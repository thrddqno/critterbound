--!strict

return function(Harness)
	local TargetSelection = require("../../src/client/Presentation/TargetSelection")

	local model = {
		critters = {
			{ id = "ally.source", teamId = "ally", defeated = false },
			{ id = "ally.other", teamId = "ally", defeated = false },
			{ id = "enemy.front", teamId = "enemy", defeated = false },
			{ id = "enemy.dead", teamId = "enemy", defeated = true },
		},
	}

	Harness.test("target selection exposes only legal living targets", function()
		Harness.deepEqual(
			TargetSelection.legalTargetIds({
				sourceCombatantId = "ally.source",
				targetingRule = "ALLY",
			}, model),
			{ "ally.other" }
		)
		Harness.deepEqual(
			TargetSelection.legalTargetIds({
				sourceCombatantId = "ally.source",
				targetingRule = "ENEMY",
			}, model),
			{ "enemy.front" }
		)
		Harness.deepEqual(
			TargetSelection.legalTargetIds({
				sourceCombatantId = "ally.source",
				targetingRule = "SELF",
			}, model),
			{ "ally.source" }
		)
	end)

	Harness.test("derived targets require no client selection", function()
		for _, rule in { "FRONT_ENEMY", "ALL_ALLIES", "ALL_ENEMIES" } do
			Harness.expect(not TargetSelection.needsSelection({ targetingRule = rule }))
			Harness.deepEqual(
				TargetSelection.legalTargetIds({
					sourceCombatantId = "ally.source",
					targetingRule = rule,
				}, model),
				{}
			)
		end
	end)
end
