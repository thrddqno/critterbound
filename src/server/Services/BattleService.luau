--!strict

local BattleService = {}

local function clone<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, child in value :: any do
		result[clone(key)] = clone(child)
	end
	return result :: any
end

local function failure(code: string, message: string)
	return { ok = false, errors = { { code = code, message = message } } }
end

local function indexInstances(input)
	local result = {}
	for _, team in input.teams do
		for _, instance in team.critterInstances do
			result[instance.id] = instance
		end
	end
	return result
end

local function findTeamState(state, teamId: string)
	for _, teamState in state.teamRoundStates do
		if teamState.teamId == teamId then
			return teamState
		end
	end
	return nil
end

local function commandEnvelope(session, teamId: string, id: string, commandType: string, payload)
	local teamState = findTeamState(session.state, teamId)
	return {
		protocolVersion = session.protocolVersion,
		matchId = session.state.id,
		teamId = teamId,
		commandId = id,
		expectedStateVersion = session.state.stateVersion,
		expectedPlanVersion = teamState.planVersion,
		commandType = commandType,
		payload = payload,
	}
end

local function extractInitiative(events)
	for _, event in events do
		if event.kind == "INITIATIVE_DETERMINED" then
			return clone(event.payload.initiativeCombatantIds or {})
		end
	end
	return {}
end

local function new(dependencies)
	local deps = dependencies
	local sessions = {}
	local generations = {}
	local lifecycleReceipts = {}
	local service = {}
	local planningSeconds = deps.planningSeconds or 45
	local beginPlanning
	local handleDeadline

	local function currentTime(): number
		if deps.now ~= nil then
			return math.floor(deps.now())
		end
		return os.time()
	end

	local function planningTime(): number
		if deps.planningNow ~= nil then
			return deps.planningNow()
		end
		return currentTime()
	end

	local function cancelPlanningTimer(session)
		session.timerGeneration = (session.timerGeneration or 0) + 1
		local handle = session.timerHandle
		session.timerHandle = nil
		session.planningDeadline = nil
		if handle ~= nil and deps.cancelScheduled ~= nil then
			deps.cancelScheduled(handle)
		end
	end

	local function completionEvidence(session, userId: number)
		return {
			context = { kind = "SERVER", source = "BATTLE_SERVICE" },
			userId = userId,
			mode = "TRAINING",
			battleId = session.state.id,
			playerTeamId = session.playerTeamId,
			outcome = clone(session.matchOutcome),
			startedAt = session.startedAt,
			completedAt = session.completedAt,
		}
	end

	local function deliverCompletion(session, userId: number)
		if session.completionDelivered then
			return true, nil
		end
		if session.matchOutcome == nil then
			return true, nil
		end
		if deps.onBattleCompleted == nil then
			session.completionDelivered = true
			session.pendingCompletion = nil
			return true, nil
		end
		if session.pendingCompletion == nil then
			session.pendingCompletion = completionEvidence(session, userId)
		end
		local ok, result = pcall(deps.onBattleCompleted, clone(session.pendingCompletion))
		if not ok then
			return false, "CONTRACT_COMPLETION_ERROR"
		end
		if type(result) ~= "table" or result.ok ~= true then
			return false,
				if type(result) == "table"
						and result.errors
						and result.errors[1]
					then result.errors[1].code
					else "CONTRACT_COMPLETION_ERROR"
		end
		session.completionDelivered = true
		session.pendingCompletion = nil
		return true, nil
	end

	local function flushPendingCompletion(userId: number)
		local session = sessions[userId]
		if session == nil or session.pendingCompletion == nil then
			return true, nil
		end
		return deliverCompletion(session, userId)
	end

	local function completionPendingFailure(code: string?)
		return failure(
			"COMPLETION_PENDING",
			`Battle victory is not durable yet ({code or "PENDING"})`
		)
	end

	local function projectionContext(session)
		return {
			cardDefinitionsById = session.context.cardDefinitionsById,
			critterDefinitionsById = session.context.critterDefinitionsById,
			critterInstancesById = session.context.critterInstancesById,
			initiativeCombatantIds = session.latestInitiativeCombatantIds,
			matchOutcome = session.matchOutcome,
			statusEffects = deps.statusEffects,
			planningDeadline = session.planningDeadline,
			bloodMoonConfig = deps.bloodMoonConfig,
		}
	end

	local function project(session, userId: number, state)
		return deps.projector.project(state or session.state, userId, projectionContext(session))
	end

	local function createSession(userId: number)
		local generation = (generations[userId] or 0) + 1
		local inputFactory = deps.inputFactory or deps.content
		local produced = inputFactory.createInput(userId, generation)
		if type(produced) == "table" and produced.ok ~= nil then
			if not produced.ok then
				return produced
			end
			produced = produced.value
		end
		local input = produced
		local criticalRngSeed = deps.criticalRngSeed(userId, generation)
		local created = deps.factory.create(input, {
			rng = deps.rng,
			criticalRngSeed = criticalRngSeed,
			deck = deps.deck,
			validator = deps.validator,
			deckRules = deps.deckRules,
			deckBuilder = deps.deckBuilder,
			deckShuffler = deps.deckShuffler,
		})
		if not created.ok then
			return created
		end
		generations[userId] = generation
		local session = {
			state = created.value,
			processedCommandsById = {},
			context = {
				cardDefinitionsById = input.cardDefinitionsById,
				critterDefinitionsById = input.critterDefinitionsById,
				critterInstancesById = indexInstances(input),
			},
			playerTeamId = input.playerTeamId,
			aiTeamId = input.aiTeamId,
			aiOwnerUserId = input.aiOwnerUserId,
			protocolVersion = deps.protocolVersion,
			generation = generation,
			startedAt = currentTime(),
			completedAt = nil,
			completionDelivered = false,
			pendingCompletion = nil,
			latestInitiativeCombatantIds = {},
			matchOutcome = nil,
			resolving = false,
			connected = true,
			planningDeadline = nil,
			timerHandle = nil,
			timerGeneration = 0,
		}
		sessions[userId] = session
		local initialized = beginPlanning(session, userId)
		if not initialized.ok then
			cancelPlanningTimer(session)
			sessions[userId] = nil
			return initialized
		end
		return { ok = true, value = session }
	end

	local function startBattle(userId: number)
		local flushed, flushCode = flushPendingCompletion(userId)
		if not flushed then
			return completionPendingFailure(flushCode)
		end
		local session = sessions[userId]
		if session == nil then
			local created = createSession(userId)
			if not created.ok then
				return created
			end
			session = created.value
		end
		session.connected = true
		if
			session.state.phase == "PLANNING"
			and session.planningDeadline ~= nil
			and planningTime() >= session.planningDeadline
		then
			local expired = handleDeadline(session, userId)
			if not expired.ok then
				return expired
			end
		end
		local projected = project(session, userId)
		if not projected.ok then
			return projected
		end
		return { ok = true, value = { snapshot = projected.value, started = true } }
	end

	local function restartBattle(userId: number, requestId: string)
		if type(requestId) ~= "string" or requestId == "" then
			return failure("INVALID_REQUEST_ID", "Restart request ID is required")
		end
		local flushed, flushCode = flushPendingCompletion(userId)
		if not flushed then
			return completionPendingFailure(flushCode)
		end
		local receipts = lifecycleReceipts[userId] or {}
		lifecycleReceipts[userId] = receipts
		if receipts[requestId] ~= nil then
			return clone(receipts[requestId])
		end
		local existing = sessions[userId]
		if existing ~= nil then
			cancelPlanningTimer(existing)
		end
		local created = createSession(userId)
		if not created.ok then
			return created
		end
		local projected = project(created.value, userId)
		if not projected.ok then
			return projected
		end
		local response = { ok = true, value = { snapshot = projected.value, restarted = true } }
		receipts[requestId] = clone(response)
		return response
	end

	local function requestSnapshot(userId: number)
		local flushed, flushCode = flushPendingCompletion(userId)
		if not flushed then
			return completionPendingFailure(flushCode)
		end
		local session = sessions[userId]
		if session == nil then
			return failure("NO_ACTIVE_BATTLE", "Player has no active battle")
		end
		if
			session.state.phase == "PLANNING"
			and session.planningDeadline ~= nil
			and planningTime() >= session.planningDeadline
		then
			local expired = handleDeadline(session, userId)
			if not expired.ok then
				return expired
			end
		end
		local projected = project(session, userId)
		if not projected.ok then
			return projected
		end
		return { ok = true, value = { snapshot = projected.value } }
	end

	local function processInternalCommand(
		session,
		teamId: string,
		ownerUserId: number,
		commandType: string,
		payload,
		suffix: string
	)
		local envelope = commandEnvelope(
			session,
			teamId,
			`server:{session.state.id}:r{session.state.roundNumber}:{suffix}`,
			commandType,
			payload
		)
		local result = deps.commandProcessor.process(session, ownerUserId, envelope, {
			battlePlan = deps.battlePlan,
			cardDefinitionsById = session.context.cardDefinitionsById,
		})
		if result.ok then
			local nextSession = result.value.session
			session.state = nextSession.state
			session.processedCommandsById = nextSession.processedCommandsById
		end
		return result
	end

	local function processAiCommand(session, commandType: string, payload, suffix: string)
		return processInternalCommand(
			session,
			session.aiTeamId,
			session.aiOwnerUserId,
			commandType,
			payload,
			`ai:{suffix}`
		)
	end

	local function planAndCommitAi(session)
		local planned = deps.aiPlanner.plan(
			session.state,
			session.aiTeamId,
			session.context.cardDefinitionsById
		)
		if not planned.ok then
			return planned
		end
		for index, request in planned.value.requests do
			local queued = processAiCommand(session, "QUEUE_CARD", request, `queue:{index}`)
			if not queued.ok then
				return queued
			end
		end
		return processAiCommand(session, "COMMIT_PLAN", {}, "commit")
	end

	local function resolveCommitted(session, userId: number)
		if session.resolving then
			return failure("RESOLUTION_IN_PROGRESS", "Battle resolution is already running")
		end
		session.resolving = true
		cancelPlanningTimer(session)
		local preProjection = project(session, userId)
		if not preProjection.ok then
			session.resolving = false
			return preProjection
		end
		local shuffle = deps.rng.shuffle
		if deps.deckShuffler ~= nil then
			shuffle = function(rng, values)
				return deps.deckShuffler.shuffle(rng, values, deps.rng)
			end
		end
		local resolved = deps.resolver.resolveRound(session.state, {
			cardDefinitionsById = session.context.cardDefinitionsById,
			deck = deps.deck,
			economy = deps.economy,
			shuffle = shuffle,
			drawPerRound = if deps.deckRules ~= nil
				then deps.deckRules.DrawsPerRound
				else deps.drawPerRound,
			maxHandSize = if deps.deckRules ~= nil then deps.deckRules.MaxHandSize else nil,
			defeatPolicy = if deps.deckRules ~= nil then deps.deckRules.DefeatPolicy else nil,
			criticalRng = deps.criticalRng or deps.rng,
			bloodMoonConfig = deps.bloodMoonConfig,
		})
		if not resolved.ok then
			session.resolving = false
			return resolved
		end
		session.state = resolved.value.state
		session.latestInitiativeCombatantIds = extractInitiative(resolved.value.events)
		session.matchOutcome = resolved.value.matchOutcome
		if session.matchOutcome ~= nil and session.completedAt == nil then
			session.completedAt = currentTime()
			local delivered, deliveryCode = deliverCompletion(session, userId)
			if not delivered then
				session.resolving = false
				return completionPendingFailure(deliveryCode)
			end
		end
		if session.state.phase == "PLANNING" then
			local initialized = beginPlanning(session, userId)
			if not initialized.ok then
				session.resolving = false
				return initialized
			end
		else
			cancelPlanningTimer(session)
		end
		session.resolving = false
		local finalProjection = project(session, userId)
		if not finalProjection.ok then
			return finalProjection
		end
		return {
			ok = true,
			value = {
				id = `resolution:{session.state.id}:{session.state.lastResolvedRound}`,
				preSnapshot = preProjection.value,
				events = clone(resolved.value.events),
				finalSnapshot = finalProjection.value,
				matchOutcome = clone(resolved.value.matchOutcome),
			},
		}
	end

	local function commitUncommittedTeams(session)
		for _, team in session.state.teams do
			local teamState = findTeamState(session.state, team.id)
			if teamState ~= nil and not teamState.committed then
				local committed = processInternalCommand(
					session,
					team.id,
					team.ownerUserId,
					"COMMIT_PLAN",
					{},
					`timeout:{team.id}`
				)
				if not committed.ok then
					return committed
				end
			end
		end
		return { ok = true, value = true }
	end

	handleDeadline = function(session, userId: number)
		if sessions[userId] ~= session or session.state.phase ~= "PLANNING" then
			return { ok = true, value = false }
		end
		if session.planningDeadline == nil or planningTime() < session.planningDeadline then
			return { ok = true, value = false }
		end
		session.timerHandle = nil
		local aiState = findTeamState(session.state, session.aiTeamId)
		if aiState ~= nil and not aiState.committed then
			local planned = planAndCommitAi(session)
			if not planned.ok then
				return planned
			end
		end
		local committed = commitUncommittedTeams(session)
		if not committed.ok then
			return committed
		end
		if session.state.phase ~= "RESOLVING" then
			return failure("INVALID_PHASE", "Timeout did not complete all plans")
		end
		return resolveCommitted(session, userId)
	end

	beginPlanning = function(session, userId: number)
		if session.state.phase ~= "PLANNING" then
			return failure("INVALID_PHASE", "Battle is not planning")
		end
		cancelPlanningTimer(session)
		session.planningDeadline = planningTime() + planningSeconds
		local token = session.timerGeneration
		if deps.schedule ~= nil then
			session.timerHandle = deps.schedule(planningSeconds, function()
				if session.timerGeneration == token then
					handleDeadline(session, userId)
				end
			end)
		end
		local aiState = findTeamState(session.state, session.aiTeamId)
		if aiState ~= nil and not aiState.committed then
			return planAndCommitAi(session)
		end
		return { ok = true, value = true }
	end

	local function processCommand(userId: number, envelope)
		local flushed, flushCode = flushPendingCompletion(userId)
		if not flushed then
			return completionPendingFailure(flushCode)
		end
		local session = sessions[userId]
		if session == nil then
			return failure("NO_ACTIVE_BATTLE", "Player has no active battle")
		end
		if session.resolving then
			return failure("RESOLUTION_IN_PROGRESS", "Battle resolution is already running")
		end
		local duplicate = type(envelope) == "table"
			and type(envelope.commandId) == "string"
			and session.processedCommandsById[envelope.commandId] ~= nil
		if
			not duplicate
			and session.state.phase == "PLANNING"
			and session.planningDeadline ~= nil
			and planningTime() >= session.planningDeadline
		then
			handleDeadline(session, userId)
			return failure("PLANNING_DEADLINE_EXPIRED", "Planning deadline has passed")
		end
		local result = deps.commandProcessor.process(session, userId, envelope, {
			battlePlan = deps.battlePlan,
			cardDefinitionsById = session.context.cardDefinitionsById,
		})
		if not result.ok then
			return result
		end
		local nextSession = result.value.session
		session.state = nextSession.state
		session.processedCommandsById = nextSession.processedCommandsById

		local resolution = nil
		if session.state.phase == "RESOLVING" then
			local resolved = resolveCommitted(session, userId)
			if not resolved.ok then
				return resolved
			end
			resolution = resolved.value
		end

		local projected = project(session, userId)
		if not projected.ok then
			return projected
		end
		return {
			ok = true,
			value = {
				receipt = clone(result.value.receipt),
				duplicate = result.value.duplicate,
				snapshot = projected.value,
				resolution = resolution,
			},
		}
	end

	local function handleRequest(userId: number, request)
		if type(request) ~= "table" then
			return failure("INVALID_REQUEST", "Battle request must be a table")
		end
		if request.kind == "START_BATTLE" then
			return startBattle(userId)
		elseif request.kind == "REQUEST_SNAPSHOT" then
			return requestSnapshot(userId)
		elseif request.kind == "RESTART_BATTLE" then
			return restartBattle(userId, request.requestId)
		elseif request.kind == "COMMAND" then
			return processCommand(userId, request.envelope)
		end
		return failure("INVALID_REQUEST_KIND", "Unknown battle request kind")
	end

	function service.removePlayer(userId: number)
		flushPendingCompletion(userId)
		local session = sessions[userId]
		if session ~= nil then
			cancelPlanningTimer(session)
		end
		sessions[userId] = nil
		lifecycleReceipts[userId] = nil
	end

	function service.playerDisconnected(userId: number)
		local session = sessions[userId]
		if session ~= nil then
			session.connected = false
		end
	end

	function service.invalidateBattle(userId: number)
		local session = sessions[userId]
		if session ~= nil then
			cancelPlanningTimer(session)
		end
		sessions[userId] = nil
	end

	function service.getActiveBattleId(userId: number): string?
		local session = sessions[userId]
		if session == nil then
			return nil
		end
		return session.state.id
	end

	function service.hasPendingCompletion(userId: number): boolean
		local session = sessions[userId]
		return session ~= nil and session.pendingCompletion ~= nil
	end

	service.startBattle = startBattle
	service.restartBattle = restartBattle
	service.requestSnapshot = requestSnapshot
	service.processCommand = processCommand
	service.handleRequest = handleRequest
	return table.freeze(service)
end

BattleService.new = new
return table.freeze(BattleService)
