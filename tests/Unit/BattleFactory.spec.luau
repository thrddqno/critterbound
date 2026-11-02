--!strict

return function(Harness)
	local Factory = require("../../src/shared/Battle/BattleFactory")
	local Rng = require("../../src/shared/Battle/DeterministicRng")
	local Deck = require("../../src/shared/Battle/Deck")
	local Validator = require("../../src/shared/Validation/DomainValidator")
	local Fixtures = require("../Fixtures/Run4Fixtures")

	local dependencies = { rng = Rng, deck = Deck, validator = Validator }

	Harness.test("valid 3v3 battle initializes deterministically", function()
		local input = Fixtures.createInput()
		local before = Harness.clone(input)
		local first = Factory.create(input, dependencies)
		local second = Factory.create(input, dependencies)
		Harness.expect(first.ok)
		Harness.deepEqual(first, second)
		Harness.deepEqual(input, before)
		Harness.equal(first.value.phase, "PLANNING")
		Harness.equal(first.value.roundNumber, 1)
		Harness.equal(first.value.stateVersion, 1)
		Harness.equal(#first.value.combatants, 6)
		Harness.equal(#first.value.cardInstances, 48)
	end)

	Harness.test("battle factory creates deck hand and energy per team", function()
		local result = Factory.create(Fixtures.createInput(), dependencies)
		Harness.expect(result.ok)
		for _, teamState in result.value.teamRoundStates do
			Harness.equal(teamState.energy, 3)
			Harness.equal(#teamState.handCardInstanceIds, 6)
			Harness.equal(#teamState.drawPileCardInstanceIds, 18)
			Harness.equal(#teamState.discardCardInstanceIds, 0)
			Harness.equal(#teamState.queuedCards, 0)
		end
	end)

	Harness.test("battle factory gives every Critter eight physical cards", function()
		local state = Factory.create(Fixtures.createInput(), dependencies).value
		local counts = {}
		for _, card in state.cardInstances do
			counts[card.sourceCritterInstanceId] = (counts[card.sourceCritterInstanceId] or 0) + 1
		end
		for _, count in counts do
			Harness.equal(count, 8)
		end
		Harness.equal(#state.cardInstances, 48)
	end)

	Harness.test("battle factory rejects invalid teams", function()
		local input = Fixtures.createInput()
		table.remove(input.teams[1].critterInstances)
		local result = Factory.create(input, dependencies)
		Harness.expect(not result.ok)
		Harness.expect(Harness.hasError(result, "INVALID_TEAM_SIZE"))
	end)

	Harness.test("battle factory rejects duplicate owners and missing card definitions", function()
		local duplicateOwner = Fixtures.createInput()
		duplicateOwner.teams[2].ownerUserId = duplicateOwner.teams[1].ownerUserId
		Harness.expect(
			Harness.hasError(Factory.create(duplicateOwner, dependencies), "DUPLICATE_TEAM_OWNER")
		)

		local missing = Fixtures.createInput()
		missing.cardDefinitionsById["card.stone.guard"] = nil
		Harness.expect(
			Harness.hasError(Factory.create(missing, dependencies), "MISSING_CARD_DEFINITION")
		)
	end)

	Harness.test("different seeds change order without changing deck membership", function()
		local firstInput = Fixtures.createInput()
		local secondInput = Fixtures.createInput()
		secondInput.rngSeed = 3002
		local first = Factory.create(firstInput, dependencies).value
		local second = Factory.create(secondInput, dependencies).value
		Harness.expect(
			first.teamRoundStates[1].handCardInstanceIds[1]
				~= second.teamRoundStates[1].handCardInstanceIds[1]
		)
		local firstIds = {}
		local secondIds = {}
		for _, card in first.cardInstances do
			firstIds[card.id] = true
		end
		for _, card in second.cardInstances do
			secondIds[card.id] = true
		end
		Harness.deepEqual(firstIds, secondIds)
	end)
end
