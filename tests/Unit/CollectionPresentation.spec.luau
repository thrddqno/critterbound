--!strict

return function(Harness)
	local Presentation = require("../../src/client/Presentation/CollectionPresentation")

	Harness.test("collection presentation maps stats genes restrictions and equipment", function()
		local result = Presentation.map({
			revision = 4,
			selectedTeam = { "critter.one" },
			critters = {
				{
					id = "critter.one",
					definitionId = "definition.one",
					displayName = "Pebble",
					class = "Stone",
					baseStats = { health = 52, speed = 10, skill = 2, morale = 6 },
					resolvedAppearance = {
						resolvedGenesBySlot = { color = "gene.appearance.color.stone.default" },
					},
					resolvedAbilityIds = { "stone.guard", "stone.slam" },
					acquisition = { source = "STARTER" },
					breeding = {
						breedable = false,
						generation = 0,
						parentIds = {},
						successfulBreedCount = 0,
					},
					tradable = false,
					selectedTeamSlot = 1,
					equippedItem = { displayName = "Training Charm" },
				},
			},
		})
		Harness.equal(result.revision, 4)
		Harness.equal(result.critters[1].statsText, "Health 52  Speed 10  Skill 2  Morale 6")
		Harness.equal(result.critters[1].equipmentText, "Training Charm")
		Harness.equal(result.critters[1].breedingText, "Restricted")
		Harness.equal(result.critters[1].selectedTeamSlot, 1)
		Harness.expect(
			string.find(result.critters[1].appearanceText, "Color: Stone Color", 1, true) ~= nil
		)
		Harness.expect(
			string.find(result.critters[1].appearanceText, "gene.appearance", 1, true) == nil
		)
		Harness.expect(
			string.find(result.critters[1].restrictionsText, "Breeding: Restricted", 1, true) ~= nil
		)
	end)

	Harness.test("collection presentation uses curated gene display names", function()
		Harness.equal(
			Presentation.readableIdentifier("gene.appearance.eyes.stone.foreign_species"),
			"Stone Crystal Eyes"
		)
		Harness.equal(
			Presentation.readableIdentifier("gene.appearance.accessories.verdant.sprout"),
			"Verdant Sprout"
		)
		Harness.equal(
			Presentation.readableIdentifier("gene.appearance.color.stone.default"),
			"Stone Color"
		)
	end)
end
