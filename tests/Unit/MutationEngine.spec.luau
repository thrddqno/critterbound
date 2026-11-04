--!strict

return function(Harness)
	local GeneRegistry = require("../../src/shared/Genetics/GeneRegistry")
	local GenomeValidator = require("../../src/shared/Genetics/GenomeValidator")
	local GenotypeExpressor = require("../../src/shared/Genetics/GenotypeExpressor")
	local UnbiasedRandom = require("../../src/shared/Genetics/UnbiasedRandom")
	local DeckBuilder = require("../../src/shared/Battle/DeckBuilder")
	local ClassicInheritance = require("../../src/server/Genetics/ClassicInheritancePolicy")
	local MutationEngine = require("../../src/server/Genetics/MutationEngine")
	local MutationPolicy = require("../../src/server/Genetics/MutationPolicy")

	local CLASSES = { "Stone", "Feral", "Verdant", "Tide", "Gale", "Shade" }
	local ACTIVE_ABILITY_LOCI = { "mouth", "horn", "back", "tail" }
	local RECESSIVE_POSITIONS = { "R1", "R2" }

	local function policy(numerator: number, denominator: number, enabled: boolean?)
		return {
			version = MutationPolicy.Version,
			enabled = if enabled == nil then true else enabled,
			probabilityNumerator = numerator,
			probabilityDenominator = denominator,
		}
	end

	local function mutate(className: string, seedOrState, selectedPolicy)
		local genomes = GeneRegistry.defaultGenomes(className)
		return MutationEngine.mutate(
			genomes.appearanceGenome,
			genomes.abilityGenome,
			className,
			seedOrState,
			selectedPolicy
		),
			genomes
	end

	local function parent(className: string)
		local genomes = GeneRegistry.defaultGenomes(className)
		return {
			class = className,
			appearanceGenome = genomes.appearanceGenome,
			abilityGenome = genomes.abilityGenome,
		}
	end

	local function assertDominantsAndTraitsUnchanged(result, original)
		for _, locus in GeneRegistry.AppearanceSlots do
			Harness.equal(
				result.appearanceGenome.slots[locus].D,
				original.appearanceGenome.slots[locus].D
			)
		end
		for _, locus in GeneRegistry.AbilitySlots do
			Harness.equal(
				result.abilityGenome.slots[locus].D,
				original.abilityGenome.slots[locus].D
			)
		end
		Harness.deepEqual(result.abilityGenome.slots.traits, original.abilityGenome.slots.traits)
	end

	Harness.test(
		"mutation policy defaults disabled at the proposed ten-percent test rate",
		function()
			Harness.equal(MutationPolicy.Default.version, "MUTATION_POLICY_V1")
			Harness.equal(MutationPolicy.Default.enabled, false)
			Harness.equal(MutationPolicy.Default.probabilityNumerator, 1)
			Harness.equal(MutationPolicy.Default.probabilityDenominator, 10)
			Harness.equal(MutationEngine.EligiblePositionCount, 22)
			Harness.equal(MutationEngine.MaxTraceEntries, 22)
		end
	)

	Harness.test(
		"disabled policy returns identical genomes without consuming mutation RNG",
		function()
			local result, original = mutate("Stone", 101, MutationPolicy.Default)
			Harness.expect(result.ok)
			Harness.deepEqual(result.value.appearanceGenome, original.appearanceGenome)
			Harness.deepEqual(result.value.abilityGenome, original.abilityGenome)
			Harness.equal(result.value.trace.outcome, "DISABLED")
			Harness.equal(result.value.trace.mutationCount, 0)
			Harness.equal(#result.value.trace.entries, 0)
			Harness.equal(result.value.rng.drawCount, 0)
		end
	)

	Harness.test("enabled zero rate produces no mutations", function()
		local result, original = mutate("Feral", 202, policy(0, 1))
		Harness.expect(result.ok)
		Harness.deepEqual(result.value.appearanceGenome, original.appearanceGenome)
		Harness.deepEqual(result.value.abilityGenome, original.abilityGenome)
		Harness.equal(result.value.trace.outcome, "NO_MUTATIONS")
		Harness.equal(result.value.trace.mutationCount, 0)
		Harness.equal(#result.value.trace.entries, 22)
	end)

	Harness.test("full rate mutates all 22 recessives within their registered loci", function()
		local result, original = mutate("Verdant", 303, policy(1, 1))
		Harness.expect(result.ok)
		Harness.equal(result.value.trace.mutationCount, 22)
		Harness.equal(#result.value.trace.entries, 22)
		assertDominantsAndTraitsUnchanged(result.value, original)

		for _, entry in result.value.trace.entries do
			Harness.equal(entry.outcome, "MUTATED")
			Harness.expect(entry.position == "R1" or entry.position == "R2")
			Harness.expect(entry.newGeneId ~= entry.previousGeneId)
			local definition = GeneRegistry.get(entry.newGeneId)
			Harness.expect(definition ~= nil)
			Harness.equal(definition.kind, entry.layer)
			Harness.equal(definition.slot, entry.locus)
		end
	end)

	Harness.test("same mutation seed reproduces genome RNG and bounded trace", function()
		local first = mutate("Tide", 404, policy(1, 3))
		local second = mutate("Tide", 404, policy(1, 3))
		Harness.expect(first.ok and second.ok)
		Harness.deepEqual(first, second)
		Harness.equal(first.value.trace.policyVersion, MutationPolicy.Version)
		Harness.equal(first.value.trace.rng.algorithm, "PARK_MILLER_V1")
		Harness.expect(
			first.value.trace.rng.drawCountAfter >= first.value.trace.rng.drawCountBefore
		)
		Harness.expect(#first.value.trace.entries <= MutationEngine.MaxTraceEntries)
		Harness.equal(first.value.trace.rng.state, nil)
	end)

	Harness.test("mutation uses injected bounded RNG", function()
		local draws = 0
		local random = {
			nextInteger = function(state, minimum, maximum)
				draws += 1
				return UnbiasedRandom.nextInteger(state, minimum, maximum)
			end,
		}
		local genomes = GeneRegistry.defaultGenomes("Gale")
		local result = MutationEngine.mutate(
			genomes.appearanceGenome,
			genomes.abilityGenome,
			"Gale",
			505,
			policy(1, 1),
			{ random = random }
		)
		Harness.expect(result.ok)
		Harness.equal(draws, 44)
	end)

	Harness.test("mutation rates never alter inherited pre-mutation genetics", function()
		local inherited = ClassicInheritance.inherit(parent("Stone"), parent("Shade"), "Stone", 606)
		Harness.expect(inherited.ok)
		local appearanceBefore = Harness.clone(inherited.value.appearanceGenome)
		local abilityBefore = Harness.clone(inherited.value.abilityGenome)
		local none = MutationEngine.mutate(
			inherited.value.appearanceGenome,
			inherited.value.abilityGenome,
			"Stone",
			7001,
			policy(0, 1)
		)
		local all = MutationEngine.mutate(
			inherited.value.appearanceGenome,
			inherited.value.abilityGenome,
			"Stone",
			7001,
			policy(1, 1)
		)
		Harness.expect(none.ok and all.ok)
		Harness.deepEqual(inherited.value.appearanceGenome, appearanceBefore)
		Harness.deepEqual(inherited.value.abilityGenome, abilityBefore)
		Harness.deepEqual(none.value.appearanceGenome, appearanceBefore)
		Harness.deepEqual(none.value.abilityGenome, abilityBefore)
		assertDominantsAndTraitsUnchanged(all.value, {
			appearanceGenome = appearanceBefore,
			abilityGenome = abilityBefore,
		})
	end)

	Harness.test("low configured rate permits a deterministic zero-mutation conception", function()
		local found = false
		for seed = 1, 100 do
			local result = mutate("Shade", seed, policy(1, 100))
			Harness.expect(result.ok)
			if result.value.trace.mutationCount == 0 then
				found = true
				break
			end
		end
		Harness.expect(found)
	end)

	Harness.test("mutation frequencies approach configured independent rates", function()
		local configuredRates = {
			{ numerator = 1, denominator = 10, tolerance = 0.015 },
			{ numerator = 1, denominator = 4, tolerance = 0.02 },
		}
		for _, configured in configuredRates do
			local rng = UnbiasedRandom.new(808).value
			local mutations = 0
			local samples = 1_000
			for _ = 1, samples do
				local result =
					mutate("Stone", rng, policy(configured.numerator, configured.denominator))
				Harness.expect(result.ok)
				mutations += result.value.trace.mutationCount
				rng = result.value.rng
			end
			local expected = configured.numerator / configured.denominator
			local observed = mutations / (samples * MutationEngine.EligiblePositionCount)
			Harness.expect(
				math.abs(observed - expected) < configured.tolerance,
				`expected mutation rate {expected}, observed {observed}`
			)
		end
	end)

	Harness.test(
		"all six classes remain valid with legal four-ability eight-card phenotypes",
		function()
			for index, className in CLASSES do
				local result = mutate(className, 900 + index, policy(1, 1))
				Harness.expect(result.ok)
				Harness.expect(
					GenomeValidator.validate(
						result.value.appearanceGenome,
						result.value.abilityGenome,
						className
					).ok
				)
				local expression = GenotypeExpressor.express(
					result.value.appearanceGenome,
					result.value.abilityGenome,
					className
				)
				Harness.expect(expression.ok)
				local definitionIds = expression.value.phenotype.abilities.cardDefinitionIds
				Harness.equal(#definitionIds, #ACTIVE_ABILITY_LOCI)
				local deck = DeckBuilder.build(1, {
					{
						sourceCritterInstanceId = `mutation:{className}`,
						definitionIds = definitionIds,
					},
				}, {
					AbilitiesPerCritter = 4,
					CopiesPerCard = 2,
					TeamDeckSize = 8,
				})
				Harness.expect(deck.ok)
				Harness.equal(#deck.value.cardInstances, 8)
			end
		end
	)

	Harness.test("policy and input validation fail closed", function()
		local genomes = GeneRegistry.defaultGenomes("Stone")
		local invalidPolicy = policy(2, 1)
		Harness.expect(
			Harness.hasError(
				MutationEngine.mutate(
					genomes.appearanceGenome,
					genomes.abilityGenome,
					"Stone",
					1,
					invalidPolicy
				),
				"INVALID_MUTATION_PROBABILITY"
			)
		)
		local invalidGenome = Harness.clone(genomes.appearanceGenome)
		invalidGenome.slots.body.R1 = "gene.missing"
		Harness.expect(
			Harness.hasError(
				MutationEngine.mutate(
					invalidGenome,
					genomes.abilityGenome,
					"Stone",
					1,
					policy(1, 10)
				),
				"UNKNOWN_GENE"
			)
		)
	end)

	Harness.test("only active recessive loci are eligible in stable order", function()
		local result = mutate("Stone", 1001, policy(0, 1))
		Harness.expect(result.ok)
		local expectedIndex = 1
		for _, locus in GeneRegistry.AppearanceSlots do
			for _, position in RECESSIVE_POSITIONS do
				local entry = result.value.trace.entries[expectedIndex]
				Harness.equal(entry.layer, "APPEARANCE")
				Harness.equal(entry.locus, locus)
				Harness.equal(entry.position, position)
				expectedIndex += 1
			end
		end
		for _, locus in ACTIVE_ABILITY_LOCI do
			for _, position in RECESSIVE_POSITIONS do
				local entry = result.value.trace.entries[expectedIndex]
				Harness.equal(entry.layer, "ABILITY")
				Harness.equal(entry.locus, locus)
				Harness.equal(entry.position, position)
				expectedIndex += 1
			end
		end
		Harness.equal(expectedIndex - 1, 22)
	end)
end
