--!strict

local BattlePlan = {}

-- Targeting rules whose targets are derived by the server at resolution time.
local DERIVED_TARGETING_RULES = {
	FRONT_ENEMY = true,
	ALL_ALLIES = true,
	ALL_ENEMIES = true,
}

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

local function failure(code: string, message: string, path: string?)
	return { ok = false, errors = { { code = code, message = message, path = path } } }
end

local function indexById(values)
	local result = {}
	for _, value in values or {} do
		result[value.id] = value
	end
	return result
end

local function findTeamState(state, teamId)
	for _, teamState in state.teamRoundStates do
		if teamState.teamId == teamId then
			return teamState
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

local function validatePlan(state, teamId: string, cardDefinitionsById)
	if state.phase ~= "PLANNING" then
		return failure("INVALID_PHASE", "Planning is not active", "phase")
	end
	local team = findTeam(state, teamId)
	local teamState = findTeamState(state, teamId)
	if team == nil or teamState == nil then
		return failure("TEAM_NOT_FOUND", "Team is not part of battle", "teamId")
	end
	if teamState.committed then
		return failure("PLAN_LOCKED", "Committed plan cannot change", "committed")
	end
	local queue = teamState.queuedCards or {}
	if #queue > 10 then
		return failure("INVALID_QUEUE_LENGTH", "Plan cannot exceed ten cards", "queuedCards")
	end

	local hand = {}
	for _, cardId in teamState.handCardInstanceIds do
		hand[cardId] = true
	end
	local teamCombatants = {}
	for _, combatantId in team.combatantIds do
		teamCombatants[combatantId] = true
	end
	local combatants = indexById(state.combatants)
	local cards = indexById(state.cardInstances)
	local seenCards = {}
	local indicesBySource = {}
	local spent = 0

	for index, queued in queue do
		if seenCards[queued.cardInstanceId] then
			return failure("CARD_ALREADY_QUEUED", "Card is already queued", `queuedCards[{index}]`)
		end
		seenCards[queued.cardInstanceId] = true
		if not hand[queued.cardInstanceId] then
			return failure("CARD_NOT_IN_HAND", "Card is not in team hand", `queuedCards[{index}]`)
		end
		local card = cards[queued.cardInstanceId]
		if card == nil then
			return failure(
				"UNKNOWN_CARD_INSTANCE",
				"Card instance does not exist",
				`queuedCards[{index}]`
			)
		end
		local source = combatants[queued.sourceCombatantId]
		if source == nil or not teamCombatants[queued.sourceCombatantId] then
			return failure(
				"INVALID_CARD_SOURCE",
				"Source Critter does not belong to team",
				`queuedCards[{index}]`
			)
		end
		if source.currentHealth <= 0 then
			return failure(
				"INELIGIBLE_CARD_SOURCE",
				"Defeated Critter cannot queue cards",
				`queuedCards[{index}]`
			)
		end
		if card.sourceCritterInstanceId ~= source.critterInstanceId then
			return failure(
				"INVALID_CARD_SOURCE",
				"Card belongs to another Critter",
				`queuedCards[{index}]`
			)
		end
		local definition = cardDefinitionsById[card.definitionId]
		if definition == nil then
			return failure(
				"MISSING_CARD_DEFINITION",
				"Card definition does not exist",
				`queuedCards[{index}]`
			)
		end
		spent += definition.energyCost

		local rule = definition.targetingRule
		if DERIVED_TARGETING_RULES[rule] then
			if type(queued.targetCombatantIds) ~= "table" or #queued.targetCombatantIds ~= 0 then
				return failure(
					"INVALID_TARGET_COUNT",
					"Derived targeting rules require an empty target list",
					`queuedCards[{index}].targetCombatantIds`
				)
			end
		else
			if type(queued.targetCombatantIds) ~= "table" or #queued.targetCombatantIds ~= 1 then
				return failure(
					"INVALID_TARGET_COUNT",
					"Card requires one target",
					`queuedCards[{index}].targetCombatantIds`
				)
			end
			local targetId = queued.targetCombatantIds[1]
			local target = combatants[targetId]
			if target == nil then
				return failure(
					"INVALID_TARGET",
					"Target does not exist",
					`queuedCards[{index}].targetCombatantIds[1]`
				)
			end
			local legal = rule == "ANY"
				or (rule == "SELF" and targetId == source.id)
				or (rule == "ALLY" and target.teamId == source.teamId and targetId ~= source.id)
				or (rule == "ENEMY" and target.teamId ~= source.teamId)
			if not legal then
				return failure(
					"INVALID_TARGET",
					"Target violates targeting rule",
					`queuedCards[{index}].targetCombatantIds[1]`
				)
			end
		end

		local indices = indicesBySource[source.id] or {}
		table.insert(indices, queued.queueIndex)
		indicesBySource[source.id] = indices
	end

	for sourceId, indices in indicesBySource do
		table.sort(indices)
		for expected, actual in indices do
			if actual ~= expected then
				return failure(
					"INVALID_QUEUE_ORDER",
					"Per-Critter queue indices must be contiguous",
					sourceId
				)
			end
		end
	end
	if spent > teamState.energy then
		return failure("INSUFFICIENT_ENERGY", "Plan exceeds team energy", "queuedCards")
	end
	return { ok = true, value = { energyCost = spent } }
end

local function mutateQueue(state, teamId, nextQueue, cardDefinitionsById)
	local nextState = clone(state)
	local teamState = findTeamState(nextState, teamId)
	teamState.queuedCards = nextQueue
	local validation = validatePlan(nextState, teamId, cardDefinitionsById)
	if not validation.ok then
		return validation
	end
	teamState.reservedEnergy = validation.value.energyCost
	teamState.planVersion = (teamState.planVersion or 0) + 1
	return { ok = true, value = nextState }
end

local function queueCard(state, teamId: string, request, cardDefinitionsById)
	local teamState = findTeamState(state, teamId)
	if teamState == nil then
		return failure("TEAM_NOT_FOUND", "Team is not part of battle", "teamId")
	end
	local queue = clone(teamState.queuedCards or {})
	for _, queued in queue do
		if queued.cardInstanceId == request.cardInstanceId then
			return failure("CARD_ALREADY_QUEUED", "Card is already queued", "cardInstanceId")
		end
	end
	local sourceCount = 0
	for _, queued in queue do
		if queued.sourceCombatantId == request.sourceCombatantId then
			sourceCount += 1
		end
	end
	table.insert(queue, {
		cardInstanceId = request.cardInstanceId,
		sourceCombatantId = request.sourceCombatantId,
		targetCombatantIds = clone(request.targetCombatantIds or {}),
		queueIndex = sourceCount + 1,
	})
	return mutateQueue(state, teamId, queue, cardDefinitionsById)
end

local function removeQueuedCard(state, teamId: string, cardInstanceId: string, cardDefinitionsById)
	local teamState = findTeamState(state, teamId)
	if teamState == nil then
		return failure("TEAM_NOT_FOUND", "Team is not part of battle", "teamId")
	end
	local queue = {}
	local removedSource = nil
	for _, queued in teamState.queuedCards or {} do
		if queued.cardInstanceId == cardInstanceId then
			removedSource = queued.sourceCombatantId
		else
			table.insert(queue, clone(queued))
		end
	end
	if removedSource == nil then
		return failure("CARD_NOT_QUEUED", "Card is not queued", "cardInstanceId")
	end
	local sourceIndex = 0
	for _, queued in queue do
		if queued.sourceCombatantId == removedSource then
			sourceIndex += 1
			queued.queueIndex = sourceIndex
		end
	end
	return mutateQueue(state, teamId, queue, cardDefinitionsById)
end

local function reorderQueuedCard(
	state,
	teamId: string,
	cardInstanceId: string,
	newIndex: number,
	cardDefinitionsById
)
	if type(newIndex) ~= "number" or newIndex % 1 ~= 0 or newIndex < 1 then
		return failure("INVALID_QUEUE_INDEX", "Queue index must be positive", "newIndex")
	end
	local teamState = findTeamState(state, teamId)
	if teamState == nil then
		return failure("TEAM_NOT_FOUND", "Team is not part of battle", "teamId")
	end
	local queue = clone(teamState.queuedCards or {})
	local moving = nil
	local sourceEntries = {}
	for _, queued in queue do
		if queued.cardInstanceId == cardInstanceId then
			moving = queued
		end
	end
	if moving == nil then
		return failure("CARD_NOT_QUEUED", "Card is not queued", "cardInstanceId")
	end
	for _, queued in queue do
		if queued.sourceCombatantId == moving.sourceCombatantId then
			table.insert(sourceEntries, queued)
		end
	end
	if newIndex > #sourceEntries then
		return failure("INVALID_QUEUE_INDEX", "Queue index exceeds source queue", "newIndex")
	end
	table.sort(sourceEntries, function(a, b)
		return a.queueIndex < b.queueIndex
	end)
	local oldIndex = moving.queueIndex
	table.remove(sourceEntries, oldIndex)
	table.insert(sourceEntries, newIndex, moving)
	for index, queued in sourceEntries do
		queued.queueIndex = index
	end
	return mutateQueue(state, teamId, queue, cardDefinitionsById)
end

local function clearPlan(state, teamId: string, cardDefinitionsById)
	local teamState = findTeamState(state, teamId)
	if teamState == nil then
		return failure("TEAM_NOT_FOUND", "Team is not part of battle", "teamId")
	end
	if #(teamState.queuedCards or {}) == 0 then
		local validation = validatePlan(state, teamId, cardDefinitionsById)
		if not validation.ok then
			return validation
		end
		return { ok = true, value = state }
	end
	return mutateQueue(state, teamId, {}, cardDefinitionsById)
end

local function commitPlan(state, teamId: string, cardDefinitionsById)
	local validation = validatePlan(state, teamId, cardDefinitionsById)
	if not validation.ok then
		return validation
	end
	local nextState = clone(state)
	local teamState = findTeamState(nextState, teamId)
	teamState.energy -= validation.value.energyCost
	teamState.reservedEnergy = 0
	teamState.committed = true
	teamState.planVersion = (teamState.planVersion or 0) + 1
	local bothCommitted = true
	for _, candidate in nextState.teamRoundStates do
		bothCommitted = bothCommitted and candidate.committed
	end
	if bothCommitted then
		nextState.phase = "COMMITTED"
		nextState.stateVersion = (nextState.stateVersion or 0) + 1
	end
	return { ok = true, value = nextState }
end

BattlePlan.validatePlan = validatePlan
BattlePlan.queueCard = queueCard
BattlePlan.removeQueuedCard = removeQueuedCard
BattlePlan.reorderQueuedCard = reorderQueuedCard
BattlePlan.clearPlan = clearPlan
BattlePlan.commitPlan = commitPlan
return table.freeze(BattlePlan)
