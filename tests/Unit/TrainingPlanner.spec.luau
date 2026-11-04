--!strict

return function(Harness)
	local Factory = require("../../src/shared/Battle/BattleFactory")
	local BattlePlan = require("../../src/shared/Battle/BattlePlan")
	local Content = require("../../src/shared/Definitions/TrainingGrounds")
	local Planner = require("../../src/server/AI/TrainingPlanner")
	local Fixtures = require("../Fixtures/Run5Fixtures")

	local function setup()
		local input = Content.createInput(101, 1)
		local deps = Fixtures.dependencies()
		local state = Factory.create(input, {
			rng = deps.rng,
			criticalRngSeed = 9001,
			deck = deps.deck,
			validator = deps.validator,
		}).value
		return state, input
	end

	Harness.test("AI plan queues only legal cards through BattlePlan", function()
		local state, input = setup()
		local planned = Planner.plan(state, input.aiTeamId, input.cardDefinitionsById)
		Harness.expect(planned.ok)
		local nextState = state
		for _, request in planned.value.requests do
			local queued =
				BattlePlan.queueCard(nextState, input.aiTeamId, request, input.cardDefinitionsById)
			Harness.expect(queued.ok)
			nextState = queued.value
		end
		Harness.expect(
			BattlePlan.commitPlan(nextState, input.aiTeamId, input.cardDefinitionsById).ok
		)
	end)

	Harness.test("AI prefers healing a significantly injured ally", function()
		local state, input = setup()
		local aiState = state.teamRoundStates[2]
		local cardsById = {}
		for _, card in state.cardInstances do
			cardsById[card.id] = card
		end
		local healingCardId = nil
		for _, card in state.cardInstances do
			if card.definitionId == "card.training.tide.mend" then
				local sourceIsAi = string.find(card.sourceCritterInstanceId, ".ai.", 1, true) ~= nil
				if sourceIsAi then
					healingCardId = card.id
					break
				end
			end
		end
		Harness.expect(healingCardId ~= nil)
		aiState.handCardInstanceIds = { healingCardId }
		for _, combatant in state.combatants do
			if combatant.teamId == input.aiTeamId and combatant.slot == 2 then
				combatant.currentHealth = 20
			end
		end
		local planned = Planner.plan(state, input.aiTeamId, input.cardDefinitionsById)
		Harness.equal(planned.value.requests[1].cardInstanceId, healingCardId)
		local targetId = planned.value.requests[1].targetCombatantIds[1]
		local target = nil
		for _, combatant in state.combatants do
			if combatant.id == targetId then
				target = combatant
			end
		end
		Harness.equal(target.slot, 2)
	end)

	Harness.test("AI plan ignores player private hand and queue", function()
		local first, input = setup()
		local second = Harness.clone(first)
		second.teamRoundStates[1].handCardInstanceIds = {}
		second.teamRoundStates[1].queuedCards = {
			{
				cardInstanceId = "secret.card",
				sourceCombatantId = "secret.source",
				targetCombatantIds = { "secret.target" },
				queueIndex = 1,
			},
		}
		local firstPlan = Planner.plan(first, input.aiTeamId, input.cardDefinitionsById)
		local secondPlan = Planner.plan(second, input.aiTeamId, input.cardDefinitionsById)
		Harness.deepEqual(firstPlan, secondPlan)
	end)

	Harness.test("AI submits no target IDs for automatic ENEMY cards", function()
		local state, input = setup()
		local aiState = state.teamRoundStates[2]
		local attackCardId = nil
		for _, card in state.cardInstances do
			local definition = input.cardDefinitionsById[card.definitionId]
			if
				definition.targetingRule == "ENEMY"
				and string.find(card.sourceCritterInstanceId, ".ai.", 1, true)
			then
				attackCardId = card.id
				break
			end
		end
		Harness.expect(attackCardId ~= nil)
		aiState.handCardInstanceIds = { attackCardId }
		local planned = Planner.plan(state, input.aiTeamId, input.cardDefinitionsById)
		Harness.expect(planned.ok)
		Harness.equal(#planned.value.requests, 1)
		Harness.deepEqual(planned.value.requests[1].targetCombatantIds, {})
	end)

	Harness.test("AI never plans more than four cards for one Critter", function()
		local state, input = setup()
		local aiState = state.teamRoundStates[2]
		local sourceInstanceId = nil
		for _, combatant in state.combatants do
			if combatant.teamId == input.aiTeamId then
				sourceInstanceId = combatant.critterInstanceId
				break
			end
		end
		local hand = {}
		local definitions = Harness.clone(input.cardDefinitionsById)
		for _, card in state.cardInstances do
			if card.sourceCritterInstanceId == sourceInstanceId then
				table.insert(hand, card.id)
				definitions[card.definitionId].energyCost = 0
			end
		end
		Harness.equal(#hand, 8)
		aiState.handCardInstanceIds = hand
		local planned = Planner.plan(state, input.aiTeamId, definitions)
		Harness.expect(planned.ok)
		Harness.equal(#planned.value.requests, 4)
		for _, request in planned.value.requests do
			Harness.equal(request.sourceCombatantId, planned.value.requests[1].sourceCombatantId)
		end
	end)
end
