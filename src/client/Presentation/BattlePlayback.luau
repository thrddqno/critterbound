--!strict

local BattlePlayback = {}

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

local function findCombatant(snapshot, combatantId: string)
	for _, combatant in snapshot.battleState.combatants do
		if combatant.id == combatantId then
			return combatant
		end
	end
	return nil
end

local function cardName(snapshot, payload): string
	local definitionId = payload.cardDefinitionId
	if definitionId == nil and payload.cardInstanceId ~= nil then
		local instance = (snapshot.cardInstancesById or {})[payload.cardInstanceId]
		definitionId = instance and instance.definitionId
	end
	local definition = definitionId and (snapshot.cardDefinitionsById or {})[definitionId]
	return if definition ~= nil then definition.displayName else definitionId or "Unknown card"
end

local function appendLog(state, event, text: string)
	local entries = state.logEntries
	table.insert(entries, {
		id = event.id or `local:{#entries + 1}`,
		sequence = event.sequence or #entries + 1,
		text = text,
		kind = event.kind,
	})
	if #entries > 24 then
		table.remove(entries, 1)
	end
end

local function setFeedback(state, combatantId: string?, kind: string, text: string)
	if combatantId == nil then
		return
	end
	state.feedbackSequence += 1
	state.feedbackByCombatantId[combatantId] = {
		sequence = state.feedbackSequence,
		kind = kind,
		text = text,
	}
end

local function new(snapshot)
	return {
		snapshot = clone(snapshot),
		activeSourceCombatantId = nil,
		activeTargetCombatantIds = {},
		message = "Plans committed",
		currentActionName = nil,
		logEntries = {},
		feedbackByCombatantId = {},
		feedbackSequence = 0,
		seenEventIds = {},
		lastEventSequence = 0,
		roundTransition = false,
	}
end

local function apply(state, event)
	if event.id ~= nil and state.seenEventIds[event.id] then
		return state
	end
	if
		type(event.sequence) == "number"
		and state.lastEventSequence > 0
		and event.sequence <= state.lastEventSequence
	then
		return state
	end
	local nextState = clone(state)
	local snapshot = nextState.snapshot
	if event.id ~= nil then
		nextState.seenEventIds[event.id] = true
	end
	if type(event.sequence) == "number" then
		nextState.lastEventSequence = event.sequence
	end
	nextState.feedbackByCombatantId = {}
	nextState.roundTransition = false
	nextState.activeSourceCombatantId = event.sourceCombatantId
	nextState.activeTargetCombatantIds = clone(event.targetCombatantIds or {})
	local payload = event.payload or {}

	if event.kind == "INITIATIVE_DETERMINED" then
		snapshot.initiativeCombatantIds = clone(payload.initiativeCombatantIds or {})
		nextState.message = "Initiative determined"
		appendLog(nextState, event, "Initiative determined")
	elseif event.kind == "CARD_PLAYED" then
		local name = cardName(snapshot, payload)
		nextState.currentActionName = name
		nextState.message = `{name}`
		appendLog(nextState, event, `Played {name}`)
	elseif event.kind == "TARGET_SELECTED" then
		nextState.message = if payload.skipped
			then `{nextState.currentActionName or "Action"}: no valid target`
			else `{nextState.currentActionName or "Action"}: target locked`
		if payload.skipped then
			appendLog(nextState, event, nextState.message)
		end
	elseif event.kind == "DAMAGE_APPLIED" or event.kind == "STATUS_TICKED" then
		local target = findCombatant(snapshot, payload.targetCombatantId)
		if target ~= nil then
			target.currentHealth = payload.healthAfter
		end
		nextState.message = if event.kind == "DAMAGE_APPLIED"
			then if payload.isCritical == true and (payload.hpDamage or 0) > 0
				then `Critical hit: {payload.hpDamage} HP`
				elseif
					payload.isCritical == true and (payload.shieldAbsorbed or 0) > 0
				then `Critical hit: {payload.shieldAbsorbed} shield`
				else `Damage: {payload.hpDamage or 0}`
			else `{payload.statusId} tick: {payload.damage or 0}`
		local amount = if event.kind == "DAMAGE_APPLIED"
			then payload.hpDamage or 0
			else payload.damage or 0
		local label = if event.kind == "STATUS_TICKED"
			then `-{amount} {payload.statusId or "Status"}`
			elseif payload.isCritical == true and amount > 0 then `CRIT -{amount} HP`
			elseif
				payload.isCritical == true and (payload.shieldAbsorbed or 0) > 0
			then `CRIT -{payload.shieldAbsorbed} Shield`
			else `-{amount} HP`
		setFeedback(
			nextState,
			payload.targetCombatantId,
			if payload.isCritical == true then "CRITICAL" else "DAMAGE",
			label
		)
		appendLog(nextState, event, `{label} → {payload.targetCombatantId}`)
	elseif event.kind == "BLOOD_MOON_DAMAGE" then
		local target = findCombatant(snapshot, payload.targetCombatantId)
		if target ~= nil then
			target.currentHealth = payload.healthAfter
		end
		if (payload.shieldAbsorbed or 0) > 0 then
			local shields = snapshot.shieldsByCombatantId or {}
			snapshot.shieldsByCombatantId = shields
			shields[payload.targetCombatantId] =
				math.max(0, (shields[payload.targetCombatantId] or 0) - payload.shieldAbsorbed)
		end
		nextState.message = `Blood Moon: -{payload.hpDamage or 0} HP`
		local label = `BLOOD MOON -{payload.hpDamage or 0} HP`
		setFeedback(nextState, payload.targetCombatantId, "ENVIRONMENT", label)
		appendLog(nextState, event, `{label} → {payload.targetCombatantId}`)
	elseif event.kind == "HEAL_APPLIED" then
		local target = findCombatant(snapshot, payload.targetCombatantId)
		if target ~= nil then
			target.currentHealth = payload.healthAfter
		end
		nextState.message = `Healing: {payload.restored or 0}`
		local label = `+{payload.restored or 0} HP`
		setFeedback(nextState, payload.targetCombatantId, "HEAL", label)
		appendLog(nextState, event, `{label} → {payload.targetCombatantId}`)
	elseif event.kind == "SHIELD_GRANTED" or event.kind == "SHIELD_PREPARED" then
		local shields = snapshot.shieldsByCombatantId or {}
		snapshot.shieldsByCombatantId = shields
		shields[payload.targetCombatantId] = (shields[payload.targetCombatantId] or 0)
			+ (payload.amount or 0)
		local prepared = event.kind == "SHIELD_PREPARED"
		nextState.message = if prepared
			then `Shield prepared: {payload.amount or 0}`
			else `Shield gained: {payload.amount or 0}`
		local label = if prepared
			then `PREP +{payload.amount or 0} Shield`
			else `+{payload.amount or 0} Shield`
		setFeedback(nextState, payload.targetCombatantId, "SHIELD", label)
		appendLog(nextState, event, `{label} → {payload.targetCombatantId}`)
	elseif event.kind == "SHIELD_ABSORBED" then
		local shields = snapshot.shieldsByCombatantId or {}
		snapshot.shieldsByCombatantId = shields
		shields[payload.targetCombatantId] =
			math.max(0, (shields[payload.targetCombatantId] or 0) - (payload.absorbed or 0))
		nextState.message = `Shield absorbed: {payload.absorbed or 0}`
		local label = `-{payload.absorbed or 0} Shield`
		setFeedback(nextState, payload.targetCombatantId, "SHIELD", label)
		appendLog(nextState, event, `{label} → {payload.targetCombatantId}`)
	elseif event.kind == "STATUS_APPLIED" then
		local target = findCombatant(snapshot, payload.targetCombatantId)
		if target ~= nil then
			local existing = nil
			for _, status in target.statusEffects or {} do
				if status.statusId == payload.statusId then
					existing = status
					break
				end
			end
			if existing ~= nil then
				existing.stackCount = payload.stackCount
				existing.expiresAtRound = payload.expiresAtRound
			else
				target.statusEffects = target.statusEffects or {}
				table.insert(target.statusEffects, {
					statusId = payload.statusId,
					stackCount = payload.stackCount,
					magnitude = payload.magnitude,
					expiresAtRound = payload.expiresAtRound,
				})
			end
		end
		nextState.message = `Status applied: {payload.statusId}`
		local label = `{payload.statusId} x{payload.stackCount or 1}`
		setFeedback(nextState, payload.targetCombatantId, "STATUS", label)
		appendLog(nextState, event, `{label} → {payload.targetCombatantId}`)
	elseif event.kind == "STATUS_EXPIRED" then
		if payload.statusId == "SHIELD" then
			local shields = snapshot.shieldsByCombatantId or {}
			snapshot.shieldsByCombatantId = shields
			shields[payload.targetCombatantId] = math.max(
				0,
				(shields[payload.targetCombatantId] or 0) - (payload.remainingAmount or 0)
			)
		else
			local target = findCombatant(snapshot, payload.targetCombatantId)
			if target ~= nil then
				local kept = {}
				for _, status in target.statusEffects or {} do
					if status.statusId ~= payload.statusId then
						table.insert(kept, status)
					end
				end
				target.statusEffects = kept
			end
		end
		nextState.message = `Status expired: {payload.statusId}`
		local label = `{payload.statusId} expired`
		setFeedback(nextState, payload.targetCombatantId, "STATUS", label)
		appendLog(nextState, event, `{label} → {payload.targetCombatantId}`)
	elseif event.kind == "CRITTER_DEFEATED" then
		local target = findCombatant(snapshot, payload.combatantId)
		if target ~= nil then
			target.currentHealth = 0
		end
		nextState.message = "Critter defeated"
		setFeedback(nextState, payload.combatantId, "DEFEAT", "DEFEATED")
		appendLog(nextState, event, `{payload.combatantId} defeated`)
	elseif event.kind == "ACTION_CANCELED" then
		local name = cardName(snapshot, payload)
		nextState.currentActionName = name
		nextState.message = `{name} canceled: {payload.reason or "UNKNOWN"}`
		setFeedback(nextState, payload.sourceCombatantId, "CANCELED", "ACTION CANCELED")
		appendLog(nextState, event, nextState.message)
	elseif event.kind == "ROUND_COMPLETED" then
		nextState.currentActionName = `Round {event.roundNumber} complete`
		nextState.message = `Round complete — preparing round {payload.nextRoundNumber}`
		nextState.roundTransition = true
		appendLog(nextState, event, nextState.message)
	elseif event.kind == "MATCH_COMPLETED" then
		snapshot.matchOutcome = clone(payload)
		nextState.message = if payload.isDraw then "Draw" else "Match completed"
		nextState.currentActionName = nextState.message
		appendLog(nextState, event, nextState.message)
	end
	return nextState
end

local function applyAll(state, events)
	local nextState = state
	for _, event in events do
		nextState = apply(nextState, event)
	end
	return nextState
end

BattlePlayback.new = new
BattlePlayback.apply = apply
BattlePlayback.applyAll = applyAll
return table.freeze(BattlePlayback)
