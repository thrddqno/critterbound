--!strict

return function(Harness)
	local Deck = require("../../src/shared/Battle/Deck")
	local DeterministicRng = require("../../src/shared/Battle/DeterministicRng")
	local RoundEconomy = require("../../src/shared/Battle/RoundEconomy")
	local RoundResolver = require("../../src/shared/Battle/RoundResolver")
	local Fixtures = require("../Fixtures/Run4BFixtures")

	local function definitions(extra)
		local result = Fixtures.clone(Fixtures.CardDefinitionsById)
		for _, value in extra or {} do
			result[value.id] = value
		end
		return result
	end

	local function resolve(state, extra)
		return RoundResolver.resolveRound(state, {
			cardDefinitionsById = definitions(extra),
			deck = Deck,
			economy = RoundEconomy,
			shuffle = DeterministicRng.shuffle,
			drawPerRound = 3,
		})
	end

	local function ids(count, prefix)
		local result = {}
		for index = 1, count do
			table.insert(result, `{prefix}.{index}`)
		end
		return result
	end

	Harness.test("round transition discards resolved cards, resets plans, and draws", function()
		local state = Fixtures.createState()
		local teamState = Fixtures.findTeamState(state, "team.1")
		teamState.energy = 3
		teamState.handCardInstanceIds = { "card.keep", "card.played" }
		teamState.drawPileCardInstanceIds = ids(4, "card.draw")
		teamState.discardCardInstanceIds = { "card.discard" }
		Fixtures.makeCard(
			state,
			"card.played",
			Fixtures.CardDefinitions.Attack.id,
			"combatant:t1:s2"
		)
		Fixtures.queue(state, "team.1", "card.played", "combatant:t1:s2", { "combatant:t2:s1" })

		local result = resolve(state)
		Harness.expect(result.ok)
		local nextState = result.value.state
		local nextTeam = Fixtures.findTeamState(nextState, "team.1")

		Harness.equal(nextState.phase, "PLANNING")
		Harness.equal(nextState.roundNumber, 2)
		Harness.equal(nextState.lastResolvedRound, 1)
		Harness.equal(nextTeam.energy, 5)
		Harness.equal(nextTeam.reservedEnergy, 0)
		Harness.equal(nextTeam.committed, false)
		Harness.equal(nextTeam.planVersion, 1)
		Harness.equal(#nextTeam.queuedCards, 0)
		Harness.expect(table.find(nextTeam.handCardInstanceIds, "card.keep") ~= nil)
		Harness.expect(table.find(nextTeam.handCardInstanceIds, "card.played") == nil)
		Harness.equal(#nextTeam.handCardInstanceIds, 4)
		Harness.expect(table.find(nextTeam.discardCardInstanceIds, "card.discard") ~= nil)
		Harness.expect(table.find(nextTeam.discardCardInstanceIds, "card.played") ~= nil)
		Harness.equal(#nextTeam.drawPileCardInstanceIds, 1)
	end)

	Harness.test("energy gain caps at ten", function()
		local state = Fixtures.createState()
		Fixtures.findTeamState(state, "team.1").energy = 9
		local result = resolve(state)
		Harness.expect(result.ok)
		Harness.equal(Fixtures.findTeamState(result.value.state, "team.1").energy, 10)
	end)

	Harness.test("draw respects the hand cap at nine cards", function()
		local cases = {
			{ handSize = 6, drawnCount = 3 },
			{ handSize = 7, drawnCount = 2 },
			{ handSize = 8, drawnCount = 1 },
			{ handSize = 9, drawnCount = 0 },
		}
		for _, case in cases do
			local state = Fixtures.createState()
			local teamState = Fixtures.findTeamState(state, "team.1")
			teamState.handCardInstanceIds = ids(case.handSize, "card.hand")
			teamState.drawPileCardInstanceIds = ids(4, "card.draw")
			local result = resolve(state)
			Harness.expect(result.ok)
			local nextTeam = Fixtures.findTeamState(result.value.state, "team.1")
			Harness.equal(#nextTeam.handCardInstanceIds, 9)
			Harness.equal(#nextTeam.drawPileCardInstanceIds, 4 - case.drawnCount)
			Harness.equal(nextTeam.lastDrawResult.requestedCount, 3)
			Harness.equal(nextTeam.lastDrawResult.drawnCount, case.drawnCount)
			Harness.equal(nextTeam.lastDrawResult.isPartial, case.drawnCount < 3)
			Harness.equal(nextTeam.pendingDiscardCount, nil)
			Harness.equal(result.value.state.planningSubphase, nil)
		end
	end)

	Harness.test("a completed match does not run the round transition", function()
		local state = Fixtures.createState()
		for _, combatantId in { "combatant:t2:s1", "combatant:t2:s2", "combatant:t2:s3" } do
			Fixtures.findCombatant(state, combatantId).currentHealth = 1
		end
		local teamState = Fixtures.findTeamState(state, "team.1")
		teamState.energy = 3
		for index, targetId in { "combatant:t2:s1", "combatant:t2:s2", "combatant:t2:s3" } do
			local cardId = `card.feral.{index}`
			Fixtures.makeCard(state, cardId, Fixtures.CardDefinitions.Attack.id, "combatant:t1:s2")
			Fixtures.queue(state, "team.1", cardId, "combatant:t1:s2", { targetId })
		end
		local result = resolve(state)
		Harness.expect(result.ok)
		Harness.equal(result.value.state.phase, "FINISHED")
		Harness.equal(result.value.state.roundNumber, 1)
		Harness.equal(Fixtures.findTeamState(result.value.state, "team.1").energy, 3)
	end)

	Harness.test("duplicate transition is prevented by phase and resolved-round guards", function()
		local state = Fixtures.createState()
		local first = resolve(state)
		Harness.expect(first.ok)

		local duplicatePhase = resolve(first.value.state)
		Harness.expect(Harness.hasError(duplicatePhase, "INVALID_PHASE"))

		local duplicateRound = first.value.state
		duplicateRound.phase = "RESOLVING"
		for _, teamState in duplicateRound.teamRoundStates do
			teamState.committed = true
		end
		duplicateRound.lastResolvedRound = duplicateRound.roundNumber
		local duplicate = resolve(duplicateRound)
		Harness.expect(Harness.hasError(duplicate, "ROUND_ALREADY_RESOLVED"))
	end)
end
