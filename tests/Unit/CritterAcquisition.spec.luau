--!strict

return function(Harness)
	local Fixtures = require("../Fixtures/ProfileFixtures")
	local AcquisitionFixtures = require("../Fixtures/AcquisitionFixtures")
	local CritterAcquisitionService = require("../../src/server/Services/CritterAcquisitionService")
	local CritterInstanceFactory = require("../../src/server/Persistence/CritterInstanceFactory")
	local VariantGenerator = require("../../src/server/Genetics/VariantGenerator")
	local BreedingService = require("../../src/server/Services/BreedingService")
	local TrainingBattleInputAdapter =
		require("../../src/server/Services/TrainingBattleInputAdapter")
	local BreedingValidator = require("../../src/server/Services/BreedingValidator")
	local InheritanceEngine = require("../../src/server/Genetics/InheritanceEngine")
	local CritterCatalog = require("../../src/shared/Definitions/CritterCatalog")
	local CardCatalog = require("../../src/shared/Definitions/CardCatalog")
	local TrainingGrounds = require("../../src/shared/Definitions/TrainingGrounds")
	local GenomeValidator = require("../../src/shared/Genetics/GenomeValidator")
	local AbilityResolver = require("../../src/shared/Genetics/AbilityResolver")
	local BattleFactory = require("../../src/shared/Battle/BattleFactory")
	local DeterministicRng = require("../../src/shared/Battle/DeterministicRng")
	local Deck = require("../../src/shared/Battle/Deck")
	local DomainValidator = require("../../src/shared/Validation/DomainValidator")
	local ProfileMigrations = require("../../src/server/Persistence/ProfileMigrations")

	local NEVER = { kind = "CLIENT", source = "CLIENT" }

	local function setup(userId: number, options)
		local env = AcquisitionFixtures.new(options)
		AcquisitionFixtures.load(env, userId)
		return env
	end

	local function ownedCount(env, userId: number)
		local total = 0
		for _ in env.profileService.ReadProfile(userId).value.ownedCritters do
			total += 1
		end
		return total
	end

	local function count(values)
		local total = 0
		for _ in values do
			total += 1
		end
		return total
	end

	Harness.test("acquisition requires server authorization", function()
		local env = setup(901)
		local before = ownedCount(env, 901)

		local candidate = env.service.GenerateCandidate(
			AcquisitionFixtures.request("COMMON_FOUNDERS", 1, { context = NEVER })
		)
		Harness.expect(Harness.hasError(candidate, "UNAUTHORIZED_GENERATION"))

		local clientSource = env.service.GenerateCandidate(
			AcquisitionFixtures.request(
				"COMMON_FOUNDERS",
				1,
				{ context = { kind = "SERVER", source = "CLIENT" } }
			)
		)
		Harness.expect(Harness.hasError(clientSource, "UNAUTHORIZED_GENERATION"))

		local granted = env.service.GrantCritter(
			901,
			AcquisitionFixtures.request("COMMON_FOUNDERS", 1, { context = NEVER })
		)
		Harness.expect(Harness.hasError(granted, "UNAUTHORIZED_GRANT"))
		Harness.equal(ownedCount(env, 901), before)
	end)

	Harness.test("grant creates one breedable Critter with persisted source metadata", function()
		local env = setup(902)
		local before = ownedCount(env, 902)
		local request = AcquisitionFixtures.request("COMMON_FOUNDERS", 101, { class = "Stone" })
		local candidate = env.service.GenerateCandidate(request)
		Harness.expect(candidate.ok)
		local result = env.service.GrantCritter(902, request)
		Harness.expect(result.ok)
		Harness.expect(result.value.duplicate == false)
		Harness.equal(ownedCount(env, 902), before + 1)

		local critter = result.value.critter
		local definition = CritterCatalog.getByClass("Stone")
		Harness.expect(string.match(critter.id, "^critter:") ~= nil)
		Harness.equal(critter.definitionId, definition.id)
		Harness.equal(critter.ownerUserId, 902)
		Harness.deepEqual(critter.baseStats, definition.baseStats)
		Harness.deepEqual(critter.appearanceGenome, candidate.value.appearanceGenome)
		Harness.deepEqual(critter.abilityGenome, candidate.value.abilityGenome)
		Harness.equal(critter.acquisition.source, "ACQUISITION.COMMON_FOUNDERS")
		Harness.equal(critter.acquisition.acquiredAt, AcquisitionFixtures.NOW)
		Harness.equal(critter.acquisition.sourceVersion, 1)
		Harness.equal(critter.breeding.breedable, true)
		Harness.equal(critter.breeding.generation, 0)
		Harness.equal(critter.breeding.successfulBreedCount, 0)
		Harness.equal(critter.breeding.parentIds[1], nil)
		Harness.equal(critter.tradable, false)
		Harness.equal(critter.equipmentIds[1], nil)

		local abilities = AbilityResolver.resolve(critter.abilityGenome, "Stone")
		Harness.expect(abilities.ok)
		Harness.equal(#abilities.value.abilityIds, 4)

		local profile = env.profileService.ReadProfile(902).value
		local operation = profile.acquisitionOperationsById[request.commandId]
		Harness.expect(operation ~= nil)
		Harness.equal(operation.critterId, critter.id)
		Harness.equal(operation.poolId, "COMMON_FOUNDERS")
		Harness.equal(operation.poolVersion, 1)
		Harness.equal(operation.seed, 101)
		Harness.equal(operation.class, "Stone")
		Harness.equal(operation.grantedBy, "TEST_HARNESS")
		Harness.equal(profile.acquisitionOperationOrder[1], request.commandId)
	end)

	Harness.test("repeat grants are idempotent and conflicting reuse is rejected", function()
		local env = setup(903)
		local request = AcquisitionFixtures.request("CLASS_SPECIFIC_FOUNDERS", 202, {
			class = "Tide",
		})
		local first = env.service.GrantCritter(903, request)
		Harness.expect(first.ok)
		local afterFirst = ownedCount(env, 903)

		local duplicate = env.service.GrantCritter(903, request)
		Harness.expect(duplicate.ok)
		Harness.expect(duplicate.value.duplicate == true)
		Harness.equal(duplicate.value.critter.id, first.value.critter.id)
		Harness.equal(ownedCount(env, 903), afterFirst)

		local profile = env.profileService.ReadProfile(903).value
		Harness.equal(count(profile.acquisitionOperationsById), 1)
		Harness.equal(#profile.acquisitionOperationOrder, 1)

		local differentGrant = env.service.GrantCritter(
			903,
			AcquisitionFixtures.request("CLASS_SPECIFIC_FOUNDERS", 202, {
				class = "Tide",
				grantId = "grant.other",
			})
		)
		Harness.expect(Harness.hasError(differentGrant, "COMMAND_ID_CONFLICT"))

		local differentSeed = env.service.GrantCritter(
			903,
			AcquisitionFixtures.request("CLASS_SPECIFIC_FOUNDERS", 203, {
				class = "Tide",
				commandId = request.commandId,
			})
		)
		Harness.expect(Harness.hasError(differentSeed, "COMMAND_ID_CONFLICT"))
		Harness.equal(ownedCount(env, 903), afterFirst)
	end)

	Harness.test("distinct commands create distinct Critters and operation records", function()
		local env = setup(904)
		local first =
			env.service.GrantCritter(904, AcquisitionFixtures.request("COMMON_FOUNDERS", 301))
		local second =
			env.service.GrantCritter(904, AcquisitionFixtures.request("COMMON_FOUNDERS", 302))
		Harness.expect(first.ok and second.ok)
		Harness.expect(first.value.critter.id ~= second.value.critter.id)
		local profile = env.profileService.ReadProfile(904).value
		Harness.equal(count(profile.acquisitionOperationsById), 2)
		Harness.equal(#profile.acquisitionOperationOrder, 2)
	end)

	Harness.test("save failure leaves no partial grant", function()
		local env = setup(905)
		local before = ownedCount(env, 905)
		local saveFailure = {
			ReadProfile = function(userId)
				return env.profileService.ReadProfile(userId)
			end,
			UpdateProfile = function()
				return {
					ok = false,
					errors = { { code = "SAVE_FAILED", message = "DataStore unavailable" } },
				}
			end,
		}
		local service = CritterAcquisitionService.new({
			profileService = saveFailure,
			generateId = function()
				return "acquisition-failed"
			end,
			now = function()
				return AcquisitionFixtures.NOW
			end,
		})
		local result =
			service.GrantCritter(905, AcquisitionFixtures.request("COMMON_FOUNDERS", 401))
		Harness.expect(Harness.hasError(result, "SAVE_FAILED"))
		Harness.equal(ownedCount(env, 905), before)
		local profile = env.profileService.ReadProfile(905).value
		Harness.equal(profile.acquisitionOperationsById["cmd.COMMON_FOUNDERS.401"], nil)
	end)

	Harness.test("grant does not overwrite an owned Critter on ID collision", function()
		local env = setup(906)
		local profile = env.profileService.ReadProfile(906).value
		local starterId = profile.selectedTeam[1]
		local before = count(profile.ownedCritters)
		local service = CritterAcquisitionService.new({
			profileService = env.profileService,
			generateId = function()
				return string.gsub(starterId, "^critter:", "")
			end,
			now = function()
				return AcquisitionFixtures.NOW
			end,
		})
		local result =
			service.GrantCritter(906, AcquisitionFixtures.request("COMMON_FOUNDERS", 501))
		Harness.expect(Harness.hasError(result, "DUPLICATE_CRITTER_ID"))
		local after = env.profileService.ReadProfile(906).value
		Harness.equal(count(after.ownedCritters), before)
		Harness.equal(after.ownedCritters[starterId].acquisition.source, "STARTER")
	end)

	Harness.test("stale expected revision rejects the grant without mutation", function()
		local env = setup(907)
		local before = ownedCount(env, 907)
		local stale = env.profileService.ReadProfile(907).value.revision - 1
		local result = env.service.GrantCritter(
			907,
			AcquisitionFixtures.request("COMMON_FOUNDERS", 601, { expectedRevision = stale })
		)
		Harness.expect(Harness.hasError(result, "STALE_REVISION"))
		Harness.equal(ownedCount(env, 907), before)
	end)

	Harness.test("grant survives rejoin and duplicate retry after reload", function()
		local env = setup(908)
		local request = AcquisitionFixtures.request("CLASS_SPECIFIC_FOUNDERS", 701, {
			class = "Gale",
		})
		local granted = env.service.GrantCritter(908, request)
		Harness.expect(granted.ok)
		local genome = granted.value.critter.appearanceGenome

		local reloaded = AcquisitionFixtures.reload(env, 908)
		Harness.expect(reloaded.LoadProfile(908).ok)
		local loadedProfile = reloaded.ReadProfile(908)
		Harness.expect(loadedProfile.ok)
		local critter = loadedProfile.value.ownedCritters[granted.value.critter.id]
		Harness.expect(critter ~= nil)
		Harness.deepEqual(critter.appearanceGenome, genome)
		Harness.equal(critter.acquisition.source, "ACQUISITION.CLASS_SPECIFIC_FOUNDERS")
		Harness.expect(loadedProfile.value.acquisitionOperationsById[request.commandId] ~= nil)

		local retryService = CritterAcquisitionService.new({
			profileService = reloaded,
			generateId = function()
				return "unused"
			end,
			now = function()
				return AcquisitionFixtures.NOW
			end,
		})
		local retry = retryService.GrantCritter(908, request)
		Harness.expect(retry.ok)
		Harness.expect(retry.value.duplicate == true)
		Harness.equal(retry.value.critter.id, granted.value.critter.id)
	end)

	Harness.test("acquisitions appear in Collection Team Builder and Training Grounds", function()
		local env = setup(909)
		local granted = env.service.GrantCritter(
			909,
			AcquisitionFixtures.request("COMMON_FOUNDERS", 801, { class = "Verdant" })
		)
		Harness.expect(granted.ok)
		local critterId = granted.value.critter.id

		local collection = env.profileService.GetProfile(909)
		Harness.expect(collection.ok)
		local found = nil
		for _, critter in collection.value.ownedCritters do
			if critter.id == critterId then
				found = critter
			end
		end
		Harness.expect(found ~= nil)
		Harness.equal(found.class, "Verdant")
		Harness.equal(#found.resolvedAbilityIds, 4)

		local profile = env.profileService.ReadProfile(909).value
		local starters = {}
		for id, critter in profile.ownedCritters do
			if critter.id ~= critterId then
				table.insert(starters, id)
			end
		end
		Harness.expect(#starters >= 2)
		local team = { critterId, starters[1], starters[2] }
		local teamService = Fixtures.newTeamService(env.profileService)
		Harness.expect(teamService.SetSelectedTeam(909, team).ok)
		Harness.deepEqual(env.profileService.GetProfile(909).value.selectedTeam, team)

		local adapter = TrainingBattleInputAdapter.new({
			profileService = env.profileService,
			content = TrainingGrounds,
		})
		local input = adapter.createInput(909, 1)
		Harness.expect(input.ok)
		Harness.equal(input.value.teams[1].critterInstances[1].id, critterId)
	end)

	Harness.test("acquired Critters can breed while starters remain restricted", function()
		local env = setup(910)
		local first = env.service.GrantCritter(
			910,
			AcquisitionFixtures.request("CLASS_SPECIFIC_FOUNDERS", 901, { class = "Tide" })
		)
		local second = env.service.GrantCritter(
			910,
			AcquisitionFixtures.request("CLASS_SPECIFIC_FOUNDERS", 902, { class = "Gale" })
		)
		Harness.expect(first.ok and second.ok)

		local profile = env.profileService.ReadProfile(910).value
		for _, critter in profile.ownedCritters do
			if critter.id ~= first.value.critter.id and critter.id ~= second.value.critter.id then
				Harness.equal(critter.breeding.breedable, false)
			end
		end

		local breedingService = BreedingService.new({
			protocolVersion = 1,
			profileService = env.profileService,
			validator = BreedingValidator,
			catalog = CritterCatalog,
			genomeValidator = GenomeValidator,
			inheritanceEngine = InheritanceEngine,
			rng = DeterministicRng,
			rngSeed = function()
				return 777
			end,
			generateId = function()
				return "acquisition-egg"
			end,
			now = function()
				return AcquisitionFixtures.NOW
			end,
			incubationSeconds = 60,
		})
		local bred = breedingService.Breed(
			910,
			first.value.critter.id,
			second.value.critter.id,
			"breed-acquired",
			profile.revision
		)
		Harness.expect(bred.ok)
		Harness.equal(bred.value.egg.parentAId, first.value.critter.id)
		Harness.equal(bred.value.egg.parentBId, second.value.critter.id)
	end)

	Harness.test("generated Critters fit the 24-card BattleFactory deck", function()
		local generator = VariantGenerator.new()
		local factory = CritterInstanceFactory.new()
		local cards = CardCatalog.allById()
		local definitions = CritterCatalog.allById()
		local classes = { "Stone", "Feral", "Verdant", "Tide", "Gale", "Shade" }
		local teams = {
			{ id = "team.generated.a", ownerUserId = 921, critterInstances = {} },
			{ id = "team.generated.b", ownerUserId = 922, critterInstances = {} },
		}
		local counter = 0
		for index, className in classes do
			counter += 1
			local candidate = generator.Generate({
				poolId = "CLASS_SPECIFIC_FOUNDERS",
				seed = 500 + counter,
				class = className,
			})
			Harness.expect(candidate.ok)
			local created = factory.Create({
				id = `critter:battle-{counter}`,
				ownerUserId = if index <= 3 then 921 else 922,
				definitionId = candidate.value.definitionId,
				appearanceGenome = candidate.value.appearanceGenome,
				abilityGenome = candidate.value.abilityGenome,
				source = candidate.value.source,
				sourceVersion = candidate.value.poolVersion,
				acquiredAt = AcquisitionFixtures.NOW,
				tradable = false,
			})
			Harness.expect(created.ok)
			local team = if index <= 3 then teams[1] else teams[2]
			table.insert(team.critterInstances, created.value)
		end

		local battle = BattleFactory.create({
			battleId = "battle.acquisition.fixture",
			rngSeed = 4242,
			teams = teams,
			critterDefinitionsById = definitions,
			cardDefinitionsById = cards,
		}, { rng = DeterministicRng, deck = Deck, validator = DomainValidator })
		Harness.expect(
			battle.ok,
			`battle creation failed: {if battle.ok then "" else battle.errors[1].code}`
		)
		Harness.equal(#battle.value.cardInstances, 48)
		local perTeam = {}
		for _, card in battle.value.cardInstances do
			local teamIndex = tonumber(string.match(card.id, "^card:t(%d+):")) or 0
			perTeam[teamIndex] = (perTeam[teamIndex] or 0) + 1
		end
		Harness.equal(perTeam[1], 24)
		Harness.equal(perTeam[2], 24)
		local sourceCounts = {}
		for _, card in battle.value.cardInstances do
			sourceCounts[card.sourceCritterInstanceId] = (
				sourceCounts[card.sourceCritterInstanceId] or 0
			) + 1
		end
		for _, critterId in sourceCounts do
			Harness.equal(critterId, 8)
		end
	end)

	Harness.test("schema 4 profiles migrate to v5 acquisition tables", function()
		local profile = {
			schemaVersion = 4,
			userId = 930,
			revision = 2,
			createdAt = 1,
			updatedAt = 1,
			starterGrantVersion = 1,
			ownedCritters = {},
			selectedTeam = {},
			eggs = {},
			breedingOperationsById = {},
			breedingOperationOrder = {},
			inventory = {
				schemaVersion = 2,
				stacksByDefinitionId = {},
				uniqueItemsById = {},
				operationsById = {},
				operationOrder = {},
			},
			progression = { schemaVersion = 1, flags = {}, counters = {} },
		}
		local migrated = ProfileMigrations.migrate(profile, 5, ProfileMigrations.DefaultHooks)
		Harness.expect(migrated.ok)
		Harness.equal(migrated.value.schemaVersion, 5)
		Harness.deepEqual(migrated.value.acquisitionOperationsById, {})
		Harness.deepEqual(migrated.value.acquisitionOperationOrder, {})
		Harness.equal(profile.acquisitionOperationsById, nil)
	end)

	Harness.test("acquired Critters preserve generation zero and empty lineage", function()
		local env = setup(931)
		local result = env.service.GrantCritter(
			931,
			AcquisitionFixtures.request("CROSS_CLASS_CARRIERS", 1001, { class = "Stone" })
		)
		Harness.expect(result.ok)
		local critter = result.value.critter
		Harness.equal(critter.breeding.generation, 0)
		Harness.equal(#critter.breeding.parentIds, 0)
		Harness.equal(critter.breeding.successfulBreedCount, 0)
		Harness.equal(critter.tradable, false)
		Harness.equal(#critter.equipmentIds, 0)
	end)
end
