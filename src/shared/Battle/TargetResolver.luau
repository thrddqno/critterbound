--!strict

-- Deterministic target resolution and retarget policy.
--
-- Rules:
--   SELF         -> the source combatant while alive.
--   ALLY         -> the submitted living ally; otherwise lowest-slot living ally (not self).
--   ENEMY        -> the submitted living enemy; otherwise lowest-slot living enemy.
--   FRONT_ENEMY  -> lowest-slot living enemy; submitted targets are ignored.
--   ALL_ALLIES   -> every living ally ordered by slot.
--   ALL_ENEMIES  -> every living enemy ordered by slot.
--   ANY          -> the submitted living target; otherwise skipped.
--
-- If no legal target exists the effect is skipped. A skipped card still consumes its turn.

export type Resolution = {
	targetIds: { string },
	retargeted: boolean,
	skipped: boolean,
}

local MULTI_RULES: { [string]: boolean } = {
	ALL_ALLIES = true,
	ALL_ENEMIES = true,
}

local function isAlive(combatant): boolean
	return combatant ~= nil and combatant.currentHealth > 0
end

local function livingBySlot(combatantsById, teamId: string?): { any }
	local living = {}
	for _, combatant in combatantsById do
		if isAlive(combatant) and (teamId == nil or combatant.teamId == teamId) then
			table.insert(living, combatant)
		end
	end
	table.sort(living, function(a, b)
		if a.slot ~= b.slot then
			return a.slot < b.slot
		end
		return a.id < b.id
	end)
	return living
end

local function resolve(
	rule: string,
	sourceCombatant,
	submittedTargetIds: { string },
	combatantsById
): Resolution
	if not isAlive(sourceCombatant) then
		return { targetIds = {}, retargeted = false, skipped = true }
	end

	if rule == "SELF" then
		return { targetIds = { sourceCombatant.id }, retargeted = false, skipped = false }
	end

	if rule == "ALL_ALLIES" or rule == "ALL_ENEMIES" then
		local teamId = if rule == "ALL_ALLIES" then sourceCombatant.teamId else nil
		local targets = {}
		for _, combatant in livingBySlot(combatantsById, teamId) do
			if rule == "ALL_ENEMIES" then
				if combatant.teamId ~= sourceCombatant.teamId then
					table.insert(targets, combatant.id)
				end
			else
				table.insert(targets, combatant.id)
			end
		end
		return { targetIds = targets, retargeted = false, skipped = #targets == 0 }
	end

	if rule == "FRONT_ENEMY" then
		for _, combatant in livingBySlot(combatantsById, nil) do
			if combatant.teamId ~= sourceCombatant.teamId then
				return { targetIds = { combatant.id }, retargeted = true, skipped = false }
			end
		end
		return { targetIds = {}, retargeted = false, skipped = true }
	end

	local submittedId = if submittedTargetIds ~= nil then submittedTargetIds[1] else nil
	local submitted = if submittedId ~= nil then combatantsById[submittedId] else nil

	if rule == "ALLY" then
		if
			isAlive(submitted)
			and submitted.teamId == sourceCombatant.teamId
			and submitted.id ~= sourceCombatant.id
		then
			return { targetIds = { submitted.id }, retargeted = false, skipped = false }
		end
		for _, combatant in livingBySlot(combatantsById, sourceCombatant.teamId) do
			if combatant.id ~= sourceCombatant.id then
				return { targetIds = { combatant.id }, retargeted = true, skipped = false }
			end
		end
		return { targetIds = {}, retargeted = false, skipped = true }
	end

	if rule == "ENEMY" then
		if isAlive(submitted) and submitted.teamId ~= sourceCombatant.teamId then
			return { targetIds = { submitted.id }, retargeted = false, skipped = false }
		end
		for _, combatant in livingBySlot(combatantsById, nil) do
			if combatant.teamId ~= sourceCombatant.teamId then
				return { targetIds = { combatant.id }, retargeted = true, skipped = false }
			end
		end
		return { targetIds = {}, retargeted = false, skipped = true }
	end

	-- ANY and unknown rules keep the submitted target only when it is alive.
	if isAlive(submitted) then
		return { targetIds = { submitted.id }, retargeted = false, skipped = false }
	end
	return { targetIds = {}, retargeted = false, skipped = true }
end

local function isMultiTarget(rule: string): boolean
	return MULTI_RULES[rule] == true
end

return table.freeze({
	resolve = resolve,
	isMultiTarget = isMultiTarget,
	isAlive = isAlive,
})
