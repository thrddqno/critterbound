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
	end)

	Harness.test("automatic targets require no client selection", function()
		for _, rule in { "SELF", "ENEMY", "FRONT_ENEMY", "ALL_ALLIES", "ALL_ENEMIES" } do
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

	Harness.test("automatic target rules have explicit non-interactive labels", function()
		Harness.equal(
			TargetSelection.ruleDescription({ targetingRule = "ENEMY" }),
			"Target: automatic enemy"
		)
		Harness.equal(
			TargetSelection.ruleDescription({ targetingRule = "FRONT_ENEMY" }),
			"Target: automatic front enemy"
		)
	end)
end
