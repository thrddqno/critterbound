--!strict

return function(Harness)
	local Mapper = require("../../src/client/Presentation/BattlePresentationMapper")
	local PlanningState = require("../../src/client/Presentation/PlanningState")
	local MockBattleSession = require("../../src/client/Development/MockBattleSession")
	local mapped = Mapper.map(MockBattleSession.createSnapshot())
	Harness.expect(mapped.ok)
	local model = mapped.value

	Harness.test("queues and removes card instances", function()
		local state = PlanningState.new()
		local queued = PlanningState.queueCard(state, model.hand[1], model)
		Harness.expect(queued.ok)
		Harness.equal(queued.state.queuedCards[1].card.id, model.hand[1].id)
		local removed = PlanningState.removeCard(queued.state, model.hand[1].id)
		Harness.expect(removed.ok)
		Harness.equal(#removed.state.queuedCards, 0)
	end)

	Harness.test("rejects duplicate card instance", function()
		local first = PlanningState.queueCard(PlanningState.new(), model.hand[1], model)
		local duplicate = PlanningState.queueCard(first.state, model.hand[1], model)
		Harness.expect(not duplicate.ok)
		Harness.equal(duplicate.error, "CARD_ALREADY_QUEUED")
	end)

	Harness.test("calculates energy preview and rejects over budget", function()
		local first = PlanningState.queueCard(PlanningState.new(), model.hand[2], model)
		Harness.expect(first.ok)
		local preview = PlanningState.energy(model, first.state)
		Harness.equal(preview.allocated, 2)
		Harness.equal(preview.remaining, 1)
		local secondFeral = Harness.clone(model.hand[2])
		secondFeral.id = "unaffordable.feral"
		local rejected = PlanningState.queueCard(first.state, secondFeral, model)
		Harness.expect(not rejected.ok)
		Harness.equal(rejected.error, "INSUFFICIENT_ENERGY")
	end)

	Harness.test("preserves per-Critter queue order after removal", function()
		local first = PlanningState.queueCard(PlanningState.new(), model.hand[1], model)
		local secondCard = Harness.clone(model.hand[1])
		secondCard.id = "same-source.second"
		local second = PlanningState.queueCard(first.state, secondCard, model)
		Harness.equal(second.state.queuedCards[2].sourceOrder, 2)
		local removed = PlanningState.removeCard(second.state, model.hand[1].id)
		Harness.equal(removed.state.queuedCards[1].sourceOrder, 1)
	end)

	Harness.test("undo removes last action and clear removes all actions", function()
		local first = PlanningState.queueCard(PlanningState.new(), model.hand[1], model)
		local second = PlanningState.queueCard(first.state, model.hand[2], model)
		local undone = PlanningState.undo(second.state)
		Harness.expect(undone.ok)
		Harness.equal(#undone.state.queuedCards, 1)
		Harness.equal(undone.state.queuedCards[1].card.id, model.hand[1].id)
		local cleared = PlanningState.clear(undone.state)
		Harness.expect(cleared.ok)
		Harness.equal(#cleared.state.queuedCards, 0)
		Harness.equal(PlanningState.undo(cleared.state).error, "QUEUE_EMPTY")
	end)

	Harness.test("card reasons explain queued unaffordable and defeated cards", function()
		local queued = PlanningState.queueCard(PlanningState.new(), model.hand[2], model)
		Harness.equal(
			PlanningState.cardDisabledReason(queued.state, model.hand[2], model),
			"Queued — tap queued card to remove"
		)
		local unaffordable = Harness.clone(model.hand[2])
		unaffordable.id = "unaffordable.reason"
		Harness.equal(
			PlanningState.cardDisabledReason(queued.state, unaffordable, model),
			`Needs {unaffordable.energyCost} energy`
		)
		local defeatedModel = Harness.clone(model)
		for _, critter in defeatedModel.critters do
			if critter.id == defeatedModel.hand[1].sourceCombatantId then
				critter.defeated = true
			end
		end
		Harness.equal(
			PlanningState.cardDisabledReason(
				PlanningState.new(),
				defeatedModel.hand[1],
				defeatedModel
			),
			"Source Critter is defeated"
		)
	end)

	Harness.test("per-Critter capacity disables fifth card until removal", function()
		local capacityModel = Harness.clone(model)
		capacityModel.energy.available = 100
		local sourceCard = capacityModel.hand[1]
		local cards = {}
		for index = 1, 5 do
			local card = Harness.clone(sourceCard)
			card.id = `capacity.card.{index}`
			table.insert(cards, card)
		end
		local state = PlanningState.new()
		for index = 1, 4 do
			local result = PlanningState.queueCard(state, cards[index], capacityModel)
			Harness.expect(result.ok)
			state = result.state
		end
		Harness.equal(
			PlanningState.cardDisabledReason(state, cards[5], capacityModel),
			"Queue full (4/4)"
		)
		Harness.equal(
			PlanningState.queueCard(state, cards[5], capacityModel).error,
			"CRITTER_QUEUE_LIMIT_EXCEEDED"
		)
		local removed = PlanningState.removeCard(state, cards[2].id)
		Harness.expect(PlanningState.queueCard(removed.state, cards[5], capacityModel).ok)
	end)

	Harness.test("commit locks planning and reset restores state", function()
		local queued = PlanningState.queueCard(PlanningState.new(), model.hand[1], model)
		local committed = PlanningState.commit(queued.state, model)
		Harness.expect(committed.ok)
		Harness.expect(committed.state.committed)
		local rejected = PlanningState.removeCard(committed.state, model.hand[1].id)
		Harness.expect(not rejected.ok)
		Harness.deepEqual(PlanningState.reset(), PlanningState.new())
	end)

	Harness.test("planning operations never mutate prior state", function()
		local state = PlanningState.new()
		local before = Harness.clone(state)
		PlanningState.queueCard(state, model.hand[1], model)
		Harness.deepEqual(state, before)
	end)
end
