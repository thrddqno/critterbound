--!strict

return function(Harness)
	local GeneRegistry = require("../../src/shared/Genetics/GeneRegistry")
	local GenotypeExpressor = require("../../src/shared/Genetics/GenotypeExpressor")
	local CardCatalog = require("../../src/shared/Definitions/CardCatalog")
	local DeckBuilder = require("../../src/shared/Battle/DeckBuilder")
	local DeckRules = require("../../src/shared/Battle/DeckRules")

	local CLASSES = { "Stone", "Feral", "Verdant", "Tide", "Gale", "Shade" }
	local ACTIVE_ABILITY_SLOTS = { "mouth", "horn", "back", "tail" }

	local function express(className: string, genomes)
		return GenotypeExpressor.express(
			genomes.appearanceGenome,
			genomes.abilityGenome,
			className,
			GeneRegistry.ContentVersion
		)
	end

	Harness.test(
		"all six classes express complete logical appearance and four abilities",
		function()
			for _, className in CLASSES do
				local result = express(className, GeneRegistry.founderGenomes(className))
				Harness.expect(result.ok, className)
				local phenotype = result.value.phenotype
				local appearance = phenotype.appearance
				Harness.expect(type(appearance.spriteRigId) == "string")
				Harness.expect(type(appearance.bodyShape) == "string")
				Harness.expect(type(appearance.baseAssetId) == "string")
				Harness.expect(type(appearance.anchorKey) == "string")
				Harness.expect(type(appearance.pivotKey) == "string")
				Harness.equal(#appearance.layers, 6)
				for _, slot in GeneRegistry.AppearanceSlots do
					Harness.expect(
						appearance.resolvedGenesBySlot[slot] ~= nil,
						`{className}.{slot}`
					)
				end

				local abilities = phenotype.abilities
				Harness.equal(#abilities.abilityIds, 4)
				Harness.equal(#abilities.cardDefinitionIds, 4)
				local seen = {}
				for index, abilityId in abilities.abilityIds do
					Harness.expect(not seen[abilityId], abilityId)
					seen[abilityId] = true
					local card = CardCatalog.getById(abilities.cardDefinitionIds[index])
					Harness.expect(card ~= nil and card.abilityId == abilityId)
				end
			end
		end
	)

	Harness.test("trace covers seven appearance and four active ability loci", function()
		local result = express("Stone", GeneRegistry.defaultGenomes("Stone"))
		Harness.expect(result.ok)
		Harness.equal(result.value.trace.geneContentVersion, GeneRegistry.ContentVersion)
		Harness.equal(#result.value.trace.entries, 11)
		local loci = {}
		for _, entry in result.value.trace.entries do
			loci[`{entry.genome}:{entry.locus}`] = true
			Harness.equal(entry.compatibilityDecision, "DOMINANT_EXPRESSED")
			Harness.equal(entry.inheritedDominantGene, entry.expressedGene)
			Harness.equal(entry.geneContentVersion, GeneRegistry.ContentVersion)
			Harness.equal(entry.fallbackReason, nil)
		end
		for _, slot in GeneRegistry.AppearanceSlots do
			Harness.expect(loci[`APPEARANCE:{slot}`])
		end
		for _, slot in ACTIVE_ABILITY_SLOTS do
			Harness.expect(loci[`ABILITY:{slot}`])
		end
	end)

	Harness.test("incompatible dominants fall back without expressing hidden carriers", function()
		local genomes = GeneRegistry.defaultGenomes("Stone")
		genomes.appearanceGenome.slots.tail.D = "gene.appearance.tail.gale.feather"
		genomes.appearanceGenome.slots.tail.R1 = "gene.appearance.tail.stone.crystal"
		genomes.abilityGenome.slots.mouth.D = "gene.ability.mouth.feral.maul"
		genomes.abilityGenome.slots.mouth.R1 = "gene.ability.mouth.stone.rampart"
		local before = Harness.clone(genomes)

		local result = express("Stone", genomes)
		Harness.expect(result.ok)
		Harness.equal(
			result.value.phenotype.appearance.resolvedGenesBySlot.tail,
			"gene.appearance.tail.stone.default"
		)
		Harness.equal(result.value.phenotype.abilities.abilityIds[1], "stone.guard")
		Harness.deepEqual(genomes, before)

		local fallbacks = {}
		for _, entry in result.value.trace.entries do
			if entry.compatibilityDecision == "PHENOTYPE_FALLBACK" then
				fallbacks[`{entry.genome}:{entry.locus}`] = entry
			end
		end
		Harness.equal(fallbacks["APPEARANCE:tail"].fallbackReason, "SPECIES_INCOMPATIBLE")
		Harness.equal(fallbacks["ABILITY:mouth"].fallbackReason, "CLASS_INCOMPATIBLE")
		Harness.equal(genomes.appearanceGenome.slots.tail.R1, "gene.appearance.tail.stone.crystal")
		Harness.equal(genomes.abilityGenome.slots.mouth.R1, "gene.ability.mouth.stone.rampart")
	end)

	Harness.test("curated cross-class genes express from the dominant position", function()
		local genomes = GeneRegistry.defaultGenomes("Stone")
		genomes.abilityGenome.slots.horn.D = "gene.ability.horn.verdant.bloom"
		local result = express("Stone", genomes)
		Harness.expect(result.ok)
		Harness.equal(result.value.phenotype.abilities.abilityIds[2], "verdant.bloom")
		Harness.equal(
			result.value.phenotype.abilities.cardClassesByAbilityId["verdant.bloom"],
			"Verdant"
		)
		Harness.equal(result.value.trace.entries[9].compatibilityDecision, "DOMINANT_EXPRESSED")
	end)

	Harness.test(
		"expression is deterministic and rejects invalid class version and duplicate attempts",
		function()
			local genomes = GeneRegistry.founderGenomes("Tide")
			local first = express("Tide", genomes)
			local second = express("Tide", genomes)
			Harness.deepEqual(first, second)
			Harness.expect(
				Harness.hasError(
					GenotypeExpressor.express(
						genomes.appearanceGenome,
						genomes.abilityGenome,
						"Unknown",
						GeneRegistry.ContentVersion
					),
					"INVALID_CRITTER_CLASS"
				)
			)
			Harness.expect(
				Harness.hasError(
					GenotypeExpressor.express(
						genomes.appearanceGenome,
						genomes.abilityGenome,
						"Tide",
						GeneRegistry.ContentVersion + 1
					),
					"UNSUPPORTED_GENE_CONTENT_VERSION"
				)
			)
			local duplicateAttempt = Harness.clone(genomes)
			duplicateAttempt.abilityGenome.slots.tail =
				Harness.clone(duplicateAttempt.abilityGenome.slots.horn)
			Harness.expect(
				Harness.hasError(express("Tide", duplicateAttempt), "INCOMPATIBLE_GENE_SLOT")
			)
		end
	)

	Harness.test(
		"production-shaped Critter and egg genomes build eight and twenty-four cards",
		function()
			local genomes = GeneRegistry.defaultGenomes("Feral")
			local critter = {
				schemaVersion = 3,
				definitionId = "critter.training.feral",
				appearanceGenome = genomes.appearanceGenome,
				abilityGenome = genomes.abilityGenome,
			}
			local egg = {
				schemaVersion = 1,
				offspringClass = "Feral",
				offspringAppearanceGenome = Harness.clone(critter.appearanceGenome),
				offspringAbilityGenome = Harness.clone(critter.abilityGenome),
			}
			local critterExpression =
				GenotypeExpressor.express(critter.appearanceGenome, critter.abilityGenome, "Feral")
			local eggExpression = GenotypeExpressor.express(
				egg.offspringAppearanceGenome,
				egg.offspringAbilityGenome,
				egg.offspringClass
			)
			Harness.expect(critterExpression.ok and eggExpression.ok)
			Harness.deepEqual(critterExpression.value.phenotype, eggExpression.value.phenotype)

			local definitionIds = critterExpression.value.phenotype.abilities.cardDefinitionIds
			local one = DeckBuilder.build(1, {
				{ sourceCritterInstanceId = "critter:1", definitionIds = definitionIds },
			}, {
				AbilitiesPerCritter = 4,
				CopiesPerCard = 2,
				TeamDeckSize = 8,
			})
			Harness.expect(one.ok)
			Harness.equal(#one.value.cardInstances, 8)
			local team = DeckBuilder.build(1, {
				{ sourceCritterInstanceId = "critter:1", definitionIds = definitionIds },
				{ sourceCritterInstanceId = "critter:2", definitionIds = definitionIds },
				{ sourceCritterInstanceId = "critter:3", definitionIds = definitionIds },
			}, DeckRules.Default)
			Harness.expect(team.ok)
			Harness.equal(#team.value.cardInstances, 24)
		end
	)
end
