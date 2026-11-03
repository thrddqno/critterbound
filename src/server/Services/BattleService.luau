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

local function commandEnvelope(session, id: string, commandType: string, payload)
	local teamState = findTeamState(session.state, session.aiTeamId)
	return {
		protocolVersion = session.protocolVersion,
		matchId = session.state.id,
		teamId = session.aiTeamId,
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

	local function projectionContext(session)
		return {
			cardDefinitionsById = session.context.cardDefinitionsById,
			critterDefinitionsById = session.context.critterDefinitionsById,
			critterInstancesById = session.context.critterInstancesById,
			initiativeCombatantIds = session.latestInitiativeCombatantIds,
			matchOutcome = session.matchOutcome,
			statusEffects = deps.statusEffects,
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
		local created = deps.factory.create(input, {
			rng = deps.rng,
			deck = deps.deck,
			validator = deps.validator,
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
			latestInitiativeCombatantIds = {},
			matchOutcome = nil,
			resolving = false,
		}
		sessions[userId] = session
		return { ok = true, value = session }
	end

	local function startBattle(userId: number)
		local session = sessions[userId]
		if session == nil then
			local created = createSession(userId)
			if not created.ok then
				return created
			end
			session = created.value
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
		local receipts = lifecycleReceipts[userId] or {}
		lifecycleReceipts[userId] = receipts
		if receipts[requestId] ~= nil then
			return clone(receipts[requestId])
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
		local session = sessions[userId]
		if session == nil then
			return failure("NO_ACTIVE_BATTLE", "Player has no active battle")
		end
		local projected = project(session, userId)
		if not projected.ok then
			return projected
		end
		return { ok = true, value = { snapshot = projected.value } }
	end

	local function processAiCommand(session, commandType: string, payload, suffix: string)
		local envelope = commandEnvelope(
			session,
			`ai:{session.state.id}:r{session.state.roundNumber}:{suffix}`,
			commandType,
			payload
		)
		local result = deps.commandProcessor.process(session, session.aiOwnerUserId, envelope, {
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
		local preProjection = project(session, userId)
		if not preProjection.ok then
			session.resolving = false
			return preProjection
		end
		local resolved = deps.resolver.resolveRound(session.state, {
			cardDefinitionsById = session.context.cardDefinitionsById,
			deck = deps.deck,
			economy = deps.economy,
			shuffle = deps.rng.shuffle,
			drawPerRound = deps.drawPerRound,
		})
		session.resolving = false
		if not resolved.ok then
			return resolved
		end
		session.state = resolved.value.state
		session.latestInitiativeCombatantIds = extractInitiative(resolved.value.events)
		session.matchOutcome = resolved.value.matchOutcome
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

	local function processCommand(userId: number, envelope)
		local session = sessions[userId]
		if session == nil then
			return failure("NO_ACTIVE_BATTLE", "Player has no active battle")
		end
		if session.resolving then
			return failure("RESOLUTION_IN_PROGRESS", "Battle resolution is already running")
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
		local playerState = findTeamState(session.state, session.playerTeamId)
		if
			envelope.commandType == "COMMIT_PLAN"
			and not result.value.duplicate
			and playerState ~= nil
			and playerState.committed
			and session.state.phase == "PLANNING"
		then
			local aiResult = planAndCommitAi(session)
			if not aiResult.ok then
				return aiResult
			end
		end
		if session.state.phase == "COMMITTED" then
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
		sessions[userId] = nil
		lifecycleReceipts[userId] = nil
	end

	function service.invalidateBattle(userId: number)
		sessions[userId] = nil
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
