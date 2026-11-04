--!strict

local BattleProjector = {}

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

local function failure(code: string, message: string)
	return { ok = false, errors = { { code = code, message = message } } }
end

local function project(state, authenticatedUserId: number, context)
	local viewerTeam = nil
	for _, team in state.teams do
		if team.ownerUserId == authenticatedUserId then
			viewerTeam = team
			break
		end
	end
	if viewerTeam == nil then
		return failure("VIEWER_NOT_IN_BATTLE", "Authenticated player is not in battle")
	end

	local cardInstancesById = {}
	for _, card in state.cardInstances do
		cardInstancesById[card.id] = card
	end
	local visibleCardInstances = {}
	local visibleCardDefinitions = {}
	local visibleQueuedCards = {}
	local projectedRoundStates = {}
	local shieldsByCombatantId = {}
	local effectiveSpeedByCombatantId = {}
	local viewerPlanVersion = 0
	local revealPlans = state.phase ~= "PLANNING"
	for _, combatant in state.combatants do
		local shieldTotal = 0
		for _, shield in combatant.shields or {} do
			shieldTotal += shield.amount or 0
		end
		shieldsByCombatantId[combatant.id] = shieldTotal
		effectiveSpeedByCombatantId[combatant.id] = if context.statusEffects ~= nil
			then context.statusEffects.effectiveSpeed(combatant)
			else combatant.stats.speed
	end

	for _, teamState in state.teamRoundStates do
		local own = teamState.teamId == viewerTeam.id
		local handIds = if own then clone(teamState.handCardInstanceIds) else {}
		local queue = if own or revealPlans then teamState.queuedCards or {} else {}
		if own then
			viewerPlanVersion = teamState.planVersion
		end
		for _, cardId in handIds do
			local card = cardInstancesById[cardId]
			if card ~= nil then
				visibleCardInstances[cardId] = clone(card)
				local definition = context.cardDefinitionsById[card.definitionId]
				if definition ~= nil then
					visibleCardDefinitions[definition.id] = clone(definition)
				end
			end
		end
		for _, queued in queue do
			local card = cardInstancesById[queued.cardInstanceId]
			if card ~= nil then
				visibleCardInstances[card.id] = clone(card)
				local definition = context.cardDefinitionsById[card.definitionId]
				if definition ~= nil then
					visibleCardDefinitions[definition.id] = clone(definition)
				end
				table.insert(visibleQueuedCards, clone(queued))
			end
		end
		table.insert(projectedRoundStates, {
			teamId = teamState.teamId,
			energy = if own then teamState.energy else nil,
			reservedEnergy = if own then teamState.reservedEnergy else nil,
			handCardInstanceIds = handIds,
			handCount = #teamState.handCardInstanceIds,
			drawPileCount = #(teamState.drawPileCardInstanceIds or {}),
			discardCount = #(teamState.discardCardInstanceIds or {}),
			removedCount = #(teamState.removedCardInstanceIds or {}),
			committed = teamState.committed,
		})
	end

	return {
		ok = true,
		value = {
			revision = state.stateVersion,
			planVersion = viewerPlanVersion,
			viewerTeamId = viewerTeam.id,
			battleState = {
				schemaVersion = state.schemaVersion,
				id = state.id,
				phase = state.phase,
				roundNumber = state.roundNumber,
				planningDeadline = context.planningDeadline,
				bloodMoon = clone(context.bloodMoonConfig),
				teams = clone(state.teams),
				combatants = clone(state.combatants),
				teamRoundStates = projectedRoundStates,
			},
			critterInstancesById = clone(context.critterInstancesById),
			critterDefinitionsById = clone(context.critterDefinitionsById),
			cardInstancesById = visibleCardInstances,
			cardDefinitionsById = visibleCardDefinitions,
			shieldsByCombatantId = shieldsByCombatantId,
			effectiveSpeedByCombatantId = effectiveSpeedByCombatantId,
			initiativeCombatantIds = clone(context.initiativeCombatantIds or {}),
			visibleQueuedCards = visibleQueuedCards,
			matchOutcome = clone(context.matchOutcome),
		},
	}
end

BattleProjector.project = project
return table.freeze(BattleProjector)
