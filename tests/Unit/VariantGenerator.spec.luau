--!strict

return function(Harness)
	local VariantGenerator = require("../../src/server/Genetics/VariantGenerator")
	local AcquisitionPools = require("../../src/shared/Definitions/AcquisitionPools")
	local GeneRegistry = require("../../src/shared/Genetics/GeneRegistry")
	local GenomeValidator = require("../../src/shared/Genetics/GenomeValidator")
	local AppearanceResolver = require("../../src/shared/Genetics/AppearanceResolver")
	local AbilityResolver = require("../../src/shared/Genetics/AbilityResolver")

	local CLASSES = { "Stone", "Feral", "Verdant", "Tide", "Gale", "Shade" }
	local ABILITY_SLOTS = { "mouth", "horn", "back", "tail" }
	local CROSS_CLASSES = { "Stone", "Tide", "Feral" }
	local generator = VariantGenerator.new()

	local function requireSuccess(result, label: string)
		Harness.expect(result.ok, `{label}: {if result.ok then "" else result.errors[1].code}`)
		return result.value
	end

	local function signature(value)
		local parts = { value.class }
		for _, slot in GeneRegistry.AppearanceSlots do
			table.insert(parts, value.appearanceGenome.slots[slot].D)
			table.insert(parts, value.appearanceGenome.slots[slot].R1)
			table.insert(parts, value.appearanceGenome.slots[slot].R2)
		end
		for _, slot in GeneRegistry.AbilitySlots do
			table.insert(parts, value.abilityGenome.slots[slot].D)
			table.insert(parts, value.abilityGenome.slots[slot].R1)
			table.insert(parts, value.abilityGenome.slots[slot].R2)
		end
		return table.concat(parts, "|")
	end

	local function validateGenomes(value)
		local validation =
			GenomeValidator.validate(value.appearanceGenome, value.abilityGenome, value.class)
		Harness.expect(validation.ok, `genome validation failed for {value.class}`)
		for _, slot in GeneRegistry.AppearanceSlots do
			local triplet = value.appearanceGenome.slots[slot]
			for _, position in GeneRegistry.Positions do
				Harness.expect(
					GeneRegistry.get(triplet[position]) ~= nil,
					`unregistered appearance gene {tostring(triplet[position])}`
				)
			end
		end
		for _, slot in GeneRegistry.AbilitySlots do
			local triplet = value.abilityGenome.slots[slot]
			for _, position in GeneRegistry.Positions do
				Harness.expect(
					GeneRegistry.get(triplet[position]) ~= nil,
					`unregistered ability gene {tostring(triplet[position])}`
				)
			end
		end
		local appearance = AppearanceResolver.resolve(value.appearanceGenome, value.class)
		Harness.expect(appearance.ok, `appearance did not resolve for {value.class}`)
		local abilities = AbilityResolver.resolve(
			value.abilityGenome,
			value.class,
			appearance.ok and appearance.value.speciesId or nil
		)
		Harness.expect(abilities.ok, `abilities did not resolve for {value.class}`)
		local seen = {}
		for _, abilityId in abilities.value.abilityIds do
			Harness.expect(seen[abilityId] == nil, `duplicate ability {abilityId}`)
			seen[abilityId] = true
			Harness.expect(
				AbilityResolver.cardClassFor(abilityId, value.class) ~= nil,
				`ability {abilityId} has no legal card class`
			)
		end
		Harness.equal(#abilities.value.abilityIds, 4)
	end

	Harness.test("acquisition pools expose validated authoring data", function()
		local seenPools = {}
		for poolId in AcquisitionPools.all() do
			seenPools[poolId] = true
			local validation = AcquisitionPools.validate(poolId)
			Harness.expect(validation.ok, `pool {poolId} is invalid`)
			local pool = validation.value
			Harness.expect(#pool.eligibleClasses >= 1)
			Harness.expect(pool.version >= 1)
			Harness.expect(type(pool.source) == "string")
			for _, className in pool.eligibleClasses do
				Harness.expect(pool.classWeights[className] >= 1)
			end
			local preview = requireSuccess(generator.PreviewPool(poolId), `preview {poolId}`)
			Harness.equal(preview.id, poolId)
			Harness.equal(preview.version, pool.version)
			Harness.deepEqual(preview.eligibleClasses, pool.eligibleClasses)
		end
		Harness.expect(seenPools.COMMON_FOUNDERS)
		Harness.expect(seenPools.CLASS_SPECIFIC_FOUNDERS)
		Harness.expect(seenPools.CROSS_CLASS_CARRIERS)
		Harness.expect(AcquisitionPools.validate("UNKNOWN_POOL").ok == false)
	end)

	Harness.test("pool class constraints are enforced", function()
		local required = generator.Generate({ poolId = "CLASS_SPECIFIC_FOUNDERS", seed = 1 })
		Harness.expect(Harness.hasError(required, "CLASS_REQUIRED"))

		local outside = generator.Generate({
			poolId = "CROSS_CLASS_CARRIERS",
			seed = 1,
			class = "Verdant",
		})
		Harness.expect(Harness.hasError(outside, "CLASS_NOT_IN_POOL"))

		local badSeed = generator.Generate({ poolId = "COMMON_FOUNDERS", seed = 0 })
		Harness.expect(Harness.hasError(badSeed, "INVALID_RNG_SEED"))
	end)

	Harness.test("generation is deterministic and seed-sensitive", function()
		local first = requireSuccess(
			generator.Generate({ poolId = "COMMON_FOUNDERS", seed = 4242, class = "Stone" }),
			"first"
		)
		local second = requireSuccess(
			generator.Generate({ poolId = "COMMON_FOUNDERS", seed = 4242, class = "Stone" }),
			"second"
		)
		Harness.deepEqual(first, second)
		Harness.equal(first.seed, 4242)
		Harness.equal(first.generatorVersion, VariantGenerator.GeneratorVersion)

		local different = requireSuccess(
			generator.Generate({ poolId = "COMMON_FOUNDERS", seed = 4243, class = "Stone" }),
			"different"
		)
		Harness.expect(signature(first) ~= signature(different))
	end)

	Harness.test("generated genomes are legal and preserve D R1 R2", function()
		for _, poolId in { "COMMON_FOUNDERS", "CLASS_SPECIFIC_FOUNDERS" } do
			for _, className in CLASSES do
				for seed = 1, 25 do
					local value = requireSuccess(
						generator.Generate({ poolId = poolId, seed = seed, class = className }),
						`{poolId} {className} {seed}`
					)
					Harness.equal(value.class, className)
					validateGenomes(value)
					for _, slot in GeneRegistry.AppearanceSlots do
						local triplet = value.appearanceGenome.slots[slot]
						Harness.expect(triplet.D ~= nil and triplet.R1 ~= nil and triplet.R2 ~= nil)
					end
					for _, slot in GeneRegistry.AbilitySlots do
						local triplet = value.abilityGenome.slots[slot]
						Harness.expect(triplet.D ~= nil and triplet.R1 ~= nil and triplet.R2 ~= nil)
					end
				end
			end
		end
		for _, className in CROSS_CLASSES do
			for seed = 1, 40 do
				local value = requireSuccess(
					generator.Generate({
						poolId = "CROSS_CLASS_CARRIERS",
						seed = seed,
						class = className,
					}),
					`cross {className} {seed}`
				)
				Harness.equal(value.class, className)
				validateGenomes(value)
			end
		end
	end)

	Harness.test(
		"every generated Critter shows visible variation and recessive carriers",
		function()
			local forced = 0
			local withCarriers = 0
			local carrierSlots = 0
			for seed = 1, 120 do
				local value = requireSuccess(
					generator.Generate({ poolId = "COMMON_FOUNDERS", seed = seed, class = "Stone" }),
					`visible {seed}`
				)
				local defaults = GeneRegistry.defaultGenomes(value.class)
				local visible = 0
				for _, slot in GeneRegistry.AppearanceSlots do
					if
						value.appearanceGenome.slots[slot].D
						~= defaults.appearanceGenome.slots[slot].D
					then
						visible += 1
					end
				end
				Harness.expect(visible >= 1, `seed {seed} shows no visible change`)
				if value.trace.forcedVariant ~= nil then
					forced += 1
				end
				local carriers = 0
				for _, genome in { value.appearanceGenome, value.abilityGenome } do
					local slots = if genome == value.appearanceGenome
						then GeneRegistry.AppearanceSlots
						else GeneRegistry.AbilitySlots
					for _, slot in slots do
						local triplet = genome.slots[slot]
						if triplet.R1 ~= triplet.D then
							carriers += 1
						end
						if triplet.R2 ~= triplet.D then
							carriers += 1
						end
					end
				end
				if carriers > 0 then
					withCarriers += 1
					carrierSlots += carriers
				end
			end
			Harness.expect(withCarriers > 0, "no recessive carriers were generated")
			Harness.expect(carrierSlots > withCarriers, "carriers should be varied")
			Harness.expect(forced < 120, "variant forcing should not be the only path")
		end
	)

	Harness.test("pools respect variant carrier and cross-class caps", function()
		for _, poolId in { "COMMON_FOUNDERS", "CLASS_SPECIFIC_FOUNDERS" } do
			local pool = AcquisitionPools.validate(poolId).value
			for _, className in CLASSES do
				for seed = 1, 40 do
					local value = requireSuccess(
						generator.Generate({ poolId = poolId, seed = seed, class = className }),
						`caps {poolId} {className}`
					)
					Harness.expect(
						value.trace.counts.appearanceVariants <= pool.limits.maxAppearanceVariants
					)
					Harness.expect(
						value.trace.counts.abilityVariants <= pool.limits.maxAbilityVariants
					)
					Harness.expect(value.trace.counts.crossTotal <= pool.limits.maxCrossClassGenes)
					Harness.expect(
						value.trace.counts.crossDominant <= pool.limits.maxCrossClassDominant
					)
				end
			end
		end

		local pool = AcquisitionPools.validate("CROSS_CLASS_CARRIERS").value
		local allowed = {}
		for _, geneId in pool.crossClassGeneIds do
			allowed[geneId] = true
		end
		Harness.expect(#pool.crossClassGeneIds > 0)
		local dominantSeeds = 0
		local carrierSeeds = 0
		for _, className in CROSS_CLASSES do
			for seed = 1, 80 do
				local value = requireSuccess(
					generator.Generate({
						poolId = "CROSS_CLASS_CARRIERS",
						seed = seed,
						class = className,
					}),
					`cross caps {className} {seed}`
				)
				Harness.expect(
					value.trace.counts.appearanceVariants <= pool.limits.maxAppearanceVariants
				)
				Harness.expect(value.trace.counts.abilityVariants <= pool.limits.maxAbilityVariants)
				Harness.expect(value.trace.counts.crossTotal <= pool.limits.maxCrossClassGenes)
				Harness.expect(
					value.trace.counts.crossDominant <= pool.limits.maxCrossClassDominant
				)
				if value.trace.counts.crossDominant > 0 then
					dominantSeeds += 1
				end
				if value.trace.counts.crossTotal > value.trace.counts.crossDominant then
					carrierSeeds += 1
				end
				for _, step in value.trace.steps do
					if step.crossClass then
						Harness.expect(
							allowed[step.geneId] == true,
							`cross-class gene {step.geneId} is outside the pool allowlist`
						)
					end
				end
			end
		end
		Harness.expect(dominantSeeds > 0, "cross-class dominance was never generated")
		Harness.expect(carrierSeeds > 0, "cross-class carriers were never generated")
	end)

	Harness.test("common founders cover every class with diverse outputs", function()
		local classCounts = {}
		local signatures = {}
		for seed = 1, 600 do
			local value = requireSuccess(
				generator.Generate({ poolId = "COMMON_FOUNDERS", seed = seed }),
				`diversity {seed}`
			)
			classCounts[value.class] = (classCounts[value.class] or 0) + 1
			signatures[signature(value)] = true
		end
		for _, className in CLASSES do
			Harness.expect(
				(classCounts[className] or 0) > 0,
				`class {className} was never generated`
			)
		end
		local unique = 0
		for _ in signatures do
			unique += 1
		end
		Harness.expect(unique > 100, `only {unique} unique genomes in 600 seeds`)
	end)

	Harness.test("weighted class selection reaches every eligible class", function()
		for _, case in
			{
				{ poolId = "COMMON_FOUNDERS", classes = CLASSES },
				{ poolId = "CROSS_CLASS_CARRIERS", classes = CROSS_CLASSES },
			}
		do
			local classCounts = {}
			for seed = 1, 240 do
				local value = requireSuccess(
					generator.Generate({ poolId = case.poolId, seed = seed }),
					`class diversity {case.poolId} {seed}`
				)
				classCounts[value.class] = (classCounts[value.class] or 0) + 1
			end
			for _, className in case.classes do
				Harness.expect(
					(classCounts[className] or 0) > 0,
					`{case.poolId} never generated {className}`
				)
			end
		end
	end)

	Harness.test("weighted selection favours defaults without removing alternatives", function()
		local defaults = 0
		local alternatives = 0
		local abilityVariants = 0
		for seed = 1, 300 do
			local value = requireSuccess(
				generator.Generate({
					poolId = "COMMON_FOUNDERS",
					seed = seed,
					class = "Stone",
				}),
				`weights {seed}`
			)
			local genomes = GeneRegistry.defaultGenomes("Stone")
			if value.appearanceGenome.slots.tail.D == genomes.appearanceGenome.slots.tail.D then
				defaults += 1
			else
				alternatives += 1
			end
			local variants = 0
			for _, slot in ABILITY_SLOTS do
				if value.abilityGenome.slots[slot].D ~= genomes.abilityGenome.slots[slot].D then
					variants += 1
				end
			end
			abilityVariants += variants
		end
		Harness.expect(defaults > alternatives, "default appearance gene should dominate")
		Harness.expect(alternatives > 0, "appearance alternatives should still appear")
		Harness.expect(abilityVariants > 0, "ability alternatives should still appear")
	end)

	Harness.test("generation failure is bounded rather than looping forever", function()
		local start = os.clock()
		for _, poolId in { "COMMON_FOUNDERS", "CLASS_SPECIFIC_FOUNDERS", "CROSS_CLASS_CARRIERS" } do
			local class = if poolId == "CLASS_SPECIFIC_FOUNDERS"
				then "Stone"
				elseif poolId == "CROSS_CLASS_CARRIERS" then "Tide"
				else nil
			for seed = 1, 200 do
				local result = generator.Generate({ poolId = poolId, seed = seed, class = class })
				Harness.expect(result.ok, `{poolId} seed {seed} failed generation`)
			end
		end
		Harness.expect(os.clock() - start < 30, "generation took unexpectedly long")
	end)
end
