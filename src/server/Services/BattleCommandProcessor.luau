--!strict

local BattleCommandProcessor = {}

local function clone(value)
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, child in value do
		result[clone(key)] = clone(child)
	end
	return result
end

local function deepEqual(a, b, visited)
	if type(a) ~= type(b) then
		return false
	end
	if type(a) ~= "table" then
		return a == b
	end
	if visited[a] == b then
		return true
	end
	visited[a] = b
	for key, value in a do
		if not deepEqual(value, b[key], visited) then
			return false
		end
	end
	for key in b do
		if a[key] == nil then
			return false
		end
	end
	return true
end

local function failure(code: string, message: string)
	return { ok = false, errors = { { code = code, message = message } } }
end

local function isNonEmptyString(value): boolean
	return type(value) == "string" and value ~= ""
end

local function isPositiveInteger(value): boolean
	return type(value) == "number" and value > 0 and value % 1 == 0
end

local function validatePayload(commandType: string, payload)
	if type(payload) ~= "table" then
		return failure("INVALID_PAYLOAD", "Command payload must be a table")
	end
	if
		payload.isCritical ~= nil
		or payload.criticalOutcome ~= nil
		or payload.criticalMultiplier ~= nil
	then
		return failure("INVALID_PAYLOAD", "Critical outcomes are server-authoritative")
	end
	if commandType == "QUEUE_CARD" then
		if not isNonEmptyString(payload.cardInstanceId) then
			return failure("INVALID_PAYLOAD", "Card instance ID is required")
		end
		if not isNonEmptyString(payload.sourceCombatantId) then
			return failure("INVALID_PAYLOAD", "Source combatant ID is required")
		end
		if payload.targetCombatantIds ~= nil and type(payload.targetCombatantIds) ~= "table" then
			return failure("INVALID_PAYLOAD", "Target combatant IDs must be a table")
		end
	elseif commandType == "REMOVE_QUEUED_CARD" then
		if not isNonEmptyString(payload.cardInstanceId) then
			return failure("INVALID_PAYLOAD", "Card instance ID is required")
		end
	elseif commandType == "REORDER_QUEUED_CARD" then
		if not isNonEmptyString(payload.cardInstanceId) then
			return failure("INVALID_PAYLOAD", "Card instance ID is required")
		end
		if not isPositiveInteger(payload.newIndex) then
			return failure("INVALID_PAYLOAD", "New queue index must be a positive integer")
		end
	end
	return nil
end

local function findTeam(state, teamId)
	for _, team in state.teams do
		if team.id == teamId then
			return team
		end
	end
	return nil
end

local function findTeamState(state, teamId)
	for _, teamState in state.teamRoundStates do
		if teamState.teamId == teamId then
			return teamState
		end
	end
	return nil
end

local function process(session, authenticatedUserId: number, envelope, context)
	local protocolVersion = session.protocolVersion or 2
	if type(envelope) ~= "table" or envelope.protocolVersion ~= protocolVersion then
		return failure("UNSUPPORTED_PROTOCOL", `Protocol version {protocolVersion} is required`)
	end
	if type(envelope.commandId) ~= "string" or envelope.commandId == "" then
		return failure("INVALID_COMMAND", "Command ID is required")
	end
	local previous = session.processedCommandsById[envelope.commandId]
	if previous ~= nil then
		if
			previous.authenticatedUserId == authenticatedUserId
			and deepEqual(previous.envelope, envelope, {})
		then
			return {
				ok = true,
				value = { session = session, receipt = previous.receipt, duplicate = true },
			}
		end
		return failure("COMMAND_ID_REUSED", "Command ID was used with different content")
	end

	local state = session.state
	if envelope.matchId ~= state.id then
		return failure("BATTLE_ID_MISMATCH", "Command targets another battle")
	end
	local team = findTeam(state, envelope.teamId)
	local teamState = findTeamState(state, envelope.teamId)
	if team == nil or teamState == nil then
		return failure("TEAM_NOT_FOUND", "Team is not part of battle")
	end
	if team.ownerUserId ~= authenticatedUserId then
		return failure("NOT_TEAM_OWNER", "Authenticated player does not own team")
	end
	if envelope.expectedStateVersion ~= state.stateVersion then
		return failure("STALE_STATE_VERSION", "Shared battle version is stale")
	end
	if envelope.expectedPlanVersion ~= teamState.planVersion then
		return failure("STALE_PLAN_VERSION", "Private plan version is stale")
	end

	local payload = envelope.payload
	if payload == nil then
		payload = {}
	end
	local payloadFailure = validatePayload(envelope.commandType, payload)
	if payloadFailure ~= nil then
		return payloadFailure
	end
	local result
	if envelope.commandType == "QUEUE_CARD" then
		result = context.battlePlan.queueCard(state, team.id, payload, context.cardDefinitionsById)
	elseif envelope.commandType == "REMOVE_QUEUED_CARD" then
		result = context.battlePlan.removeQueuedCard(
			state,
			team.id,
			payload.cardInstanceId,
			context.cardDefinitionsById
		)
	elseif envelope.commandType == "REORDER_QUEUED_CARD" then
		result = context.battlePlan.reorderQueuedCard(
			state,
			team.id,
			payload.cardInstanceId,
			payload.newIndex,
			context.cardDefinitionsById
		)
	elseif envelope.commandType == "CLEAR_PLAN" then
		result = context.battlePlan.clearPlan(state, team.id, context.cardDefinitionsById)
	elseif envelope.commandType == "COMMIT_PLAN" then
		result = context.battlePlan.commitPlan(state, team.id, context.cardDefinitionsById)
	else
		return failure("INVALID_COMMAND_KIND", "Unknown battle command type")
	end
	if not result.ok then
		return result
	end

	local nextState = result.value
	local nextTeamState = findTeamState(nextState, team.id)
	local receipt = {
		commandId = envelope.commandId,
		matchId = state.id,
		teamId = team.id,
		stateVersion = nextState.stateVersion,
		planVersion = nextTeamState.planVersion,
		phase = nextState.phase,
	}
	local nextSession = {
		state = nextState,
		processedCommandsById = clone(session.processedCommandsById),
	}
	nextSession.processedCommandsById[envelope.commandId] = {
		authenticatedUserId = authenticatedUserId,
		envelope = clone(envelope),
		receipt = clone(receipt),
	}
	return { ok = true, value = { session = nextSession, receipt = receipt, duplicate = false } }
end

BattleCommandProcessor.process = process
return table.freeze(BattleCommandProcessor)
