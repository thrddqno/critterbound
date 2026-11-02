--!strict

return function(Harness)
	local Factory = require("../../src/shared/Battle/BattleFactory")
	local BattlePlan = require("../../src/shared/Battle/BattlePlan")
	local Processor = require("../../src/server/Services/BattleCommandProcessor")
	local Rng = require("../../src/shared/Battle/DeterministicRng")
	local Deck = require("../../src/shared/Battle/Deck")
	local Validator = require("../../src/shared/Validation/DomainValidator")
	local Fixtures = require("../Fixtures/Run4Fixtures")

	local function setup()
		local input = Fixtures.createInput()
		local state = Factory.create(input, { rng = Rng, deck = Deck, validator = Validator }).value
		return { state = state, processedCommandsById = {} }, {
			battlePlan = BattlePlan,
			cardDefinitionsById = input.cardDefinitionsById,
		}
	end

	local function command(id, teamId, commandType, stateVersion, planVersion, payload)
		return {
			protocolVersion = 2,
			matchId = "battle.run4.fixture",
			teamId = teamId,
			commandId = id,
			expectedStateVersion = stateVersion,
			expectedPlanVersion = planVersion,
			commandType = commandType,
			payload = payload or {},
		}
	end

	Harness.test("authenticated command rejects impersonation and stale versions", function()
		local session, context = setup()
		local envelope = command("commit.1", "team.1", "COMMIT_PLAN", 1, 0)
		Harness.expect(
			Harness.hasError(Processor.process(session, 999, envelope, context), "NOT_TEAM_OWNER")
		)
		local stale = Harness.clone(envelope)
		stale.expectedStateVersion = 0
		Harness.expect(
			Harness.hasError(Processor.process(session, 101, stale, context), "STALE_STATE_VERSION")
		)
	end)

	Harness.test("teams commit independently from same shared version", function()
		local session, context = setup()
		local first = Processor.process(
			session,
			101,
			command("commit.1", "team.1", "COMMIT_PLAN", 1, 0),
			context
		)
		Harness.expect(first.ok)
		Harness.equal(first.value.session.state.phase, "PLANNING")
		Harness.equal(first.value.session.state.stateVersion, 1)
		local second = Processor.process(
			first.value.session,
			202,
			command("commit.2", "team.2", "COMMIT_PLAN", 1, 0),
			context
		)
		Harness.expect(second.ok)
		Harness.equal(second.value.session.state.phase, "COMMITTED")
		Harness.equal(second.value.session.state.stateVersion, 2)
	end)

	Harness.test("duplicate command returns receipt without applying twice", function()
		local session, context = setup()
		local envelope = command("commit.1", "team.1", "COMMIT_PLAN", 1, 0)
		local first = Processor.process(session, 101, envelope, context)
		local duplicate = Processor.process(first.value.session, 101, envelope, context)
		Harness.expect(duplicate.ok)
		Harness.expect(duplicate.value.duplicate)
		Harness.deepEqual(duplicate.value.session.state, first.value.session.state)
		local altered = Harness.clone(envelope)
		altered.commandType = "CLEAR_PLAN"
		Harness.expect(
			Harness.hasError(
				Processor.process(first.value.session, 101, altered, context),
				"COMMAND_ID_REUSED"
			)
		)
	end)

	Harness.test("invalid commands never mutate session", function()
		local session, context = setup()
		local before = Harness.clone(session)
		local invalid = command("bad", "team.1", "QUEUE_CARD", 1, 0, { cardInstanceId = "missing" })
		Harness.expect(not Processor.process(session, 101, invalid, context).ok)
		Harness.deepEqual(session, before)
	end)

	Harness.test("accepted private command advances only team plan version", function()
		local session, context = setup()
		local teamState = session.state.teamRoundStates[1]
		local cardId = teamState.handCardInstanceIds[1]
		local cards = Fixtures.indexById(session.state.cardInstances)
		local source = nil
		for _, combatant in session.state.combatants do
			if combatant.critterInstanceId == cards[cardId].sourceCritterInstanceId then
				source = combatant
				break
			end
		end
		local definition = context.cardDefinitionsById[cards[cardId].definitionId]
		local target = source
		if definition.targetingRule == "ENEMY" then
			for _, combatant in session.state.combatants do
				if combatant.teamId ~= source.teamId then
					target = combatant
					break
				end
			end
		end
		if definition.targetingRule == "ALLY" then
			for _, combatant in session.state.combatants do
				if combatant.teamId == source.teamId and combatant.id ~= source.id then
					target = combatant
					break
				end
			end
		end
		local envelope = command("queue.1", "team.1", "QUEUE_CARD", 1, 0, {
			cardInstanceId = cardId,
			sourceCombatantId = source.id,
			targetCombatantIds = { target.id },
		})
		local result = Processor.process(session, 101, envelope, context)
		Harness.expect(result.ok)
		Harness.equal(result.value.session.state.stateVersion, 1)
		Harness.equal(result.value.receipt.planVersion, 1)
	end)

	Harness.test("same state and commands produce identical results", function()
		local firstSession, firstContext = setup()
		local secondSession, secondContext = setup()
		local envelope = command("commit.1", "team.1", "COMMIT_PLAN", 1, 0)
		local first = Processor.process(firstSession, 101, envelope, firstContext)
		local second = Processor.process(secondSession, 101, envelope, secondContext)
		Harness.deepEqual(first, second)
	end)
end
