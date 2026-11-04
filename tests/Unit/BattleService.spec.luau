--!strict

return function(Harness)
	local Fixtures = require("../Fixtures/Run5Fixtures")

	local function viewerRoundState(snapshot)
		for _, roundState in snapshot.battleState.teamRoundStates do
			if roundState.teamId == snapshot.viewerTeamId then
				return roundState
			end
		end
		error("Missing viewer round state")
	end

	local function roundStateForTeam(state, teamId)
		for _, roundState in state.teamRoundStates do
			if roundState.teamId == teamId then
				return roundState
			end
		end
		error(`Missing round state for {teamId}`)
	end

	local function legalPayload(snapshot, cardId)
		local instance = snapshot.cardInstancesById[cardId]
		local definition = instance and snapshot.cardDefinitionsById[instance.definitionId]
		if definition == nil then
			return nil
		end
		local source = nil
		for _, combatant in snapshot.battleState.combatants do
			if combatant.critterInstanceId == instance.sourceCritterInstanceId then
				source = combatant
				break
			end
		end
		if source == nil or source.currentHealth <= 0 then
			return nil
		end
		local targetIds = {}
		if definition.targetingRule == "ALLY" then
			for _, combatant in snapshot.battleState.combatants do
				if
					combatant.teamId == source.teamId
					and combatant.id ~= source.id
					and combatant.currentHealth > 0
				then
					targetIds = { combatant.id }
					break
				end
			end
			if #targetIds == 0 then
				return nil
			end
		elseif definition.targetingRule == "ANY" then
			local candidates = {}
			for _, combatant in snapshot.battleState.combatants do
				if combatant.teamId ~= source.teamId and combatant.currentHealth > 0 then
					table.insert(candidates, combatant)
				end
			end
			table.sort(candidates, function(a, b)
				if a.currentHealth ~= b.currentHealth then
					return a.currentHealth < b.currentHealth
				end
				return a.id < b.id
			end)
			if candidates[1] == nil then
				return nil
			end
			targetIds = { candidates[1].id }
		end
		return {
			cardInstanceId = cardId,
			sourceCombatantId = source.id,
			targetCombatantIds = targetIds,
		},
			definition
	end

	local function chooseCard(snapshot, attackOnly)
		local roundState = viewerRoundState(snapshot)
		local queued = {}
		for _, value in snapshot.visibleQueuedCards do
			queued[value.cardInstanceId] = true
		end
		local fallback = nil
		for _, cardId in roundState.handCardInstanceIds do
			if not queued[cardId] then
				local payload, definition = legalPayload(snapshot, cardId)
				if
					payload ~= nil
					and definition.energyCost <= snapshot.battleState.teamRoundStates[1].energy
				then
					local damage = false
					for _, effect in definition.effects or {} do
						if effect.kind == "DAMAGE" or effect.statusId == "POISON" then
							damage = true
						end
					end
					if damage then
						return payload
					end
					fallback = fallback or payload
				end
			end
		end
		return if attackOnly then nil else fallback
	end

	local function send(service, userId, snapshot, id, commandType, payload)
		return service.processCommand(userId, Fixtures.command(snapshot, id, commandType, payload))
	end

	Harness.test("BattleService starts one owned match and hides enemy private state", function()
		local service = Fixtures.createService()
		local first = service.startBattle(101)
		local second = service.startBattle(101)
		Harness.expect(first.ok and second.ok)
		Harness.equal(first.value.snapshot.battleState.id, second.value.snapshot.battleState.id)
		for _, roundState in first.value.snapshot.battleState.teamRoundStates do
			if roundState.teamId ~= first.value.snapshot.viewerTeamId then
				Harness.equal(#roundState.handCardInstanceIds, 0)
				Harness.expect(roundState.energy == nil)
			end
		end
	end)

	Harness.test("BattleService rejects malformed and unauthorized client commands", function()
		local service = Fixtures.createService()
		local snapshot = Fixtures.start(service, 101)
		Harness.expect(Harness.hasError(service.handleRequest(101, "bad"), "INVALID_REQUEST"))
		local enemy = Fixtures.command(snapshot, "enemy.command", "COMMIT_PLAN", {})
		enemy.teamId = "team.training"
		Harness.expect(Harness.hasError(service.processCommand(101, enemy), "NOT_TEAM_OWNER"))
		local malformed = Fixtures.command(snapshot, "bad.payload", "QUEUE_CARD", "bad")
		Harness.expect(Harness.hasError(service.processCommand(101, malformed), "INVALID_PAYLOAD"))
	end)

	Harness.test(
		"BattleService queues idempotently and resolves both committed plans once",
		function()
			local service = Fixtures.createService()
			local snapshot = Fixtures.start(service, 101)
			local payload = chooseCard(snapshot, false)
			Harness.expect(payload ~= nil)
			local envelope = Fixtures.command(snapshot, "queue.once", "QUEUE_CARD", payload)
			local first = service.processCommand(101, envelope)
			local duplicate = service.processCommand(101, envelope)
			Harness.expect(first.ok and duplicate.ok)
			Harness.expect(duplicate.value.duplicate)
			Harness.equal(#duplicate.value.snapshot.visibleQueuedCards, 1)

			local committed =
				send(service, 101, duplicate.value.snapshot, "commit.round1", "COMMIT_PLAN", {})
			Harness.expect(committed.ok)
			Harness.expect(committed.value.resolution ~= nil)
			Harness.equal(committed.value.resolution.preSnapshot.battleState.phase, "RESOLVING")
			Harness.equal(committed.value.snapshot.battleState.roundNumber, 2)
			Harness.equal(committed.value.snapshot.battleState.phase, "PLANNING")
			local initiative = committed.value.resolution.events[1]
			Harness.equal(initiative.kind, "INITIATIVE_DETERMINED")
			Harness.deepEqual(
				committed.value.snapshot.initiativeCombatantIds,
				initiative.payload.initiativeCombatantIds
			)
			local duplicateCommit =
				send(service, 101, duplicate.value.snapshot, "commit.round1", "COMMIT_PLAN", {})
			Harness.expect(duplicateCommit.ok)
			Harness.expect(duplicateCommit.value.duplicate)
			Harness.expect(duplicateCommit.value.resolution == nil)
		end
	)

	Harness.test("BattleService restart is fresh and duplicate-safe", function()
		local service = Fixtures.createService()
		local initial = Fixtures.start(service, 101)
		local restarted = service.restartBattle(101, "restart.1")
		local duplicate = service.restartBattle(101, "restart.1")
		Harness.expect(restarted.ok and duplicate.ok)
		Harness.expect(restarted.value.snapshot.battleState.id ~= initial.battleState.id)
		Harness.deepEqual(restarted, duplicate)
		Harness.equal(restarted.value.snapshot.battleState.roundNumber, 1)
		Harness.equal(restarted.value.snapshot.battleState.phase, "PLANNING")
	end)

	Harness.test("commit before deadline resolves immediately when AI is committed", function()
		local service, timing = Fixtures.createTimedService()
		local snapshot = Fixtures.start(service, 601)
		local deadline = snapshot.battleState.planningDeadline
		Harness.equal(deadline, 1_045)
		Harness.expect(roundStateForTeam(snapshot.battleState, "team.training").committed)

		timing.advance(44)
		local committed = send(service, 601, snapshot, "early.commit", "COMMIT_PLAN", {})
		Harness.expect(committed.ok)
		Harness.expect(committed.value.resolution ~= nil)
		Harness.equal(committed.value.resolution.preSnapshot.battleState.phase, "RESOLVING")
		Harness.equal(committed.value.snapshot.battleState.roundNumber, 2)
		Harness.equal(committed.value.snapshot.battleState.planningDeadline, 1_089)
	end)

	Harness.test("timeout auto-commits a queued player plan", function()
		local baseResolver = Fixtures.dependencies().resolver
		local resolvingState = nil
		local service, timing = Fixtures.createTimedService({
			resolver = {
				resolveRound = function(state, dependencies)
					resolvingState = state
					return baseResolver.resolveRound(state, dependencies)
				end,
			},
		})
		local snapshot = Fixtures.start(service, 602)
		local payload = chooseCard(snapshot, false)
		Harness.expect(payload ~= nil)
		local queued = send(service, 602, snapshot, "timeout.queue", "QUEUE_CARD", payload)
		Harness.expect(queued.ok)

		timing.advance(45)
		local refreshed = service.requestSnapshot(602)
		Harness.expect(refreshed.ok)
		Harness.equal(refreshed.value.snapshot.battleState.roundNumber, 2)
		local playerState = roundStateForTeam(resolvingState, snapshot.viewerTeamId)
		Harness.expect(playerState.committed)
		Harness.equal(#playerState.queuedCards, 1)
		Harness.equal(playerState.queuedCards[1].cardInstanceId, payload.cardInstanceId)
	end)

	Harness.test("timeout turns an empty player queue into a committed pass", function()
		local baseResolver = Fixtures.dependencies().resolver
		local resolvingState = nil
		local service, timing = Fixtures.createTimedService({
			resolver = {
				resolveRound = function(state, dependencies)
					resolvingState = state
					return baseResolver.resolveRound(state, dependencies)
				end,
			},
		})
		local snapshot = Fixtures.start(service, 603)

		timing.advance(45)
		local refreshed = service.requestSnapshot(603)
		Harness.expect(refreshed.ok)
		Harness.equal(refreshed.value.snapshot.battleState.roundNumber, 2)
		local playerState = roundStateForTeam(resolvingState, snapshot.viewerTeamId)
		Harness.expect(playerState.committed)
		Harness.equal(#playerState.queuedCards, 0)
	end)

	Harness.test("commit versus timeout race resolves once and rejects the late commit", function()
		local baseResolver = Fixtures.dependencies().resolver
		local resolutionCount = 0
		local service, timing = Fixtures.createTimedService({
			resolver = {
				resolveRound = function(state, dependencies)
					resolutionCount += 1
					return baseResolver.resolveRound(state, dependencies)
				end,
			},
		})
		local snapshot = Fixtures.start(service, 604)
		local deadlineCallback = timing.scheduled[1].callback
		timing.time = snapshot.battleState.planningDeadline

		local late = send(service, 604, snapshot, "race.commit", "COMMIT_PLAN", {})
		Harness.expect(Harness.hasError(late, "PLANNING_DEADLINE_EXPIRED"))
		Harness.equal(resolutionCount, 1)
		deadlineCallback()
		timing.advance(0)
		Harness.equal(resolutionCount, 1)
		local refreshed = service.requestSnapshot(604)
		Harness.expect(refreshed.ok)
		Harness.equal(refreshed.value.snapshot.battleState.roundNumber, 2)
	end)

	Harness.test("late queue and commit requests are rejected", function()
		for index, commandType in { "QUEUE_CARD", "COMMIT_PLAN" } do
			local service, timing = Fixtures.createTimedService()
			local snapshot = Fixtures.start(service, 610 + index)
			local payload = if commandType == "QUEUE_CARD" then chooseCard(snapshot, false) else {}
			Harness.expect(payload ~= nil)
			timing.time = snapshot.battleState.planningDeadline
			local late =
				send(service, 610 + index, snapshot, `late.{commandType}`, commandType, payload)
			Harness.expect(Harness.hasError(late, "PLANNING_DEADLINE_EXPIRED"))
		end
	end)

	Harness.test("client commands and refreshes cannot extend the server deadline", function()
		local service, timing = Fixtures.createTimedService()
		local snapshot = Fixtures.start(service, 605)
		local deadline = snapshot.battleState.planningDeadline
		timing.advance(10)
		local payload = chooseCard(snapshot, false)
		Harness.expect(payload ~= nil)
		payload.planningDeadline = deadline + 10_000
		local queued = send(service, 605, snapshot, "deadline.queue", "QUEUE_CARD", payload)
		Harness.expect(queued.ok)
		Harness.equal(queued.value.snapshot.battleState.planningDeadline, deadline)
		local refreshed = service.requestSnapshot(605)
		Harness.expect(refreshed.ok)
		Harness.equal(refreshed.value.snapshot.battleState.planningDeadline, deadline)
		local reentered = service.startBattle(605)
		Harness.expect(reentered.ok)
		Harness.equal(reentered.value.snapshot.battleState.planningDeadline, deadline)
	end)

	Harness.test("PvE AI plans and commits immediately under the planning phase", function()
		local basePlanner = Fixtures.dependencies().aiPlanner
		local planCount = 0
		local service, timing = Fixtures.createTimedService({
			aiPlanner = {
				plan = function(...)
					planCount += 1
					return basePlanner.plan(...)
				end,
			},
		})
		local snapshot = Fixtures.start(service, 606)
		Harness.equal(timing.time, 1_000)
		Harness.equal(planCount, 1)
		Harness.expect(roundStateForTeam(snapshot.battleState, "team.training").committed)
		Harness.expect(not roundStateForTeam(snapshot.battleState, snapshot.viewerTeamId).committed)
		Harness.equal(snapshot.battleState.phase, "PLANNING")
	end)

	Harness.test("capped draws keep planning unblocked at nine cards", function()
		local service = Fixtures.createTimedService({
			aiPlanner = {
				plan = function()
					return { ok = true, value = { requests = {}, remainingEnergy = 0 } }
				end,
			},
		})
		local snapshot = Fixtures.start(service, 619)
		for round = 1, 3 do
			local hand = viewerRoundState(snapshot).handCardInstanceIds
			Harness.expect(#hand <= 9)
			local committed = send(service, 619, snapshot, `cap.commit.{round}`, "COMMIT_PLAN", {})
			Harness.expect(committed.ok)
			snapshot = committed.value.snapshot
			Harness.expect(snapshot.pendingDiscardCount == nil)
			Harness.expect(snapshot.battleState.planningSubphase == nil)
		end
		Harness.equal(#viewerRoundState(snapshot).handCardInstanceIds, 9)
	end)

	Harness.test("battle finish clears its planning deadline and timer", function()
		local baseResolver = Fixtures.dependencies().resolver
		local service, timing = Fixtures.createTimedService({
			resolver = {
				resolveRound = function(state, dependencies)
					local result = baseResolver.resolveRound(state, dependencies)
					if result.ok then
						result.value.state.phase = "FINISHED"
						result.value.matchOutcome = {
							winnerTeamId = state.teams[1].id,
							isDraw = false,
						}
					end
					return result
				end,
			},
		})
		local snapshot = Fixtures.start(service, 607)
		local committed = send(service, 607, snapshot, "finish.commit", "COMMIT_PLAN", {})
		Harness.expect(committed.ok)
		Harness.equal(committed.value.snapshot.battleState.phase, "FINISHED")
		Harness.expect(committed.value.snapshot.battleState.planningDeadline == nil)
		Harness.expect(timing.scheduled[1].cancelled)
	end)

	Harness.test("restart and player removal cancel superseded timers", function()
		local service, timing = Fixtures.createTimedService()
		Fixtures.start(service, 608)
		local firstTimer = timing.scheduled[1]
		local restarted = service.restartBattle(608, "timer.restart")
		Harness.expect(restarted.ok)
		Harness.expect(firstTimer.cancelled)
		local secondTimer = timing.scheduled[#timing.scheduled]
		Harness.expect(not secondTimer.cancelled)
		service.removePlayer(608)
		Harness.expect(secondTimer.cancelled)
	end)

	Harness.test("end-to-end Training Grounds reaches valid outcome across rounds", function()
		local service = Fixtures.createService()
		local snapshot = Fixtures.start(service, 404)
		local outcome = nil
		local rounds = 0
		local sequence = 0
		while outcome == nil and rounds < 60 do
			rounds += 1
			local energy = viewerRoundState(snapshot).energy
			local spent = 0
			while spent < energy do
				local payload = chooseCard(snapshot, true)
				if payload == nil then
					break
				end
				local definition =
					snapshot.cardDefinitionsById[snapshot.cardInstancesById[payload.cardInstanceId].definitionId]
				if spent + definition.energyCost > energy then
					break
				end
				sequence += 1
				local queued =
					send(service, 404, snapshot, `e2e.queue.{sequence}`, "QUEUE_CARD", payload)
				Harness.expect(queued.ok)
				snapshot = queued.value.snapshot
				spent += definition.energyCost
			end
			sequence += 1
			local committed =
				send(service, 404, snapshot, `e2e.commit.{sequence}`, "COMMIT_PLAN", {})
			Harness.expect(committed.ok)
			Harness.expect(committed.value.resolution ~= nil)
			snapshot = committed.value.snapshot
			outcome = snapshot.matchOutcome
		end
		Harness.expect(outcome ~= nil)
		Harness.expect(outcome.isDraw or outcome.winnerTeamId ~= nil)
		Harness.equal(snapshot.battleState.phase, "FINISHED")
		Harness.expect(rounds > 1)
	end)

	Harness.test("Training Grounds AI defeats an idle team within bounded rounds", function()
		local service = Fixtures.createService()
		local snapshot = Fixtures.start(service, 505)
		local rounds = 0
		while snapshot.matchOutcome == nil and rounds < 30 do
			rounds += 1
			local committed =
				send(service, 505, snapshot, `idle.commit.{rounds}`, "COMMIT_PLAN", {})
			Harness.expect(committed.ok)
			snapshot = committed.value.snapshot
		end
		Harness.expect(snapshot.matchOutcome ~= nil)
		Harness.equal(snapshot.matchOutcome.winnerTeamId, "team.training")
		Harness.expect(rounds <= 30)
	end)
end
