--!strict

return function(Harness)
	local Factory = require("../../src/shared/Battle/BattleFactory")
	local BattlePlan = require("../../src/shared/Battle/BattlePlan")
	local Rng = require("../../src/shared/Battle/DeterministicRng")
	local Deck = require("../../src/shared/Battle/Deck")
	local Validator = require("../../src/shared/Validation/DomainValidator")
	local Fixtures = require("../Fixtures/Run4Fixtures")

	local function setup()
		local input = Fixtures.createInput()
		local state = Factory.create(
			input,
			{ rng = Rng, criticalRngSeed = 9001, deck = Deck, validator = Validator }
		).value
		return state, input.cardDefinitionsById
	end

	local function teamState(state, teamId)
		for _, value in state.teamRoundStates do
			if value.teamId == teamId then
				return value
			end
		end
		error("Missing team state")
	end

	local function legalRequest(state, definitions, teamId, cardId)
		local cards = Fixtures.indexById(state.cardInstances)
		local card = cards[cardId]
		local source = nil
		for _, combatant in state.combatants do
			if
				combatant.teamId == teamId
				and combatant.critterInstanceId == card.sourceCritterInstanceId
			then
				source = combatant
			end
		end
		local definition = definitions[card.definitionId]
		local targetIds = {}
		if definition.targetingRule == "ALLY" then
			for _, combatant in state.combatants do
				if combatant.teamId == teamId and combatant.id ~= source.id then
					targetIds = { combatant.id }
					break
				end
			end
		elseif definition.targetingRule == "ANY" then
			targetIds = { source.id }
		end
		return {
			cardInstanceId = cardId,
			sourceCombatantId = source.id,
			targetCombatantIds = targetIds,
		}
	end

	local function cardsForCombatant(state, combatantId)
		local combatant = Fixtures.indexById(state.combatants)[combatantId]
		local result = {}
		for _, card in state.cardInstances do
			if card.sourceCritterInstanceId == combatant.critterInstanceId then
				table.insert(result, card.id)
			end
		end
		table.sort(result)
		return result
	end

	local function fiveCardsForCombatant(state, combatantId)
		local cardIds = cardsForCombatant(state, combatantId)
		Harness.equal(#cardIds, 8)
		return { cardIds[1], cardIds[2], cardIds[3], cardIds[4], cardIds[5] }
	end

	Harness.test("queue reserves energy without deducting pool", function()
		local state, definitions = setup()
		local before = Harness.clone(state)
		local current = teamState(state, "team.1")
		local request = legalRequest(state, definitions, "team.1", current.handCardInstanceIds[1])
		local result = BattlePlan.queueCard(state, "team.1", request, definitions)
		Harness.expect(result.ok)
		Harness.equal(teamState(result.value, "team.1").energy, 3)
		Harness.expect(teamState(result.value, "team.1").reservedEnergy > 0)
		Harness.equal(#teamState(result.value, "team.1").handCardInstanceIds, 6)
		Harness.equal(#teamState(result.value, "team.1").discardCardInstanceIds, 0)
		Harness.deepEqual(state, before)
	end)

	Harness.test("duplicate opponent unknown and insufficient cards reject atomically", function()
		local state, definitions = setup()
		local own = teamState(state, "team.1")
		local request = legalRequest(state, definitions, "team.1", own.handCardInstanceIds[1])
		local queued = BattlePlan.queueCard(state, "team.1", request, definitions)
		Harness.expect(
			Harness.hasError(
				BattlePlan.queueCard(queued.value, "team.1", request, definitions),
				"CARD_ALREADY_QUEUED"
			)
		)

		local enemyCard = teamState(state, "team.2").handCardInstanceIds[1]
		local enemyRequest = legalRequest(state, definitions, "team.2", enemyCard)
		Harness.expect(
			Harness.hasError(
				BattlePlan.queueCard(state, "team.1", enemyRequest, definitions),
				"CARD_NOT_IN_HAND"
			)
		)

		local unknown = Harness.clone(request)
		unknown.cardInstanceId = "missing.card"
		Harness.expect(
			Harness.hasError(
				BattlePlan.queueCard(state, "team.1", unknown, definitions),
				"CARD_NOT_IN_HAND"
			)
		)

		local noEnergy = Harness.clone(state)
		teamState(noEnergy, "team.1").energy = 0
		Harness.expect(
			Harness.hasError(
				BattlePlan.queueCard(noEnergy, "team.1", request, definitions),
				"INSUFFICIENT_ENERGY"
			)
		)
	end)

	Harness.test("ally cards reject enemy targets", function()
		local state, definitions = setup()
		local cards = Fixtures.indexById(state.cardInstances)
		local current = teamState(state, "team.1")
		local allyCardId = current.handCardInstanceIds[1]
		definitions = Harness.clone(definitions)
		definitions[cards[allyCardId].definitionId].targetingRule = "ALLY"
		local request = legalRequest(state, definitions, "team.1", allyCardId)
		local enemyId = nil
		for _, combatant in state.combatants do
			if combatant.teamId == "team.2" then
				enemyId = combatant.id
				break
			end
		end
		request.targetCombatantIds = { enemyId }
		local result = BattlePlan.queueCard(state, "team.1", request, definitions)
		Harness.expect(not result.ok)
		Harness.expect(Harness.hasError(result, "INVALID_TARGET"))
	end)

	Harness.test("remove releases reservation and clear restores plan", function()
		local state, definitions = setup()
		local current = teamState(state, "team.1")
		local cardId = current.handCardInstanceIds[1]
		local queued = BattlePlan.queueCard(
			state,
			"team.1",
			legalRequest(state, definitions, "team.1", cardId),
			definitions
		)
		local removed = BattlePlan.removeQueuedCard(queued.value, "team.1", cardId, definitions)
		Harness.expect(removed.ok)
		Harness.equal(teamState(removed.value, "team.1").reservedEnergy, 0)
		Harness.equal(#teamState(removed.value, "team.1").queuedCards, 0)
		Harness.expect(BattlePlan.clearPlan(queued.value, "team.1", definitions).ok)
	end)

	Harness.test("four cards per Critter is allowed and fifth is rejected", function()
		local state, definitions = setup()
		local current = teamState(state, "team.1")
		local sourceId = state.teams[1].id == "team.1" and state.teams[1].combatantIds[1]
			or state.teams[2].combatantIds[1]
		local cardIds = fiveCardsForCombatant(state, sourceId)
		current.handCardInstanceIds = { cardIds[1], cardIds[2], cardIds[3], cardIds[4], cardIds[5] }
		current.energy = 100
		local nextState = state
		for index = 1, 4 do
			local queued = BattlePlan.queueCard(
				nextState,
				"team.1",
				legalRequest(nextState, definitions, "team.1", cardIds[index]),
				definitions
			)
			Harness.expect(queued.ok)
			nextState = queued.value
		end
		local fifth = BattlePlan.queueCard(
			nextState,
			"team.1",
			legalRequest(nextState, definitions, "team.1", cardIds[5]),
			definitions
		)
		Harness.expect(Harness.hasError(fifth, "CRITTER_QUEUE_LIMIT_EXCEEDED"))

		local removed = BattlePlan.removeQueuedCard(nextState, "team.1", cardIds[2], definitions)
		Harness.expect(removed.ok)
		local replacement = BattlePlan.queueCard(
			removed.value,
			"team.1",
			legalRequest(removed.value, definitions, "team.1", cardIds[5]),
			definitions
		)
		Harness.expect(replacement.ok)
		Harness.equal(#teamState(replacement.value, "team.1").queuedCards, 4)
	end)

	Harness.test("distinct Critters have independent queue limits", function()
		local state, definitions = setup()
		local team = if state.teams[1].id == "team.1" then state.teams[1] else state.teams[2]
		local firstCards = cardsForCombatant(state, team.combatantIds[1])
		local secondCards = cardsForCombatant(state, team.combatantIds[2])
		local selected = {}
		for index = 1, 4 do
			table.insert(selected, firstCards[index])
			table.insert(selected, secondCards[index])
		end
		local current = teamState(state, "team.1")
		current.handCardInstanceIds = selected
		current.energy = 100
		local nextState = state
		for _, cardId in selected do
			local queued = BattlePlan.queueCard(
				nextState,
				"team.1",
				legalRequest(nextState, definitions, "team.1", cardId),
				definitions
			)
			Harness.expect(queued.ok)
			nextState = queued.value
		end
		Harness.equal(#teamState(nextState, "team.1").queuedCards, 8)
	end)

	Harness.test("oversized Critter queue fails validation and commit", function()
		local state, definitions = setup()
		local team = if state.teams[1].id == "team.1" then state.teams[1] else state.teams[2]
		local cardIds = fiveCardsForCombatant(state, team.combatantIds[1])
		local current = teamState(state, "team.1")
		current.handCardInstanceIds = { cardIds[1], cardIds[2], cardIds[3], cardIds[4], cardIds[5] }
		current.energy = 100
		current.queuedCards = {}
		for index = 1, 5 do
			local request = legalRequest(state, definitions, "team.1", cardIds[index])
			table.insert(current.queuedCards, {
				cardInstanceId = request.cardInstanceId,
				sourceCombatantId = request.sourceCombatantId,
				targetCombatantIds = request.targetCombatantIds,
				queueIndex = index,
			})
		end
		Harness.expect(
			Harness.hasError(
				BattlePlan.validatePlan(state, "team.1", definitions),
				"CRITTER_QUEUE_LIMIT_EXCEEDED"
			)
		)
		Harness.expect(
			Harness.hasError(
				BattlePlan.commitPlan(state, "team.1", definitions),
				"CRITTER_QUEUE_LIMIT_EXCEEDED"
			)
		)
	end)

	Harness.test("reorder preserves card identity per Critter", function()
		local state, definitions = setup()
		teamState(state, "team.1").energy = 10
		local current = teamState(state, "team.1")
		local cards = Fixtures.indexById(state.cardInstances)
		local pair = nil
		for firstIndex, firstId in current.handCardInstanceIds do
			for secondIndex = firstIndex + 1, #current.handCardInstanceIds do
				local secondId = current.handCardInstanceIds[secondIndex]
				if
					cards[firstId].sourceCritterInstanceId
					== cards[secondId].sourceCritterInstanceId
				then
					pair = { firstId, secondId }
					break
				end
			end
			if pair then
				break
			end
		end
		Harness.expect(pair ~= nil)
		local first = BattlePlan.queueCard(
			state,
			"team.1",
			legalRequest(state, definitions, "team.1", pair[1]),
			definitions
		)
		local second = BattlePlan.queueCard(
			first.value,
			"team.1",
			legalRequest(state, definitions, "team.1", pair[2]),
			definitions
		)
		local reordered =
			BattlePlan.reorderQueuedCard(second.value, "team.1", pair[2], 1, definitions)
		Harness.expect(reordered.ok)
		local queue = teamState(reordered.value, "team.1").queuedCards
		local byIndex = {}
		for _, queued in queue do
			byIndex[queued.queueIndex] = queued.cardInstanceId
		end
		Harness.equal(byIndex[1], pair[2])
		Harness.equal(byIndex[2], pair[1])
	end)

	Harness.test("commit deducts once locks plan and waits for opponent", function()
		local state, definitions = setup()
		local current = teamState(state, "team.1")
		local cardId = current.handCardInstanceIds[1]
		local queued = BattlePlan.queueCard(
			state,
			"team.1",
			legalRequest(state, definitions, "team.1", cardId),
			definitions
		)
		local cost = teamState(queued.value, "team.1").reservedEnergy
		local committed = BattlePlan.commitPlan(queued.value, "team.1", definitions)
		Harness.expect(committed.ok)
		Harness.equal(committed.value.phase, "PLANNING")
		Harness.equal(teamState(committed.value, "team.1").energy, 3 - cost)
		Harness.expect(
			Harness.hasError(
				BattlePlan.clearPlan(committed.value, "team.1", definitions),
				"PLAN_LOCKED"
			)
		)
		Harness.expect(not BattlePlan.commitPlan(committed.value, "team.1", definitions).ok)
	end)

	Harness.test("rejected commit leaves energy unchanged", function()
		local state, definitions = setup()
		local invalid = Harness.clone(state)
		teamState(invalid, "team.1").queuedCards = {
			{
				cardInstanceId = "missing",
				sourceCombatantId = "missing",
				targetCombatantIds = {},
				queueIndex = 1,
			},
		}
		local before = Harness.clone(invalid)
		Harness.expect(not BattlePlan.commitPlan(invalid, "team.1", definitions).ok)
		Harness.deepEqual(invalid, before)
	end)
end
