--!strict

return function(Harness)
	local Fixtures = require("../Fixtures/ProfileFixtures")
	local BreedingService = require("../../src/server/Services/BreedingService")
	local GeneRegistry = require("../../src/shared/Genetics/GeneRegistry")
	local Catalog = Fixtures.Catalog
	local NOW = 1_700_000_000

	local function setup(userId: number)
		local store = Fixtures.MockDataStore.new()
		local profileService =
			Fixtures.newService(Fixtures.newRepository(store, `breeding-{userId}`, { now = NOW }))
		Harness.expect(profileService.LoadProfile(userId).ok)
		local parents = {}
		for index, className in { "Tide", "Gale" } do
			local definition = Catalog.getByClass(className)
			local genomes = GeneRegistry.defaultGenomes(className)
			parents[index] = {
				schemaVersion = 3,
				id = `critter:breeding-parent-{index}`,
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
			}
		end
		Harness.expect(profileService.UpdateProfile(userId, function(profile)
			for _, parent in parents do
				profile.ownedCritters[parent.id] = parent
			end
			return { ok = true, value = true }
		end).ok)
		local service = BreedingService.new({
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
				return "collision"
			end,
			now = function()
				return NOW
			end,
			incubationSeconds = 300,
		})
		return profileService, service, parents, store
	end

	local function count(map): number
		local total = 0
		for _ in map do
			total += 1
		end
		return total
	end

	Harness.test("breeding late retry survives pruned operation receipt", function()
		local profileService, service, parents = setup(721)
		local revision = profileService.ReadProfile(721).value.revision
		local first = service.Breed(721, parents[1].id, parents[2].id, "breed.durable", revision)
		Harness.expect(first.ok)
		Harness.equal(first.value.egg.schemaVersion, 1)
		Harness.equal(first.value.egg.geneticsMode, nil)
		Harness.expect(profileService.UpdateProfile(721, function(profile)
			profile.breedingOperationsById["breed.durable"] = nil
			for index, commandId in profile.breedingOperationOrder do
				if commandId == "breed.durable" then
					table.remove(profile.breedingOperationOrder, index)
					break
				end
			end
			return { ok = true, value = true }
		end).ok)

		local retried = service.Breed(
			721,
			parents[1].id,
			parents[2].id,
			"breed.durable",
			profileService.ReadProfile(721).value.revision
		)
		Harness.expect(retried.ok)
		Harness.expect(retried.value.duplicate)
		Harness.equal(retried.value.egg.eggId, first.value.egg.eggId)
		local profile = profileService.ReadProfile(721).value
		Harness.equal(count(profile.eggs), 1)
		Harness.equal(profile.ownedCritters[parents[1].id].breeding.successfulBreedCount, 1)
		Harness.equal(profile.ownedCritters[parents[2].id].breeding.successfulBreedCount, 1)
	end)

	Harness.test("breeding rejects generated egg ID collision without partial mutation", function()
		local profileService, service, parents = setup(722)
		local first = service.Breed(
			722,
			parents[1].id,
			parents[2].id,
			"breed.first",
			profileService.ReadProfile(722).value.revision
		)
		Harness.expect(first.ok)
		local before = profileService.ReadProfile(722).value
		local collided =
			service.Breed(722, parents[1].id, parents[2].id, "breed.second", before.revision)
		Harness.expect(Harness.hasError(collided, "DUPLICATE_EGG_ID"))
		local after = profileService.ReadProfile(722).value
		Harness.equal(count(after.eggs), 1)
		Harness.equal(
			after.ownedCritters[parents[1].id].breeding.successfulBreedCount,
			before.ownedCritters[parents[1].id].breeding.successfulBreedCount
		)
		Harness.equal(after.breedingOperationsById["breed.second"], nil)
	end)

	Harness.test("breeding save rejection leaves no partial egg or parent counts", function()
		local profileService, service, parents, store = setup(723)
		local revision = profileService.ReadProfile(723).value.revision
		store.failNext(3)
		local failed = service.Breed(723, parents[1].id, parents[2].id, "breed.failed", revision)
		Harness.expect(not failed.ok)
		Harness.equal(profileService.GetOwnershipLock(parents[1].id), nil)
		Harness.equal(profileService.GetOwnershipLock(parents[2].id), nil)
		local after = profileService.ReadProfile(723).value
		Harness.equal(count(after.eggs), 0)
		Harness.equal(after.ownedCritters[parents[1].id].breeding.successfulBreedCount, 0)
		Harness.equal(after.ownedCritters[parents[2].id].breeding.successfulBreedCount, 0)
		Harness.equal(after.breedingOperationsById["breed.failed"], nil)

		local retried = service.Breed(723, parents[1].id, parents[2].id, "breed.failed", revision)
		Harness.expect(retried.ok)
		Harness.equal(count(profileService.ReadProfile(723).value.eggs), 1)
	end)

	Harness.test("concurrent breeding permits one mutation", function()
		local profileService, service, parents, store = setup(724)
		local revision = profileService.ReadProfile(724).value.revision
		store.yieldOnUpdate(true, coroutine.yield)
		local results = {}
		local first = coroutine.create(function()
			results[1] =
				service.Breed(724, parents[1].id, parents[2].id, "breed.concurrent.1", revision)
		end)
		local second = coroutine.create(function()
			results[2] =
				service.Breed(724, parents[1].id, parents[2].id, "breed.concurrent.2", revision)
		end)
		Harness.expect(coroutine.resume(first))
		local activeLock = profileService.GetOwnershipLock(parents[1].id)
		Harness.expect(activeLock ~= nil)
		Harness.equal(activeLock.operationType, "BREEDING")
		Harness.expect(coroutine.resume(second))
		for _ = 1, 10 do
			if coroutine.status(first) ~= "dead" then
				coroutine.resume(first)
			end
		end
		store.yieldOnUpdate(false, nil)
		Harness.equal(coroutine.status(first), "dead")
		Harness.equal(coroutine.status(second), "dead")
		Harness.expect(results[1].ok)
		Harness.expect(Harness.hasError(results[2], "COMMAND_IN_PROGRESS"))
		Harness.equal(profileService.GetOwnershipLock(parents[1].id), nil)
		local profile = profileService.ReadProfile(724).value
		Harness.equal(count(profile.eggs), 1)
		Harness.equal(profile.ownedCritters[parents[1].id].breeding.successfulBreedCount, 1)
	end)
end
