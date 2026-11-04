--!strict

return function(Harness)
	local Fixtures = require("../Fixtures/ProfileFixtures")
	local BreedingService = require("../../src/server/Services/BreedingService")
	local EggService = require("../../src/server/Services/EggService")
	local BreedingValidator = require("../../src/server/Services/BreedingValidator")
	local GeneticsConfig = require("../../src/server/Config/GeneticsConfig")
	local ConceptionRng = require("../../src/server/Genetics/ConceptionRng")
	local InheritanceEngine = require("../../src/server/Genetics/InheritanceEngine")
	local ClassInheritancePolicy = require("../../src/server/Genetics/ClassInheritancePolicy")
	local MutationEngine = require("../../src/server/Genetics/MutationEngine")
	local MutationPolicy = require("../../src/server/Genetics/MutationPolicy")
	local GeneRegistry = require("../../src/shared/Genetics/GeneRegistry")
	local GenomeValidator = require("../../src/shared/Genetics/GenomeValidator")
	local GenotypeExpressor = require("../../src/shared/Genetics/GenotypeExpressor")
	local DeterministicRng = require("../../src/shared/Battle/DeterministicRng")
	local DeckBuilder = require("../../src/shared/Battle/DeckBuilder")

	local NOW = 1_700_000_000

	local function count(map): number
		local total = 0
		for _ in map do
			total += 1
		end
		return total
	end

	local function newEnvironment(userId: number, classes, mutationEnabled: boolean, seed: number)
		local store = Fixtures.MockDataStore.new()
		local profileService =
			Fixtures.newService(Fixtures.newRepository(store, `classic-{userId}`, { now = NOW }))
		Harness.expect(profileService.LoadProfile(userId).ok)
		local parents = {}
		local parentNames = { "alpha", "beta", "gamma", "delta", "epsilon", "zeta" }
		for index, className in classes do
			local id = `critter:{parentNames[index]}`
			local definition = Fixtures.Catalog.getByClass(className)
			local genomes = GeneRegistry.founderGenomes(className)
			parents[index] = {
				schemaVersion = 3,
				id = id,
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
		local generated = 0
		local config = GeneticsConfig.classic(mutationEnabled)
		local breeding = BreedingService.new({
			protocolVersion = 1,
			profileService = profileService,
			validator = BreedingValidator,
			catalog = Fixtures.Catalog,
			genomeValidator = GenomeValidator,
			inheritanceEngine = InheritanceEngine,
			classInheritancePolicy = ClassInheritancePolicy,
			mutationEngine = MutationEngine,
			mutationPolicy = MutationPolicy,
			genotypeExpressor = GenotypeExpressor,
			conceptionRng = ConceptionRng,
			geneticsConfig = config,
			rng = DeterministicRng,
			rngSeed = function()
				return 99
			end,
			conceptionSeed = function()
				return seed
			end,
			generateId = function()
				generated += 1
				return `generated-{generated}`
			end,
			now = function()
				return NOW
			end,
			incubationSeconds = 0,
		})
		local eggService = EggService.new({
			protocolVersion = 1,
			profileService = profileService,
			catalog = Fixtures.Catalog,
			genomeValidator = GenomeValidator,
			genotypeExpressor = GenotypeExpressor,
			conceptionRng = ConceptionRng,
			generateId = function()
				generated += 1
				return `generated-{generated}`
			end,
			now = function()
				return NOW
			end,
		})
		return store, profileService, breeding, eggService, parents, config
	end

	local function breed(profileService, service, userId: number, parents, commandId: string)
		return service.Breed(
			userId,
			parents[1].id,
			parents[2].id,
			commandId,
			profileService.ReadProfile(userId).value.revision
		)
	end

	local function mutationCountFor(seed: number, classes, config): number
		local parentAClass = classes[1]
		local parentBClass = classes[2]
		local parentA = GeneRegistry.founderGenomes(parentAClass)
		local parentB = GeneRegistry.founderGenomes(parentBClass)
		local classSeed =
			ConceptionRng.derive(seed, "critter:alpha", "critter:beta", config, "CLASS")
		local inheritanceSeed =
			ConceptionRng.derive(seed, "critter:alpha", "critter:beta", config, "RECOMBINATION")
		local mutationSeed =
			ConceptionRng.derive(seed, "critter:alpha", "critter:beta", config, "MUTATION")
		local classResult = ClassInheritancePolicy.resolve(parentAClass, parentBClass, classSeed)
		local inherited = InheritanceEngine.inheritWithPolicy("CLASSIC_INHERITANCE_V1", {
			class = parentAClass,
			appearanceGenome = parentA.appearanceGenome,
			abilityGenome = parentA.abilityGenome,
		}, {
			class = parentBClass,
			appearanceGenome = parentB.appearanceGenome,
			abilityGenome = parentB.abilityGenome,
		}, classResult.value.class, inheritanceSeed, { contentVersion = 1 })
		local mutated = MutationEngine.mutate(
			inherited.value.appearanceGenome,
			inherited.value.abilityGenome,
			classResult.value.class,
			mutationSeed,
			{
				version = MutationPolicy.Version,
				enabled = true,
				probabilityNumerator = 2,
				probabilityDenominator = 100,
			}
		)
		return mutated.value.trace.mutationCount
	end

	local function findSeed(minimumMutations: number): number
		local config = GeneticsConfig.classic(true)
		for seed = 1, 10_000 do
			if mutationCountFor(seed, { "Tide", "Gale" }, config) >= minimumMutations then
				return seed
			end
		end
		error("deterministic mutation seed was not found")
	end

	Harness.test("Classic conception persists disabled mutation metadata", function()
		local _, profileService, service, _, parents =
			newEnvironment(801, { "Tide", "Gale" }, false, 12345)
		local result = breed(profileService, service, 801, parents, "classic.disabled")
		Harness.expect(result.ok)
		local egg = result.value.egg
		Harness.equal(egg.schemaVersion, 2)
		Harness.equal(egg.geneticsMode, "CLASSIC_INHERITANCE_V1")
		Harness.equal(egg.mutationEnabled, false)
		Harness.equal(egg.mutationTrace.outcome, "DISABLED")
		Harness.equal(egg.mutationTrace.mutationCount, 0)
		Harness.equal(egg.conceptionSeed, 12345)
		Harness.expect(string.match(egg.outcomeDigest, "^g1:%x%x%x%x%x%x%x%x$") ~= nil)
		local corrupt = profileService.ReadProfile(801).value
		corrupt.eggs[egg.eggId].outcomeDigest = "g1:00000000"
		Harness.expect(
			Harness.hasError(
				Fixtures.Schema.validate(corrupt, 801, Fixtures.Catalog.allById()),
				"GENETICS_DIGEST_MISMATCH"
			)
		)
	end)

	Harness.test("Classic enabled mutation supports zero and multiple outcomes", function()
		local zeroSeed = nil
		local multipleSeed = findSeed(2)
		local config = GeneticsConfig.classic(true)
		for seed = 1, 100 do
			if mutationCountFor(seed, { "Tide", "Gale" }, config) == 0 then
				zeroSeed = seed
				break
			end
		end
		Harness.expect(zeroSeed ~= nil)
		local _, zeroProfiles, zeroService, _, zeroParents =
			newEnvironment(802, { "Tide", "Gale" }, true, zeroSeed)
		local zero = breed(zeroProfiles, zeroService, 802, zeroParents, "classic.zero")
		Harness.expect(zero.ok)
		Harness.equal(zero.value.egg.mutationTrace.mutationCount, 0)
		local _, multiProfiles, multiService, _, multiParents =
			newEnvironment(803, { "Tide", "Gale" }, true, multipleSeed)
		local multiple = breed(multiProfiles, multiService, 803, multiParents, "classic.multiple")
		Harness.expect(multiple.ok)
		Harness.expect(multiple.value.egg.mutationTrace.mutationCount >= 2)
		Harness.equal(
			#multiple.value.egg.mutationTrace.entries,
			multiple.value.egg.mutationTrace.mutationCount
		)
	end)

	Harness.test("Classic same-class and mixed-class conceptions use approved classes", function()
		local _, sameProfiles, sameService, _, sameParents =
			newEnvironment(804, { "Stone", "Stone" }, false, 91)
		local same = breed(sameProfiles, sameService, 804, sameParents, "classic.same")
		Harness.expect(same.ok)
		Harness.equal(same.value.egg.offspringClass, "Stone")
		local _, mixedProfiles, mixedService, _, mixedParents =
			newEnvironment(805, { "Tide", "Gale" }, false, 91)
		local mixed = breed(mixedProfiles, mixedService, 805, mixedParents, "classic.mixed")
		Harness.expect(mixed.ok)
		Harness.expect(
			mixed.value.egg.offspringClass == "Tide" or mixed.value.egg.offspringClass == "Gale"
		)
	end)

	Harness.test("canonical parent order makes reversed retries idempotent", function()
		local _, profileService, service, _, parents =
			newEnvironment(806, { "Tide", "Gale" }, false, 771)
		local revision = profileService.ReadProfile(806).value.revision
		local first = service.Breed(806, parents[2].id, parents[1].id, "classic.order", revision)
		Harness.expect(first.ok)
		local retry = service.Breed(806, parents[1].id, parents[2].id, "classic.order", revision)
		Harness.expect(retry.ok and retry.value.duplicate)
		Harness.equal(retry.value.egg.eggId, first.value.egg.eggId)
		Harness.deepEqual(first.value.egg.canonicalParentIds, { "critter:alpha", "critter:beta" })
		Harness.equal(count(profileService.ReadProfile(806).value.eggs), 1)
	end)

	Harness.test("fixed seed reproduces genetics and independent streams", function()
		local seed = findSeed(1)
		local _, profilesA, serviceA, _, parentsA, config =
			newEnvironment(807, { "Tide", "Gale" }, true, seed)
		local _, profilesB, serviceB, _, parentsB =
			newEnvironment(808, { "Tide", "Gale" }, true, seed)
		local first = breed(profilesA, serviceA, 807, parentsA, "classic.fixed.a")
		local second = breed(profilesB, serviceB, 808, parentsB, "classic.fixed.b")
		Harness.expect(first.ok and second.ok)
		Harness.equal(first.value.egg.offspringClass, second.value.egg.offspringClass)
		Harness.deepEqual(
			first.value.egg.offspringAppearanceGenome,
			second.value.egg.offspringAppearanceGenome
		)
		Harness.deepEqual(
			first.value.egg.offspringAbilityGenome,
			second.value.egg.offspringAbilityGenome
		)
		Harness.equal(first.value.egg.outcomeDigest, second.value.egg.outcomeDigest)
		local classSeed =
			ConceptionRng.derive(seed, parentsA[2].id, parentsA[1].id, config, "CLASS")
		local recombinationSeed =
			ConceptionRng.derive(seed, parentsA[1].id, parentsA[2].id, config, "RECOMBINATION")
		local mutationSeed =
			ConceptionRng.derive(seed, parentsA[1].id, parentsA[2].id, config, "MUTATION")
		Harness.expect(classSeed ~= recombinationSeed)
		Harness.expect(classSeed ~= mutationSeed)
		Harness.expect(recombinationSeed ~= mutationSeed)
	end)

	Harness.test("Classic hatch preserves conceived genetics without rerolls", function()
		local store, profileService, service, eggService, parents =
			newEnvironment(809, { "Tide", "Gale" }, true, findSeed(1))
		local bred = breed(profileService, service, 809, parents, "classic.hatch.breed")
		Harness.expect(bred.ok)
		local seedCallsAfterBreed = bred.value.egg.conceptionSeed
		local hatched = eggService.HatchEgg(
			809,
			bred.value.egg.eggId,
			"classic.hatch",
			profileService.ReadProfile(809).value.revision
		)
		Harness.expect(hatched.ok)
		Harness.deepEqual(
			hatched.value.offspring.appearanceGenome,
			bred.value.egg.offspringAppearanceGenome
		)
		Harness.deepEqual(
			hatched.value.offspring.abilityGenome,
			bred.value.egg.offspringAbilityGenome
		)
		Harness.equal(hatched.value.offspring.genetics.conceptionSeed, seedCallsAfterBreed)
		Harness.equal(hatched.value.offspring.genetics.outcomeDigest, bred.value.egg.outcomeDigest)
		local repeated = eggService.HatchEgg(809, bred.value.egg.eggId, "classic.hatch", 0)
		Harness.expect(repeated.ok and repeated.value.duplicate)
		Harness.equal(repeated.value.offspring.id, hatched.value.offspring.id)
		Harness.expect(profileService.ReleaseProfile(809).ok)
		local reloaded =
			Fixtures.newService(Fixtures.newRepository(store, "classic-rejoin", { now = NOW }))
		Harness.expect(reloaded.LoadProfile(809).ok)
		local persisted = reloaded.ReadProfile(809).value
		Harness.equal(
			persisted.ownedCritters[hatched.value.offspring.id].genetics.outcomeDigest,
			bred.value.egg.outcomeDigest
		)
	end)

	Harness.test("Classic command conflicts and stale revisions do not mutate", function()
		local _, profileService, service, _, parents =
			newEnvironment(810, { "Tide", "Gale" }, false, 551)
		local first = breed(profileService, service, 810, parents, "classic.conflict")
		Harness.expect(first.ok)
		local profile = profileService.ReadProfile(810).value
		local extra = Harness.clone(parents[2])
		extra.id = "critter:gamma"
		Harness.expect(profileService.UpdateProfile(810, function(candidate)
			candidate.ownedCritters[extra.id] = extra
			return { ok = true, value = true }
		end).ok)
		local conflict = service.Breed(
			810,
			parents[1].id,
			extra.id,
			"classic.conflict",
			profileService.ReadProfile(810).value.revision
		)
		Harness.expect(Harness.hasError(conflict, "COMMAND_ID_CONFLICT"))
		local stale = service.Breed(810, parents[1].id, extra.id, "classic.stale", profile.revision)
		Harness.expect(Harness.hasError(stale, "STALE_REVISION"))
		Harness.equal(count(profileService.ReadProfile(810).value.eggs), 1)
	end)

	Harness.test("Classic offspring retains legal battle deck", function()
		local _, profileService, service, eggService, parents =
			newEnvironment(811, { "Tide", "Gale" }, true, findSeed(1))
		local bred = breed(profileService, service, 811, parents, "classic.battle.breed")
		local hatched = eggService.HatchEgg(
			811,
			bred.value.egg.eggId,
			"classic.battle.hatch",
			profileService.ReadProfile(811).value.revision
		)
		Harness.expect(hatched.ok)
		local expression = GenotypeExpressor.express(
			hatched.value.offspring.appearanceGenome,
			hatched.value.offspring.abilityGenome,
			bred.value.egg.offspringClass,
			1
		)
		Harness.expect(expression.ok)
		local cards = expression.value.phenotype.abilities.cardDefinitionIds
		Harness.equal(#cards, 4)
		local deck = DeckBuilder.build(1, {
			{ sourceCritterInstanceId = hatched.value.offspring.id, definitionIds = cards },
		}, {
			AbilitiesPerCritter = 4,
			CopiesPerCard = 2,
			TeamDeckSize = 8,
		})
		Harness.expect(deck.ok)
		Harness.equal(#deck.value.cardInstances, 8)
	end)

	Harness.test("normal services persist a valid generation three family line", function()
		local _, profileService, service, eggService, founders =
			newEnvironment(812, { "Stone", "Tide", "Gale", "Shade" }, true, 6201)
		local function conceiveAndHatch(parentAId: string, parentBId: string, generation: number)
			local command = `classic.chain.breed.{generation}`
			local conceived = service.Breed(
				812,
				parentAId,
				parentBId,
				command,
				profileService.ReadProfile(812).value.revision
			)
			Harness.expect(conceived.ok)
			Harness.equal(conceived.value.egg.generation, generation)
			local hatched = eggService.HatchEgg(
				812,
				conceived.value.egg.eggId,
				`classic.chain.hatch.{generation}`,
				profileService.ReadProfile(812).value.revision
			)
			Harness.expect(hatched.ok)
			Harness.equal(hatched.value.offspring.breeding.generation, generation)
			local expectedA, expectedB = ConceptionRng.canonicalParents(parentAId, parentBId)
			Harness.deepEqual(hatched.value.offspring.breeding.parentIds, { expectedA, expectedB })
			return hatched.value.offspring
		end

		local generationOne = conceiveAndHatch(founders[1].id, founders[2].id, 1)
		local generationTwo = conceiveAndHatch(generationOne.id, founders[3].id, 2)
		local generationThree = conceiveAndHatch(generationTwo.id, founders[4].id, 3)
		Harness.equal(generationThree.breeding.generation, 3)
		Harness.equal(count(profileService.ReadProfile(812).value.eggs), 3)
		print(
			`G6 CHAIN g1={generationOne.id}:{Fixtures.Catalog.getById(generationOne.definitionId).class} g2={generationTwo.id}:{Fixtures.Catalog.getById(
				generationTwo.definitionId
			).class} g3={generationThree.id}:{Fixtures.Catalog.getById(
				generationThree.definitionId
			).class}`
		)
	end)

	Harness.test(
		"Classic v1 sampling matches inheritance and two-percent mutation policy",
		function()
			local parentA = {
				class = "Stone",
				appearanceGenome = GeneRegistry.founderGenomes("Stone").appearanceGenome,
				abilityGenome = GeneRegistry.founderGenomes("Stone").abilityGenome,
			}
			local parentB = {
				class = "Tide",
				appearanceGenome = GeneRegistry.founderGenomes("Tide").appearanceGenome,
				abilityGenome = GeneRegistry.founderGenomes("Tide").abilityGenome,
			}
			local parentCounts = { A = 0, B = 0 }
			local positionCounts = { D = 0, R1 = 0, R2 = 0 }
			local mutations = 0
			local mutationPositions = 0
			local zeroMutationOffspring = 0
			local multipleMutationOffspring = 0
			for seed = 1, 2_000 do
				local inherited = InheritanceEngine.inheritWithPolicy(
					"CLASSIC_INHERITANCE_V1",
					parentA,
					parentB,
					"Stone",
					seed,
					{ contentVersion = 1 }
				)
				Harness.expect(inherited.ok)
				for _, selection in inherited.value.trace.selections do
					parentCounts[selection.parent] += 1
					positionCounts[selection.parentPosition] += 1
				end
				local mutated = MutationEngine.mutate(
					inherited.value.appearanceGenome,
					inherited.value.abilityGenome,
					"Stone",
					seed,
					{
						version = MutationPolicy.Version,
						enabled = true,
						probabilityNumerator = 2,
						probabilityDenominator = 100,
					}
				)
				Harness.expect(mutated.ok)
				local mutationCount = mutated.value.trace.mutationCount
				mutations += mutationCount
				mutationPositions += mutated.value.trace.eligiblePositionCount
				if mutationCount == 0 then
					zeroMutationOffspring += 1
				elseif mutationCount > 1 then
					multipleMutationOffspring += 1
				end
			end
			local inheritedPositions = parentCounts.A + parentCounts.B
			Harness.expect(math.abs(parentCounts.A / inheritedPositions - 0.5) < 0.01)
			Harness.expect(math.abs(positionCounts.D / inheritedPositions - 0.75) < 0.01)
			Harness.expect(math.abs(positionCounts.R1 / inheritedPositions - 0.1875) < 0.01)
			Harness.expect(math.abs(positionCounts.R2 / inheritedPositions - 0.0625) < 0.01)
			local observedMutationRate = mutations / mutationPositions
			Harness.expect(math.abs(observedMutationRate - 0.02) < 0.003)
			Harness.expect(zeroMutationOffspring > 0)
			Harness.expect(multipleMutationOffspring > 0)
			print(
				`G6 SAMPLE parentA={parentCounts.A / inheritedPositions} D={positionCounts.D / inheritedPositions} R1={positionCounts.R1 / inheritedPositions} R2={positionCounts.R2 / inheritedPositions} mutation={observedMutationRate} zero={zeroMutationOffspring} multiple={multipleMutationOffspring}`
			)
		end
	)

	Harness.test("recessive mutation can transmit and become dominant later", function()
		local config = GeneticsConfig.classic(true)
		local sourceSeed = findSeed(1)
		local parentA = GeneRegistry.founderGenomes("Tide")
		local parentB = GeneRegistry.founderGenomes("Gale")
		local classSeed =
			ConceptionRng.derive(sourceSeed, "critter:alpha", "critter:beta", config, "CLASS")
		local inheritanceSeed = ConceptionRng.derive(
			sourceSeed,
			"critter:alpha",
			"critter:beta",
			config,
			"RECOMBINATION"
		)
		local mutationSeed =
			ConceptionRng.derive(sourceSeed, "critter:alpha", "critter:beta", config, "MUTATION")
		local classResult = ClassInheritancePolicy.resolve("Tide", "Gale", classSeed)
		local inherited = InheritanceEngine.inheritWithPolicy("CLASSIC_INHERITANCE_V1", {
			class = "Tide",
			appearanceGenome = parentA.appearanceGenome,
			abilityGenome = parentA.abilityGenome,
		}, {
			class = "Gale",
			appearanceGenome = parentB.appearanceGenome,
			abilityGenome = parentB.abilityGenome,
		}, classResult.value.class, inheritanceSeed, { contentVersion = 1 })
		local mutated = MutationEngine.mutate(
			inherited.value.appearanceGenome,
			inherited.value.abilityGenome,
			classResult.value.class,
			mutationSeed,
			{
				version = MutationPolicy.Version,
				enabled = true,
				probabilityNumerator = 2,
				probabilityDenominator = 100,
			}
		)
		Harness.expect(mutated.value.trace.mutationCount > 0)
		local mutation = nil
		for _, entry in mutated.value.trace.entries do
			if entry.outcome == "MUTATED" then
				mutation = entry
				break
			end
		end
		Harness.expect(mutation ~= nil)
		local carrier = {
			class = classResult.value.class,
			appearanceGenome = mutated.value.appearanceGenome,
			abilityGenome = mutated.value.abilityGenome,
		}
		local ordinaryGenomes = GeneRegistry.defaultGenomes(carrier.class)
		local ordinary = {
			class = carrier.class,
			appearanceGenome = ordinaryGenomes.appearanceGenome,
			abilityGenome = ordinaryGenomes.abilityGenome,
		}
		local emerged = false
		for seed = 1, 1_000 do
			local descendant = InheritanceEngine.inheritWithPolicy(
				"CLASSIC_INHERITANCE_V1",
				carrier,
				ordinary,
				carrier.class,
				seed,
				{ contentVersion = 1 }
			)
			Harness.expect(descendant.ok)
			local genome = if mutation.layer == "APPEARANCE"
				then descendant.value.appearanceGenome
				else descendant.value.abilityGenome
			if genome.slots[mutation.locus].D == mutation.newGeneId then
				emerged = true
				break
			end
		end
		Harness.expect(emerged)
		print(
			`G6 MUTATION seed={sourceSeed} {mutation.layer}.{mutation.locus}.{mutation.position} {mutation.previousGeneId}->{mutation.newGeneId} emergedDominant={tostring(
				emerged
			)}`
		)
	end)
end
