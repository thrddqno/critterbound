--!strict

return function(Harness)
	local Factory = require("../../src/shared/Battle/BattleFactory")
	local Rng = require("../../src/shared/Battle/DeterministicRng")
	local Deck = require("../../src/shared/Battle/Deck")
	local Validator = require("../../src/shared/Validation/DomainValidator")
	local Fixtures = require("../Fixtures/Run4Fixtures")

	local dependencies = { rng = Rng, criticalRngSeed = 9001, deck = Deck, validator = Validator }

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
		for _, combatant in first.value.combatants do
			Harness.equal(combatant.currentHealth, combatant.stats.maxHealth)
			Harness.equal(combatant.stats.maxHealth, 150 + 4 * combatant.stats.health)
		end
	end)

	Harness.test("battle factory creates deck hand and energy per team", function()
		local result = Factory.create(Fixtures.createInput(), dependencies)
		Harness.expect(result.ok)
		for _, teamState in result.value.teamRoundStates do
			Harness.equal(teamState.energy, 3)
			Harness.equal(#teamState.handCardInstanceIds, 6)
			Harness.equal(#teamState.drawPileCardInstanceIds, 18)
			Harness.equal(#teamState.discardCardInstanceIds, 0)
			Harness.equal(#teamState.removedCardInstanceIds, 0)
			Harness.equal(#teamState.queuedCards, 0)
		end
	end)

	Harness.test("opening hand is shared and may be uneven across Critters", function()
		local state = Factory.create(Fixtures.createInput(), dependencies).value
		local cards = Fixtures.indexById(state.cardInstances)
		local foundUneven = false
		for _, teamState in state.teamRoundStates do
			local byCritter = {}
			for _, cardId in teamState.handCardInstanceIds do
				local sourceId = cards[cardId].sourceCritterInstanceId
				byCritter[sourceId] = (byCritter[sourceId] or 0) + 1
			end
			for _, count in byCritter do
				if count ~= 2 then
					foundUneven = true
				end
			end
		end
		Harness.expect(foundUneven, "Fixed seed should demonstrate no per-Critter guarantee")
	end)

	Harness.test("every team card instance occupies exactly one opening zone", function()
		local state = Factory.create(Fixtures.createInput(), dependencies).value
		local cards = Fixtures.indexById(state.cardInstances)
		for _, teamState in state.teamRoundStates do
			local seen = {}
			for _, zone in
				{
					teamState.drawPileCardInstanceIds,
					teamState.handCardInstanceIds,
					teamState.discardCardInstanceIds,
					teamState.removedCardInstanceIds,
				}
			do
				for _, cardId in zone do
					Harness.expect(not seen[cardId])
					Harness.expect(cards[cardId] ~= nil)
					seen[cardId] = true
				end
			end
			Harness.equal(
				24,
				(function()
					local count = 0
					for _ in seen do
						count += 1
					end
					return count
				end)()
			)
		end
	end)

	Harness.test("battle factory gives every Critter two copies per equipped ability", function()
		local state = Factory.create(Fixtures.createInput(), dependencies).value
		local counts = {}
		local definitionsBySource = {}
		for _, card in state.cardInstances do
			counts[card.sourceCritterInstanceId] = (counts[card.sourceCritterInstanceId] or 0) + 1
			local definitions = definitionsBySource[card.sourceCritterInstanceId] or {}
			definitions[card.definitionId] = (definitions[card.definitionId] or 0) + 1
			definitionsBySource[card.sourceCritterInstanceId] = definitions
		end
		for _, count in counts do
			Harness.equal(count, 8)
		end
		for _, definitions in definitionsBySource do
			for _, count in definitions do
				Harness.equal(count, 2)
			end
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

	Harness.test("critical RNG seed never changes opening deck order", function()
		local firstDependencies = table.clone(dependencies)
		local secondDependencies = table.clone(dependencies)
		firstDependencies.criticalRngSeed = 123
		secondDependencies.criticalRngSeed = 456
		local first = Factory.create(Fixtures.createInput(), firstDependencies).value
		local second = Factory.create(Fixtures.createInput(), secondDependencies).value
		for index, teamState in first.teamRoundStates do
			Harness.deepEqual(
				teamState.handCardInstanceIds,
				second.teamRoundStates[index].handCardInstanceIds
			)
			Harness.deepEqual(
				teamState.drawPileCardInstanceIds,
				second.teamRoundStates[index].drawPileCardInstanceIds
			)
		end
		Harness.expect(first.criticalRng.state ~= second.criticalRng.state)
		Harness.deepEqual(first.rng, second.rng)
	end)
end
