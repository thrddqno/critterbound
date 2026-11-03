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
					baseStats = { maxHealth = 120, speed = 10, skill = 2, resolve = 6 },
					appearanceGenome = { schemaVersion = 1, palette = "granite" },
					abilityGenome = { abilityIds = { "stone.guard", "stone.slam" } },
					acquisition = { source = "STARTER" },
					breeding = { breedable = false, generation = 0 },
					tradable = false,
					selectedTeamSlot = 1,
					equippedItem = { displayName = "Training Charm" },
				},
			},
		})
		Harness.equal(result.revision, 4)
		Harness.equal(result.critters[1].statsText, "HP 120  Speed 10  Skill 2  Resolve 6")
		Harness.equal(result.critters[1].equipmentText, "Training Charm")
		Harness.equal(result.critters[1].breedingText, "Restricted")
		Harness.equal(result.critters[1].selectedTeamSlot, 1)
		Harness.expect(string.find(result.critters[1].appearanceText, "palette: granite") ~= nil)
	end)
end
