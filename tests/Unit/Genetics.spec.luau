--!strict

return function(Harness)
	local GeneRegistry = require("../../src/shared/Genetics/GeneRegistry")
	local GenomeValidator = require("../../src/shared/Genetics/GenomeValidator")
	local AppearanceResolver = require("../../src/shared/Genetics/AppearanceResolver")
	local AbilityResolver = require("../../src/shared/Genetics/AbilityResolver")
	local CardCatalog = require("../../src/shared/Definitions/CardCatalog")

	Harness.test("default genomes contain every required locus and allele", function()
		for _, className in { "Stone", "Feral", "Verdant", "Tide", "Gale", "Shade" } do
			local genomes = GeneRegistry.defaultGenomes(className)
			Harness.expect(genomes ~= nil)
			Harness.expect(
				GenomeValidator.validate(genomes.appearanceGenome, genomes.abilityGenome, className).ok
			)
			for _, slot in GeneRegistry.AppearanceSlots do
				for _, position in GeneRegistry.Positions do
					Harness.expect(
						GeneRegistry.get(genomes.appearanceGenome.slots[slot][position]) ~= nil
					)
				end
			end
			for _, slot in GeneRegistry.AbilitySlots do
				for _, position in GeneRegistry.Positions do
					Harness.expect(
						GeneRegistry.get(genomes.abilityGenome.slots[slot][position]) ~= nil
					)
				end
			end
		end
	end)

	Harness.test("genome validator rejects unknown wrong-slot and incomplete alleles", function()
		local genomes = GeneRegistry.defaultGenomes("Stone")
		local unknown = Harness.clone(genomes.appearanceGenome)
		unknown.slots.eyes.D = "gene.missing"
		Harness.expect(
			Harness.hasError(GenomeValidator.validateAppearance(unknown, "Stone"), "UNKNOWN_GENE")
		)
		local wrongSlot = Harness.clone(genomes.appearanceGenome)
		wrongSlot.slots.color.D = wrongSlot.slots.eyes.D
		Harness.expect(
			Harness.hasError(
				GenomeValidator.validateAppearance(wrongSlot, "Stone"),
				"INCOMPATIBLE_GENE_SLOT"
			)
		)
		local incomplete = Harness.clone(genomes.abilityGenome)
		incomplete.slots.mouth.R2 = nil
		Harness.expect(
			Harness.hasError(
				GenomeValidator.validateAbility(incomplete, "Stone"),
				"INVALID_ALLELE_TRIPLET"
			)
		)
	end)

	Harness.test(
		"appearance resolver enforces class and body rig with deterministic fallback",
		function()
			local genomes = GeneRegistry.defaultGenomes("Stone")
			genomes.appearanceGenome.slots.wings = {
				D = "gene.appearance.wings.gale.feathered",
				R1 = "gene.appearance.wings.gale.feathered",
				R2 = "gene.appearance.wings.gale.feathered",
			}
			genomes.appearanceGenome.slots.eyes = {
				D = "gene.appearance.eyes.stone.foreign_species",
				R1 = "gene.appearance.eyes.stone.foreign_species",
				R2 = "gene.appearance.eyes.stone.foreign_species",
			}
			local result = AppearanceResolver.resolve(genomes.appearanceGenome, "Stone")
			Harness.expect(result.ok)
			Harness.equal(result.value.bodyRigFamily, "heavy")
			Harness.equal(
				result.value.resolvedGenesBySlot.wings,
				"gene.appearance.wings.stone.default"
			)
			Harness.equal(result.value.sourcesBySlot.wings, "FALLBACK")
			Harness.equal(
				result.value.resolvedGenesBySlot.eyes,
				"gene.appearance.eyes.stone.foreign_species"
			)
			Harness.equal(result.value.sourcesBySlot.eyes, "D")
			for index = 2, #result.value.layers do
				Harness.expect(
					result.value.layers[index - 1].order <= result.value.layers[index].order
				)
			end
			Harness.expect(result.value.layers[6].attachmentKey ~= nil)
		end
	)

	Harness.test("ability resolver maps four unique existing class cards", function()
		local genomes = GeneRegistry.defaultGenomes("Feral")
		local result = AbilityResolver.resolve(genomes.abilityGenome, "Feral")
		Harness.expect(result.ok)
		Harness.equal(#result.value.abilityIds, 4)
		Harness.equal(#result.value.cardDefinitionIds, 4)
		local seen = {}
		for index, abilityId in result.value.abilityIds do
			Harness.expect(not seen[abilityId])
			seen[abilityId] = true
			local card = CardCatalog.getById(result.value.cardDefinitionIds[index])
			Harness.expect(card ~= nil and card.abilityId == abilityId and card.class == "Feral")
		end
		Harness.expect(result.value.resolvedGenesBySlot.traits ~= nil)
	end)

	Harness.test("ability class mismatch uses canonical slot fallback", function()
		local stone = GeneRegistry.defaultGenomes("Stone")
		local feral = GeneRegistry.defaultGenomes("Feral")
		stone.abilityGenome.slots.mouth = Harness.clone(feral.abilityGenome.slots.mouth)
		local result = AbilityResolver.resolve(stone.abilityGenome, "Stone")
		Harness.expect(result.ok)
		Harness.equal(result.value.abilityIds[1], "stone.guard")
		Harness.equal(result.value.sourcesBySlot.mouth, "FALLBACK")
	end)

	Harness.test("central card catalog contains existing and curated cards", function()
		local count = 0
		for _, card in CardCatalog.allById() do
			count += 1
			Harness.expect(CardCatalog.getByAbilityId(card.abilityId) ~= nil)
		end
		Harness.equal(count, 36)
	end)
end
