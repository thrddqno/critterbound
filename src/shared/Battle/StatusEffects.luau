--!strict

-- Resolve sibling modules in Roblox and under the Lune test runner.
local function requireSibling(name: string)
	if script ~= nil then
		return require((script.Parent :: any)[name])
	end
	return require(`./{name}`)
end

local CombatConstants = requireSibling("CombatConstants")

export type StatusEffect = {
	id: string,
	statusId: string,
	sourceCombatantId: string,
	targetCombatantId: string,
	magnitude: number,
	duration: number,
	stackCount: number,
	appliedRound: number,
	expiresAtRound: number,
}

local STATUS_IDS: { [string]: boolean } = {
	POISON = true,
	DAMAGE_UP = true,
	DAMAGE_DOWN = true,
	SPEED_UP = true,
	SPEED_DOWN = true,
}

local function isKnownStatus(statusId: string): boolean
	return STATUS_IDS[statusId] == true
end

local function stackCap(statusId: string): number
	return CombatConstants.MaxStacks[statusId] or 1
end

local function findStatus(combatant, statusId: string): StatusEffect?
	for _, effect in combatant.statusEffects or {} do
		if effect.statusId == statusId then
			return effect
		end
	end
	return nil
end

local function effectiveSpeed(combatant): number
	local speed = combatant.stats.speed or 0
	for _, effect in combatant.statusEffects or {} do
		local contribution = (effect.magnitude or 0) * (effect.stackCount or 1)
		if effect.statusId == "SPEED_UP" then
			speed += contribution
		elseif effect.statusId == "SPEED_DOWN" then
			speed -= contribution
		end
	end
	return math.max(0, speed)
end

local function damageModifier(combatant): number
	local modifier = 0
	for _, effect in combatant.statusEffects or {} do
		local contribution = (effect.magnitude or 0) * (effect.stackCount or 1)
		if effect.statusId == "DAMAGE_UP" then
			modifier += contribution
		elseif effect.statusId == "DAMAGE_DOWN" then
			modifier -= contribution
		end
	end
	return modifier
end

-- Duration counts round ends including the application round.
-- A duration of 2 applied in round 1 is active during rounds 1 and 2 and expires at the
-- end of round 2. Shields use duration 0 and expire at the end of the current round.
local function apply(
	combatant,
	statusId: string,
	magnitude: number,
	duration: number,
	sourceCombatantId: string,
	roundNumber: number,
	factory,
	events: { any }
): boolean
	if not isKnownStatus(statusId) then
		return false
	end

	combatant.statusEffects = combatant.statusEffects or {}
	local existing = findStatus(combatant, statusId)
	local expiresAtRound = roundNumber + math.max(0, duration - 1)

	if existing ~= nil then
		local cap = stackCap(statusId)
		if existing.stackCount < cap then
			existing.stackCount += 1
		end
		existing.expiresAtRound = math.max(existing.expiresAtRound, expiresAtRound)
		table.insert(
			events,
			factory.emit("STATUS_APPLIED", roundNumber, {
				statusId = statusId,
				sourceCombatantId = sourceCombatantId,
				targetCombatantId = combatant.id,
				magnitude = existing.magnitude,
				stackCount = existing.stackCount,
				expiresAtRound = existing.expiresAtRound,
				stacked = true,
			}, sourceCombatantId, { combatant.id })
		)
		return true
	end

	local effect: StatusEffect = {
		id = `status:{combatant.id}:{statusId}:{#combatant.statusEffects + 1}`,
		statusId = statusId,
		sourceCombatantId = sourceCombatantId,
		targetCombatantId = combatant.id,
		magnitude = magnitude,
		duration = duration,
		stackCount = 1,
		appliedRound = roundNumber,
		expiresAtRound = expiresAtRound,
	}
	table.insert(combatant.statusEffects, effect)
	table.insert(
		events,
		factory.emit("STATUS_APPLIED", roundNumber, {
			statusId = statusId,
			sourceCombatantId = sourceCombatantId,
			targetCombatantId = combatant.id,
			magnitude = magnitude,
			stackCount = 1,
			expiresAtRound = expiresAtRound,
			stacked = false,
		}, sourceCombatantId, { combatant.id })
	)
	return true
end

-- Round-end poison is simultaneous: all living combatants tick once in caller-supplied
-- deterministic order, then victory is evaluated by the caller. Poison bypasses shields and
-- can defeat a Critter.
local function tickPoison(
	combatants: { any },
	roundNumber: number,
	factory,
	events: { any }
): { string }
	local defeated = {}
	for _, combatant in combatants do
		if combatant.currentHealth > 0 then
			local poison = findStatus(combatant, "POISON")
			if poison ~= nil then
				local damage = math.max(0, (poison.magnitude or 0) * (poison.stackCount or 1))
				local healthBefore = combatant.currentHealth
				combatant.currentHealth = math.max(0, healthBefore - damage)
				table.insert(
					events,
					factory.emit("STATUS_TICKED", roundNumber, {
						statusId = "POISON",
						sourceCombatantId = poison.sourceCombatantId,
						targetCombatantId = combatant.id,
						damage = damage,
						healthBefore = healthBefore,
						healthAfter = combatant.currentHealth,
					}, poison.sourceCombatantId, { combatant.id })
				)
				if healthBefore > 0 and combatant.currentHealth == 0 then
					table.insert(defeated, combatant.id)
				end
			end
		end
	end
	return defeated
end

-- Expires statuses and ordinary shields at the end of `roundNumber`. Caller supplies a
-- deterministic combatant order so event order is replayable.
local function expire(combatants: { any }, roundNumber: number, factory, events: { any })
	for _, combatant in combatants do
		local kept = {}
		for _, effect in combatant.statusEffects or {} do
			if effect.expiresAtRound <= roundNumber then
				table.insert(
					events,
					factory.emit("STATUS_EXPIRED", roundNumber, {
						statusId = effect.statusId,
						sourceCombatantId = effect.sourceCombatantId,
						targetCombatantId = combatant.id,
						stackCount = effect.stackCount,
					}, effect.sourceCombatantId, { combatant.id })
				)
			else
				table.insert(kept, effect)
			end
		end
		combatant.statusEffects = kept

		local keptShields = {}
		for _, shield in combatant.shields or {} do
			if (shield.expiresAtRound or roundNumber) <= roundNumber then
				table.insert(
					events,
					factory.emit("STATUS_EXPIRED", roundNumber, {
						statusId = "SHIELD",
						sourceCombatantId = shield.sourceCombatantId,
						targetCombatantId = combatant.id,
						remainingAmount = shield.amount,
					}, shield.sourceCombatantId, { combatant.id })
				)
			else
				table.insert(keptShields, shield)
			end
		end
		combatant.shields = keptShields
	end
end

return table.freeze({
	STATUS_IDS = table.freeze(table.clone(STATUS_IDS)),
	isKnownStatus = isKnownStatus,
	findStatus = findStatus,
	effectiveSpeed = effectiveSpeed,
	damageModifier = damageModifier,
	apply = apply,
	tickPoison = tickPoison,
	expire = expire,
})
