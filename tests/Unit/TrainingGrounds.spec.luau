--!strict

return function(Harness)
	local Factory = require("../../src/shared/Battle/BattleFactory")
	local Content = require("../../src/shared/Definitions/TrainingGrounds")
	local Fixtures = require("../Fixtures/Run5Fixtures")

	Harness.test("Training Grounds content creates valid deterministic 3v3 matches", function()
		local input = Content.createInput(101, 1)
		local deps = Fixtures.dependencies()
		local first = Factory.create(input, {
			rng = deps.rng,
			criticalRngSeed = 9001,
			deck = deps.deck,
			validator = deps.validator,
		})
		local second = Factory.create(Content.createInput(101, 1), {
			rng = deps.rng,
			criticalRngSeed = 9001,
			deck = deps.deck,
			validator = deps.validator,
		})
		Harness.expect(first.ok and second.ok)
		Harness.equal(#first.value.teams, 2)
		Harness.equal(#first.value.combatants, 6)
		Harness.equal(#first.value.cardInstances, 48)
		Harness.equal(#first.value.teamRoundStates[1].handCardInstanceIds, 6)
		Harness.deepEqual(first, second)
	end)

	Harness.test("new Training Grounds generations use fresh identities", function()
		local first = Content.createInput(101, 1)
		local second = Content.createInput(101, 2)
		Harness.expect(first.battleId ~= second.battleId)
		Harness.expect(
			first.teams[1].critterInstances[1].id ~= second.teams[1].critterInstances[1].id
		)
	end)
end
