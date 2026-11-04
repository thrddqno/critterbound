--!strict

return function(Harness)
	local GeneRegistry = require("../../src/shared/Genetics/GeneRegistry")
	local GenomeValidator = require("../../src/shared/Genetics/GenomeValidator")
	local AppearanceResolver = require("../../src/shared/Genetics/AppearanceResolver")
	local AbilityResolver = require("../../src/shared/Genetics/AbilityResolver")
	local InheritanceEngine = require("../../src/server/Genetics/InheritanceEngine")
	local CardCatalog = require("../../src/shared/Definitions/CardCatalog")
	local CritterCatalog = require("../../src/shared/Definitions/CritterCatalog")
	local TrainingGrounds = require("../../src/shared/Definitions/TrainingGrounds")
	local BattleFactory = require("../../src/shared/Battle/BattleFactory")
	local DeterministicRng = require("../../src/shared/Battle/DeterministicRng")
	local Deck = require("../../src/shared/Battle/Deck")
	local DomainValidator = require("../../src/shared/Validation/DomainValidator")

	local CLASSES = { "Stone", "Feral", "Verdant", "Tide", "Gale", "Shade" }
	local RIGS = {
		Stone = "heavy",
		Feral = "agile",
		Verdant = "round",
		Tide = "round",
		Gale = "agile",
		Shade = "agile",
	}
	local ALTERNATIVES = {
		Stone = { mouth = "stone.rampart", back = "stone.crush" },
		Feral = { mouth = "feral.maul", tail = "feral.fury" },
		Verdant = { horn = "verdant.bloom", tail = "verdant.bramble" },
		Tide = { mouth = "tide.torrent", horn = "tide.purge" },
		Gale = { mouth = "gale.squall", back = "gale.tailwind" },
		Shade = { horn = "shade.curse", back = "shade.terror" },
	}

	local function founderParent(className: string)
		local genomes = GeneRegistry.founderGenomes(className)
		Harness.expect(genomes ~= nil)
		return {
			class = className,
			appearanceGenome = genomes.appearanceGenome,
			abilityGenome = genomes.abilityGenome,
		}
	end

	local function appearanceKey(resolved)
		local parts = {}
		for _, slot in GeneRegistry.AppearanceSlots do
			table.insert(parts, resolved.resolvedGenesBySlot[slot] or "?")
		end
		return table.concat(parts, "|")
	end

	local function countKeys(values)
		local count = 0
		for _ in values do
			count += 1
		end
		return count
	end

	Harness.test("curated variants expose 36 validated cards and class ability pools", function()
		local cards = CardCatalog.allById()
		local validAbilityIds = {}
		for _, className in CLASSES do
			local definition = CritterCatalog.getByClass(className)
			Harness.expect(definition ~= nil)
			local pool = {}
			for _, abilityId in definition.abilityPool do
				pool[abilityId] = true
				validAbilityIds[abilityId] = true
			end
			for _, abilityId in definition.abilityIds do
				Harness.expect(pool[abilityId], `{className} pool omits base {abilityId}`)
			end
			for slot, abilityId in ALTERNATIVES[className] do
				Harness.expect(pool[abilityId], `{className} pool omits alternative {abilityId}`)
				Harness.expect(
					GeneRegistry.get(`gene.ability.{slot}.{abilityId}`) ~= nil,
					`Missing alternative gene {abilityId}`
				)
			end
		end
		Harness.expect(validAbilityIds["verdant.bloom"])
		Harness.expect(validAbilityIds["gale.tailwind"])

		local cardCount = 0
		for _, card in cards do
			cardCount += 1
			Harness.expect(
				DomainValidator.validateCardDefinition(card, validAbilityIds).ok,
				`Invalid curated card {card.id}`
			)
		end
		Harness.equal(cardCount, 36)
	end)

	Harness.test("cross-class genes require explicit compatibility metadata", function()
		local bloom = GeneRegistry.get("gene.ability.horn.verdant.bloom")
		Harness.expect(bloom ~= nil)
		Harness.expect(table.find(bloom.compatibleClasses, "Stone") ~= nil)
		Harness.expect(table.find(bloom.compatibleClasses, "Tide") ~= nil)
		Harness.expect(AbilityResolver.cardClassFor("verdant.bloom", "Stone") == "Verdant")
		Harness.expect(AbilityResolver.cardClassFor("verdant.bloom", "Tide") == "Verdant")
		Harness.expect(AbilityResolver.cardClassFor("verdant.bloom", "Feral") == nil)

		local tailwind = GeneRegistry.get("gene.ability.back.gale.tailwind")
		Harness.expect(tailwind ~= nil)
		Harness.expect(table.find(tailwind.compatibleClasses, "Feral") ~= nil)
		Harness.expect(AbilityResolver.cardClassFor("gale.tailwind", "Feral") == "Gale")
		Harness.expect(AbilityResolver.cardClassFor("gale.tailwind", "Shade") == nil)

		local body = GeneRegistry.get("gene.appearance.body.stone.armored")
		Harness.expect(body ~= nil)
		Harness.expect(not GeneRegistry.classExpressible(body, "Tide"))
	end)

	Harness.test("cross-class abilities resolve only for compatible classes", function()
		local function resolveAbility(className: string, slot: string, geneId: string)
			local genomes = GeneRegistry.defaultGenomes(className)
			genomes.abilityGenome.slots[slot] = { D = geneId, R1 = geneId, R2 = geneId }
			return AbilityResolver.resolve(genomes.abilityGenome, className)
		end

		local stoneBloom = resolveAbility("Stone", "horn", "gene.ability.horn.verdant.bloom")
		Harness.expect(stoneBloom.ok)
		Harness.equal(stoneBloom.value.abilityIds[2], "verdant.bloom")
		Harness.equal(stoneBloom.value.sourcesBySlot.horn, "D")

		local feralTailwind = resolveAbility("Feral", "back", "gene.ability.back.gale.tailwind")
		Harness.expect(feralTailwind.ok)
		Harness.equal(feralTailwind.value.abilityIds[3], "gale.tailwind")
		Harness.equal(feralTailwind.value.sourcesBySlot.back, "D")

		local feralBloom = resolveAbility("Feral", "horn", "gene.ability.horn.verdant.bloom")
		Harness.expect(feralBloom.ok)
		Harness.equal(feralBloom.value.abilityIds[2], "feral.pounce")
		Harness.equal(feralBloom.value.sourcesBySlot.horn, "FALLBACK")
		Harness.expect(table.find(feralBloom.value.abilityIds, "verdant.bloom") == nil)
	end)

	Harness.test("battle factory accepts recorded cross-class ability genes", function()
		local input = TrainingGrounds.createInput(101, 1)
		local stone = input.teams[1].critterInstances[1]
		local founders = GeneRegistry.founderGenomes("Stone")
		stone.appearanceGenome = founders.appearanceGenome
		stone.abilityGenome = founders.abilityGenome
		local result = BattleFactory.create(input, {
			rng = DeterministicRng,
			criticalRngSeed = 9001,
			deck = Deck,
			validator = DomainValidator,
		})
		Harness.expect(result.ok)
		local bloomCards = 0
		for _, card in result.value.cardInstances do
			local definition = input.cardDefinitionsById[card.definitionId]
			if definition.abilityId == "verdant.bloom" then
				Harness.equal(card.sourceCritterInstanceId, stone.id)
				bloomCards += 1
			end
		end
		Harness.equal(bloomCards, 2)
		Harness.equal(#result.value.cardInstances, 48)
	end)

	Harness.test(
		"appearance compatibility enforces rigs while allowing curated cross-class layers",
		function()
			local tide = founderParent("Tide")
			local tideAppearance = AppearanceResolver.resolve(tide.appearanceGenome, "Tide")
			Harness.expect(tideAppearance.ok)
			Harness.equal(tideAppearance.value.bodyRigFamily, RIGS.Tide)
			Harness.equal(tideAppearance.value.sourcesBySlot.wings, "D")
			Harness.equal(
				tideAppearance.value.resolvedGenesBySlot.wings,
				"gene.appearance.wings.gale.feathered"
			)

			local stone = founderParent("Stone")
			local stoneAppearance = AppearanceResolver.resolve(stone.appearanceGenome, "Stone")
			Harness.expect(stoneAppearance.ok)
			Harness.equal(
				stoneAppearance.value.resolvedGenesBySlot.eyes,
				"gene.appearance.eyes.stone.foreign_species"
			)
			Harness.equal(
				GeneRegistry.get(stoneAppearance.value.resolvedGenesBySlot.eyes).displayName,
				"Stone Crystal Eyes"
			)

			local badBody = GeneRegistry.defaultGenomes("Stone")
			badBody.appearanceGenome.slots.body = {
				D = "gene.appearance.body.tide.streamlined",
				R1 = "gene.appearance.body.tide.streamlined",
				R2 = "gene.appearance.body.tide.streamlined",
			}
			local badBodyResult = AppearanceResolver.resolve(badBody.appearanceGenome, "Stone")
			Harness.expect(badBodyResult.ok)
			Harness.equal(badBodyResult.value.bodyRigFamily, "heavy")
			Harness.equal(badBodyResult.value.sourcesBySlot.body, "FALLBACK")

			local badTail = GeneRegistry.defaultGenomes("Stone")
			badTail.appearanceGenome.slots.tail = {
				D = "gene.appearance.tail.gale.feather",
				R1 = "gene.appearance.tail.gale.feather",
				R2 = "gene.appearance.tail.gale.feather",
			}
			local badTailResult = AppearanceResolver.resolve(badTail.appearanceGenome, "Stone")
			Harness.expect(badTailResult.ok)
			Harness.equal(badTailResult.value.sourcesBySlot.tail, "FALLBACK")
			Harness.equal(
				badTailResult.value.resolvedGenesBySlot.tail,
				"gene.appearance.tail.stone.default"
			)
		end
	)

	Harness.test("founder genomes are valid variants with canonical recessive carriers", function()
		for _, className in CLASSES do
			local definition = CritterCatalog.getByClass(className)
			local defaults = GeneRegistry.defaultGenomes(className)
			local founders = GeneRegistry.founderGenomes(className)
			Harness.expect(defaults ~= nil and founders ~= nil)
			Harness.expect(
				GenomeValidator.validate(
					founders.appearanceGenome,
					founders.abilityGenome,
					className
				).ok
			)

			local defaultAbilities = AbilityResolver.resolve(
				defaults.abilityGenome,
				className,
				`critter.{string.lower(className)}`
			)
			Harness.expect(defaultAbilities.ok)
			Harness.deepEqual(defaultAbilities.value.abilityIds, definition.abilityIds)

			local differs = false
			for _, slot in GeneRegistry.AppearanceSlots do
				local defaultTriplet = defaults.appearanceGenome.slots[slot]
				local founderTriplet = founders.appearanceGenome.slots[slot]
				if founderTriplet.D ~= defaultTriplet.D then
					differs = true
				end
				Harness.equal(founderTriplet.R1, defaultTriplet.D)
				Harness.equal(founderTriplet.R2, defaultTriplet.D)
			end
			Harness.expect(differs, `{className} founder has no curated appearance variant`)
		end
	end)

	Harness.test(
		"diversity simulation reports unique resolved appearances and legal ability sets",
		function()
			local founders = {}
			for _, className in CLASSES do
				founders[className] = founderParent(className)
			end

			local totalAppearanceSets = 0
			local totalAbilitySets = 0
			local totalFallbackLoci = 0
			local totalRepairs = 0
			local samples = 24
			for classIndex, className in CLASSES do
				local partnerClass = CLASSES[classIndex % #CLASSES + 1]
				local parentA = founders[className]
				local parentB = founders[partnerClass]
				local pool = {}
				for _, abilityId in CritterCatalog.getByClass(className).abilityPool do
					pool[abilityId] = true
				end
				local appearances = {}
				local abilities = {}
				local fallbackLoci = 0
				local repairs = 0
				for sample = 1, samples do
					local result = InheritanceEngine.inherit(
						parentA,
						parentB,
						className,
						9000 + classIndex * 100 + sample
					)
					Harness.expect(result.ok)
					Harness.equal(result.value.rng.drawCount, 72)

					local appearance =
						AppearanceResolver.resolve(result.value.appearanceGenome, className)
					Harness.expect(appearance.ok)
					Harness.equal(appearance.value.bodyRigFamily, RIGS[className])
					appearances[appearanceKey(appearance.value)] = true
					fallbackLoci += #appearance.value.fallbackSlots

					local ability = AbilityResolver.resolve(
						result.value.abilityGenome,
						className,
						appearance.value.speciesId
					)
					Harness.expect(ability.ok)
					Harness.equal(#ability.value.abilityIds, 4)
					local seen = {}
					for _, abilityId in ability.value.abilityIds do
						Harness.expect(not seen[abilityId], `Duplicate ability {abilityId}`)
						seen[abilityId] = true
						Harness.expect(pool[abilityId], `{abilityId} is outside {className} pool`)
						local card = CardCatalog.getByAbilityId(abilityId)
						Harness.expect(card ~= nil)
						Harness.equal(card.abilityId, abilityId)
						Harness.equal(
							AbilityResolver.cardClassFor(abilityId, className),
							card.class,
							`{abilityId} is not expressible by {className}`
						)
					end
					abilities[table.concat(ability.value.abilityIds, "|")] = true
					fallbackLoci += #ability.value.fallbackSlots
					repairs += #result.value.trace.fallbacks
				end

				local appearanceCount = countKeys(appearances)
				local abilityCount = countKeys(abilities)
				totalAppearanceSets += appearanceCount
				totalAbilitySets += abilityCount
				totalFallbackLoci += fallbackLoci
				totalRepairs += repairs
				print(
					`DIVERSITY {className} vs {partnerClass}: {appearanceCount}/{samples} unique appearances, {abilityCount}/{samples} unique ability sets, {fallbackLoci} resolved fallback loci, {repairs} repaired dominants`
				)
				Harness.expect(
					appearanceCount >= 2,
					`{className} produced only {appearanceCount} resolved appearance`
				)
			end
			print(
				`DIVERSITY TOTAL: {totalAppearanceSets} unique appearance sets, {totalAbilitySets} unique ability sets, {totalFallbackLoci} resolved fallback loci, {totalRepairs} repaired dominants`
			)
		end
	)
end
