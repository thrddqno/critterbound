--!strict

return function(Harness)
	local Factory = require("../../src/shared/Battle/BattleFactory")
	local BattlePlan = require("../../src/shared/Battle/BattlePlan")
	local Projector = require("../../src/server/Services/BattleProjector")
	local Mapper = require("../../src/client/Presentation/BattlePresentationMapper")
	local Rng = require("../../src/shared/Battle/DeterministicRng")
	local Deck = require("../../src/shared/Battle/Deck")
	local Validator = require("../../src/shared/Validation/DomainValidator")
	local StatusEffects = require("../../src/shared/Battle/StatusEffects")
	local Fixtures = require("../Fixtures/Run4Fixtures")

	local function setup()
		local input = Fixtures.createInput()
		local state = Factory.create(
			input,
			{ rng = Rng, criticalRngSeed = 9001, deck = Deck, validator = Validator }
		).value
		local instances = {}
		for _, team in input.teams do
			for _, instance in team.critterInstances do
				instances[instance.id] = instance
			end
		end
		return state,
			input,
			{
				cardDefinitionsById = input.cardDefinitionsById,
				critterDefinitionsById = input.critterDefinitionsById,
				critterInstancesById = instances,
			}
	end

	local function teamState(state, teamId)
		for _, value in state.teamRoundStates do
			if value.teamId == teamId then
				return value
			end
		end
		error("Missing team")
	end

	Harness.test("projection hides opponent private zones and RNG", function()
		local state, _, context = setup()
		local result = Projector.project(state, 101, context)
		Harness.expect(result.ok)
		Harness.expect(result.value.rng == nil)
		Harness.expect(result.value.criticalRng == nil)
		Harness.expect(result.value.battleState.criticalRng == nil)
		Harness.expect(result.value.processedCommandsById == nil)
		for _, projected in result.value.battleState.teamRoundStates do
			if projected.teamId == "team.1" then
				Harness.equal(#projected.handCardInstanceIds, 6)
			else
				Harness.equal(#projected.handCardInstanceIds, 0)
				Harness.expect(projected.energy == nil)
			end
		end
	end)

	Harness.test("projection exposes own queue but hides opponent during planning", function()
		local state, input, context = setup()
		local teamOne = teamState(state, "team.1")
		local cardId = teamOne.handCardInstanceIds[1]
		local cards = Fixtures.indexById(state.cardInstances)
		local source = nil
		for _, combatant in state.combatants do
			if combatant.critterInstanceId == cards[cardId].sourceCritterInstanceId then
				source = combatant
				break
			end
		end
		local definition = input.cardDefinitionsById[cards[cardId].definitionId]
		local target = source
		if definition.targetingRule == "ENEMY" then
			for _, combatant in state.combatants do
				if combatant.teamId ~= source.teamId then
					target = combatant
					break
				end
			end
		end
		if definition.targetingRule == "ALLY" then
			for _, combatant in state.combatants do
				if combatant.teamId == source.teamId and combatant.id ~= source.id then
					target = combatant
					break
				end
			end
		end
		local queued = BattlePlan.queueCard(state, "team.1", {
			cardInstanceId = cardId,
			sourceCombatantId = source.id,
			targetCombatantIds = { target.id },
		}, input.cardDefinitionsById)
		local own = Projector.project(queued.value, 101, context)
		local opponent = Projector.project(queued.value, 202, context)
		Harness.equal(#own.value.visibleQueuedCards, 1)
		Harness.equal(#opponent.value.visibleQueuedCards, 0)
	end)

	Harness.test("both plans reveal only after both commits", function()
		local state, input, context = setup()
		local first = BattlePlan.commitPlan(state, "team.1", input.cardDefinitionsById)
		Harness.equal(#Projector.project(first.value, 202, context).value.visibleQueuedCards, 0)
		local second = BattlePlan.commitPlan(first.value, "team.2", input.cardDefinitionsById)
		Harness.equal(second.value.phase, "RESOLVING")
		Harness.expect(Projector.project(second.value, 101, context).ok)
	end)

	Harness.test("projected snapshot remains mapper compatible and isolated", function()
		local state, _, context = setup()
		local projection = Projector.project(state, 101, context)
		Harness.expect(projection.ok)
		local before = Harness.clone(state)
		projection.value.battleState.combatants[1].currentHealth = 0
		Harness.deepEqual(state, before)
		local fresh = Projector.project(state, 101, context)
		Harness.expect(Mapper.map(fresh.value).ok)
	end)

	Harness.test("projection rejects nonparticipant", function()
		local state, _, context = setup()
		Harness.expect(
			Harness.hasError(Projector.project(state, 999, context), "VIEWER_NOT_IN_BATTLE")
		)
	end)

	Harness.test("projection synchronizes shields effective Speed and allocated energy", function()
		local state, _, context = setup()
		local combatant = state.combatants[1]
		combatant.shields = {
			{ id = "shield.1", sourceCombatantId = combatant.id, amount = 7, expiresAtRound = 1 },
			{ id = "shield.2", sourceCombatantId = combatant.id, amount = 5, expiresAtRound = 1 },
		}
		combatant.statusEffects = {
			{
				id = "speed.1",
				statusId = "SPEED_UP",
				sourceCombatantId = combatant.id,
				targetCombatantId = combatant.id,
				magnitude = 4,
				duration = 2,
				stackCount = 2,
				appliedRound = 1,
				expiresAtRound = 2,
			},
		}
		teamState(state, "team.1").reservedEnergy = 2
		context.statusEffects = StatusEffects
		context.initiativeCombatantIds = { combatant.id }
		local projected = Projector.project(state, 101, context)
		Harness.equal(projected.value.shieldsByCombatantId[combatant.id], 12)
		Harness.equal(
			projected.value.effectiveSpeedByCombatantId[combatant.id],
			combatant.stats.speed + 8
		)
		Harness.equal(projected.value.battleState.teamRoundStates[1].reservedEnergy, 2)
		Harness.deepEqual(projected.value.initiativeCombatantIds, { combatant.id })
	end)
end
