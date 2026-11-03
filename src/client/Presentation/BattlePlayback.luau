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

local function new(snapshot)
	return {
		snapshot = clone(snapshot),
		activeSourceCombatantId = nil,
		activeTargetCombatantIds = {},
		message = "Plans committed",
	}
end

local function apply(state, event)
	local nextState = clone(state)
	local snapshot = nextState.snapshot
	nextState.activeSourceCombatantId = event.sourceCombatantId
	nextState.activeTargetCombatantIds = clone(event.targetCombatantIds or {})
	local payload = event.payload or {}

	if event.kind == "INITIATIVE_DETERMINED" then
		snapshot.initiativeCombatantIds = clone(payload.initiativeCombatantIds or {})
		nextState.message = "Initiative determined"
	elseif event.kind == "CARD_PLAYED" then
		nextState.message = `Card played: {payload.cardDefinitionId or payload.cardInstanceId}`
	elseif event.kind == "DAMAGE_APPLIED" or event.kind == "STATUS_TICKED" then
		local target = findCombatant(snapshot, payload.targetCombatantId)
		if target ~= nil then
			target.currentHealth = payload.healthAfter
		end
		nextState.message = if event.kind == "DAMAGE_APPLIED"
			then `Damage: {payload.hpDamage or 0}`
			else `{payload.statusId} tick: {payload.damage or 0}`
	elseif event.kind == "HEAL_APPLIED" then
		local target = findCombatant(snapshot, payload.targetCombatantId)
		if target ~= nil then
			target.currentHealth = payload.healthAfter
		end
		nextState.message = `Healing: {payload.restored or 0}`
	elseif event.kind == "SHIELD_GRANTED" then
		local shields = snapshot.shieldsByCombatantId or {}
		snapshot.shieldsByCombatantId = shields
		shields[payload.targetCombatantId] = (shields[payload.targetCombatantId] or 0)
			+ (payload.amount or 0)
		nextState.message = `Shield gained: {payload.amount or 0}`
	elseif event.kind == "SHIELD_ABSORBED" then
		local shields = snapshot.shieldsByCombatantId or {}
		snapshot.shieldsByCombatantId = shields
		shields[payload.targetCombatantId] =
			math.max(0, (shields[payload.targetCombatantId] or 0) - (payload.absorbed or 0))
		nextState.message = `Shield absorbed: {payload.absorbed or 0}`
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
	elseif event.kind == "CRITTER_DEFEATED" then
		local target = findCombatant(snapshot, payload.combatantId)
		if target ~= nil then
			target.currentHealth = 0
		end
		nextState.message = "Critter defeated"
	elseif event.kind == "ROUND_COMPLETED" then
		nextState.message = "Round completed"
	elseif event.kind == "MATCH_COMPLETED" then
		snapshot.matchOutcome = clone(payload)
		nextState.message = if payload.isDraw then "Draw" else "Match completed"
	end
	return nextState
end

BattlePlayback.new = new
BattlePlayback.apply = apply
return table.freeze(BattlePlayback)
