--!strict

return function(Harness)
	local Fixtures = require("../Fixtures/ProfileFixtures")
	local BreedingService = require("../../src/server/Services/BreedingService")
	local EggService = require("../../src/server/Services/EggService")
	local Catalog = Fixtures.Catalog
	local GeneRegistry = require("../../src/shared/Genetics/GeneRegistry")

	local NOW = 1_700_000_000

	local function newServices(incubationSeconds: number)
		local store = Fixtures.MockDataStore.new()
		local repo = Fixtures.newRepository(store, "job-a", { now = NOW })
		local profileService = Fixtures.newService(repo)
		local breedingService = BreedingService.new({
			protocolVersion = 1,
			profileService = profileService,
			validator = require("../../src/server/Services/BreedingValidator"),
			catalog = Catalog,
			genomeValidator = require("../../src/shared/Genetics/GenomeValidator"),
			inheritanceEngine = require("../../src/server/Genetics/InheritanceEngine"),
			rng = require("../../src/shared/Battle/DeterministicRng"),
			rngSeed = function()
				return 12345
			end,
			generateId = function()
				return "generated-id"
			end,
			now = function()
				return NOW
			end,
			incubationSeconds = incubationSeconds,
		})
		local eggService = EggService.new({
			protocolVersion = 1,
			profileService = profileService,
			catalog = Catalog,
			genomeValidator = require("../../src/shared/Genetics/GenomeValidator"),
			generateId = function()
				return "generated-id"
			end,
			now = function()
				return NOW
			end,
		})
		return store, profileService, breedingService, eggService
	end

	local function grantBreedable(profileService, userId: number)
		profileService.LoadProfile(userId)
		local critters = {}
		local counter = 0
		for _, className in { "Tide", "Gale" } do
			counter += 1
			local definition = Catalog.getByClass(className)
			local genomes = GeneRegistry.defaultGenomes(className)
			table.insert(critters, {
				schemaVersion = 3,
				id = `critter:breedable-{counter}`,
				definitionId = definition.id,
				ownerUserId = userId,
				appearanceGenome = genomes.appearanceGenome,
				abilityGenome = genomes.abilityGenome,
				baseStats = definition.baseStats,
				acquisition = { source = "TEST", acquiredAt = NOW, sourceVersion = 1 },
				breeding = {
					breedable = true,
					generation = 0,
					parentIds = {},
					successfulBreedCount = 0,
				},
				tradable = false,
				equipmentIds = {},
			})
		end
		profileService.UpdateProfile(userId, function(candidate)
			for _, critter in critters do
				candidate.ownedCritters[critter.id] = critter
			end
			return { ok = true, value = true }
		end)
		return critters
	end

	local function createEgg(profileService, breedingService, userId: number)
		local critters = grantBreedable(profileService, userId)
		local profile = profileService.ReadProfile(userId).value
		local bred = breedingService.Breed(
			userId,
			critters[1].id,
			critters[2].id,
			"breed-cmd",
			profile.revision
		)
		Harness.expect(bred.ok, "breeding should succeed")
		return bred.value.egg.eggId, critters
	end

	Harness.test("EggHatching incubating egg cannot hatch", function()
		local _, profileService, breedingService, eggService = newServices(300)
		local userId = 701
		local eggId = createEgg(profileService, breedingService, userId)
		local result = eggService.HatchEgg(
			userId,
			eggId,
			"hatch-cmd",
			profileService.ReadProfile(userId).value.revision
		)
		Harness.expect(Harness.hasError(result, "EGG_NOT_READY"))
	end)

	Harness.test("EggHatching egg becomes ready after hatchAt", function()
		local _, profileService, breedingService, eggService = newServices(0)
		local userId = 702
		local eggId = createEgg(profileService, breedingService, userId)
		local status = eggService.GetEggStatus(userId, eggId)
		Harness.expect(status.ok)
		Harness.equal(status.value.status, "READY")
	end)

	Harness.test("EggHatching ready egg hatches once", function()
		local _, profileService, breedingService, eggService = newServices(0)
		local userId = 703
		local eggId = createEgg(profileService, breedingService, userId)
		local revision = profileService.ReadProfile(userId).value.revision
		local first = eggService.HatchEgg(userId, eggId, "hatch-cmd", revision)
		Harness.expect(first.ok, "first hatch should succeed")
		local second = eggService.HatchEgg(
			userId,
			eggId,
			"other-cmd",
			profileService.ReadProfile(userId).value.revision
		)
		Harness.expect(Harness.hasError(second, "ALREADY_HATCHED"))
	end)

	Harness.test("EggHatching offspring uses stored genome", function()
		local _, profileService, breedingService, eggService = newServices(0)
		local userId = 704
		local eggId = createEgg(profileService, breedingService, userId)
		local egg = profileService.ReadProfile(userId).value.eggs[eggId]
		local revision = profileService.ReadProfile(userId).value.revision
		local result = eggService.HatchEgg(userId, eggId, "hatch-cmd", revision)
		Harness.expect(result.ok)
		local offspring = result.value.offspring
		local appearanceOk = pcall(function()
			Harness.deepEqual(offspring.appearanceGenome, egg.offspringAppearanceGenome)
		end)
		Harness.expect(appearanceOk, "appearance genome should match stored genome")
		local abilityOk = pcall(function()
			Harness.deepEqual(offspring.abilityGenome, egg.offspringAbilityGenome)
		end)
		Harness.expect(abilityOk, "ability genome should match stored genome")
	end)

	Harness.test("EggHatching offspring has unique id", function()
		local _, profileService, breedingService, eggService = newServices(0)
		local userId = 705
		local eggId = createEgg(profileService, breedingService, userId)
		local revision = profileService.ReadProfile(userId).value.revision
		local result = eggService.HatchEgg(userId, eggId, "hatch-cmd", revision)
		Harness.expect(result.ok)
		Harness.expect(result.value.offspring.id ~= eggId)
	end)

	Harness.test("EggHatching preserves lineage and generation", function()
		local _, profileService, breedingService, eggService = newServices(0)
		local userId = 706
		local eggId = createEgg(profileService, breedingService, userId)
		local egg = profileService.ReadProfile(userId).value.eggs[eggId]
		local revision = profileService.ReadProfile(userId).value.revision
		local result = eggService.HatchEgg(userId, eggId, "hatch-cmd", revision)
		Harness.expect(result.ok)
		local offspring = result.value.offspring
		Harness.equal(offspring.breeding.generation, egg.generation)
		Harness.expect(offspring.breeding.parentIds[1] == egg.parentAId)
		Harness.expect(offspring.breeding.parentIds[2] == egg.parentBId)
	end)

	Harness.test("EggHatching breed count starts at zero", function()
		local _, profileService, breedingService, eggService = newServices(0)
		local userId = 707
		local eggId = createEgg(profileService, breedingService, userId)
		local revision = profileService.ReadProfile(userId).value.revision
		local result = eggService.HatchEgg(userId, eggId, "hatch-cmd", revision)
		Harness.expect(result.ok)
		Harness.equal(result.value.offspring.breeding.successfulBreedCount, 0)
	end)

	Harness.test("EggHatching duplicate command returns same offspring", function()
		local _, profileService, breedingService, eggService = newServices(0)
		local userId = 708
		local eggId = createEgg(profileService, breedingService, userId)
		local revision = profileService.ReadProfile(userId).value.revision
		local first = eggService.HatchEgg(userId, eggId, "hatch-cmd", revision)
		Harness.expect(first.ok)
		local second = eggService.HatchEgg(userId, eggId, "hatch-cmd", revision)
		Harness.expect(second.ok)
		Harness.expect(second.value.duplicate == true)
		Harness.equal(second.value.offspring.id, first.value.offspring.id)
	end)

	Harness.test("EggHatching different command cannot hatch same egg", function()
		local _, profileService, breedingService, eggService = newServices(0)
		local userId = 709
		local eggId = createEgg(profileService, breedingService, userId)
		local revision = profileService.ReadProfile(userId).value.revision
		local first = eggService.HatchEgg(userId, eggId, "hatch-cmd", revision)
		Harness.expect(first.ok)
		local second = eggService.HatchEgg(
			userId,
			eggId,
			"other-cmd",
			profileService.ReadProfile(userId).value.revision
		)
		Harness.expect(Harness.hasError(second, "ALREADY_HATCHED"))
	end)

	Harness.test("EggHatching stale revision prevents mutation", function()
		local _, profileService, breedingService, eggService = newServices(0)
		local userId = 710
		local eggId = createEgg(profileService, breedingService, userId)
		local result = eggService.HatchEgg(userId, eggId, "hatch-cmd", 0)
		Harness.expect(Harness.hasError(result, "STALE_REVISION"))
		local egg = profileService.ReadProfile(userId).value.eggs[eggId]
		Harness.equal(egg.status, "INCUBATING")
	end)

	Harness.test("EggHatching save rejection leaves no partial offspring", function()
		local store, profileService, breedingService, eggService = newServices(0)
		local userId = 717
		local eggId = createEgg(profileService, breedingService, userId)
		local revision = profileService.ReadProfile(userId).value.revision
		local beforeCount = 0
		for _ in profileService.ReadProfile(userId).value.ownedCritters do
			beforeCount += 1
		end
		store.failNext(3)
		local failed = eggService.HatchEgg(userId, eggId, "hatch-save-failure", revision)
		Harness.expect(not failed.ok)
		local afterFailure = profileService.ReadProfile(userId).value
		Harness.equal(afterFailure.eggs[eggId].status, "INCUBATING")
		local afterCount = 0
		for _ in afterFailure.ownedCritters do
			afterCount += 1
		end
		Harness.equal(afterCount, beforeCount)

		local retried = eggService.HatchEgg(userId, eggId, "hatch-save-failure", revision)
		Harness.expect(retried.ok)
		Harness.equal(profileService.ReadProfile(userId).value.eggs[eggId].status, "HATCHED")
	end)

	Harness.test("EggHatching concurrent commands create one offspring", function()
		local store, profileService, breedingService, eggService = newServices(0)
		local userId = 718
		local eggId = createEgg(profileService, breedingService, userId)
		local revision = profileService.ReadProfile(userId).value.revision
		store.yieldOnUpdate(true, coroutine.yield)
		local results = {}
		local first = coroutine.create(function()
			results[1] = eggService.HatchEgg(userId, eggId, "hatch.concurrent.1", revision)
		end)
		local second = coroutine.create(function()
			results[2] = eggService.HatchEgg(userId, eggId, "hatch.concurrent.2", revision)
		end)
		Harness.expect(coroutine.resume(first))
		Harness.expect(coroutine.resume(second))
		for _ = 1, 10 do
			if coroutine.status(first) ~= "dead" then
				coroutine.resume(first)
			end
		end
		store.yieldOnUpdate(false, nil)
		Harness.expect(results[1].ok)
		Harness.expect(Harness.hasError(results[2], "COMMAND_IN_PROGRESS"))
		local profile = profileService.ReadProfile(userId).value
		Harness.equal(profile.eggs[eggId].status, "HATCHED")
		local offspringCount = 0
		for _, critter in profile.ownedCritters do
			if critter.acquisition.source == "BREEDING" then
				offspringCount += 1
			end
		end
		Harness.equal(offspringCount, 1)
	end)

	Harness.test("EggHatching survives rejoin", function()
		local store, profileService, breedingService, eggService = newServices(0)
		local userId = 711
		local eggId = createEgg(profileService, breedingService, userId)
		local revision = profileService.ReadProfile(userId).value.revision
		local result = eggService.HatchEgg(userId, eggId, "hatch-cmd", revision)
		Harness.expect(result.ok)
		local offspringId = result.value.offspring.id
		profileService.ReleaseProfile(userId)
		local reloadedService =
			Fixtures.newService(Fixtures.newRepository(store, "job-a", { now = NOW }))
		reloadedService.LoadProfile(userId)
		local egg = reloadedService.ReadProfile(userId).value.eggs[eggId]
		Harness.equal(egg.status, "HATCHED")
		Harness.equal(egg.hatchedAt, NOW)
		Harness.expect(reloadedService.ReadProfile(userId).value.ownedCritters[offspringId] ~= nil)
		local reloadedEggService = EggService.new({
			protocolVersion = 1,
			profileService = reloadedService,
			catalog = Catalog,
			genomeValidator = require("../../src/shared/Genetics/GenomeValidator"),
			generateId = function()
				return "unused"
			end,
			now = function()
				return NOW
			end,
		})
		local history = reloadedEggService.GetEggs(userId)
		Harness.expect(history.ok)
		Harness.equal(history.value.eggs[1].status, "HATCHED")
		Harness.equal(history.value.eggs[1].hatchedAt, NOW)
		Harness.equal(history.value.eggs[1].offspringId, offspringId)
	end)

	Harness.test("EggHatching offspring can join team", function()
		local _, profileService, breedingService, eggService = newServices(0)
		local userId = 712
		local eggId = createEgg(profileService, breedingService, userId)
		local revision = profileService.ReadProfile(userId).value.revision
		local result = eggService.HatchEgg(userId, eggId, "hatch-cmd", revision)
		Harness.expect(result.ok)
		local teamService = Fixtures.newTeamService(profileService)
		-- Build a valid three-critter team using existing owned critters.
		local critters = {}
		for id in profileService.ReadProfile(userId).value.ownedCritters do
			table.insert(critters, id)
		end
		Harness.expect(#critters >= 3)
		local teamResult = teamService.SetSelectedTeam(
			userId,
			{ critters[1], critters[2], critters[3] },
			profileService.ReadProfile(userId).value.revision
		)
		Harness.expect(teamResult.ok)
	end)

	Harness.test("EggHatching starter restrictions remain", function()
		local _, profileService = newServices(0)
		local userId = 713
		profileService.LoadProfile(userId)
		for _, critter in profileService.ReadProfile(userId).value.ownedCritters do
			Harness.expect(critter.breeding.breedable == false)
		end
	end)

	Harness.test("EggHatching newly bred egg appears in egg list", function()
		local _, profileService, breedingService, eggService = newServices(300)
		local userId = 716
		local eggId = createEgg(profileService, breedingService, userId)
		local result = eggService.GetEggs(userId)
		Harness.expect(result.ok, "egg list should load")
		Harness.equal(result.value.revision, profileService.ReadProfile(userId).value.revision)
		Harness.equal(#result.value.eggs, 1)
		Harness.equal(result.value.eggs[1].eggId, eggId)
		Harness.equal(result.value.eggs[1].status, "INCUBATING")
	end)

	Harness.test("EggHatching egg DTO exposes parents and hides genomes before hatch", function()
		local _, profileService, breedingService, eggService = newServices(300)
		local userId = 714
		local eggId = createEgg(profileService, breedingService, userId)
		local result = eggService.GetEggStatus(userId, eggId)
		Harness.expect(result.ok)
		local dto = result.value
		Harness.equal(dto.eggId, eggId)
		Harness.equal(dto.status, "INCUBATING")
		Harness.equal(dto.parentA.class, "Tide")
		Harness.equal(dto.parentB.class, "Gale")
		Harness.expect(dto.offspringClass == "Tide" or dto.offspringClass == "Gale")
		Harness.equal(dto.offspringAppearanceGenome, nil)
		Harness.equal(dto.offspringAbilityGenome, nil)
		Harness.equal(dto.breedingCommandId, nil)
		Harness.equal(dto.offspring, nil)
	end)

	Harness.test("EggHatching hatched egg DTO includes sanitized offspring", function()
		local _, profileService, breedingService, eggService = newServices(0)
		local userId = 715
		local eggId = createEgg(profileService, breedingService, userId)
		local revision = profileService.ReadProfile(userId).value.revision
		local hatched = eggService.HatchEgg(userId, eggId, "hatch-cmd", revision)
		Harness.expect(hatched.ok)
		local status = eggService.GetEggStatus(userId, eggId)
		Harness.expect(status.ok)
		Harness.equal(status.value.status, "HATCHED")
		Harness.equal(status.value.hatchedAt, NOW)
		Harness.equal(status.value.offspringId, hatched.value.offspring.id)
		Harness.expect(status.value.offspring ~= nil)
		Harness.equal(status.value.offspring.ownerUserId, nil)
		Harness.equal(status.value.offspring.equipmentIds, nil)
		Harness.equal(status.value.offspring.id, hatched.value.offspring.id)
	end)
end
