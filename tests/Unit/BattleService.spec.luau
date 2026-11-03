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
		if definition.targetingRule == "SELF" then
			targetIds = { source.id }
		elseif definition.targetingRule == "ALLY" then
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
		elseif definition.targetingRule == "ENEMY" or definition.targetingRule == "ANY" then
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
			Harness.equal(committed.value.resolution.preSnapshot.battleState.phase, "COMMITTED")
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
		Harness.equal(snapshot.battleState.phase, "COMPLETED")
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
