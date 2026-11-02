--!strict

export type QueuedCard = {
	cardInstanceId: string,
	sourceCombatantId: string,
	targetCombatantIds: { string },
	queueIndex: number,
}

export type InitiativeEntry = {
	combatantId: string,
	teamIndex: number,
	slot: number,
	speed: number,
	queuedCards: { QueuedCard },
}

local function compare(a: InitiativeEntry, b: InitiativeEntry, roundNumber: number): boolean
	if a.speed ~= b.speed then
		return a.speed > b.speed
	end

	if a.teamIndex ~= b.teamIndex then
		if roundNumber % 2 == 1 then
			return a.teamIndex < b.teamIndex
		end

		return a.teamIndex > b.teamIndex
	end

	if a.slot ~= b.slot then
		return a.slot < b.slot
	end

	return a.combatantId < b.combatantId
end

local function order(entries: { InitiativeEntry }, roundNumber: number): { InitiativeEntry }
	assert(roundNumber >= 1 and roundNumber % 1 == 0, "roundNumber must be a positive integer")

	local actionable: { InitiativeEntry } = {}

	for _, entry in entries do
		if #entry.queuedCards > 0 then
			table.insert(actionable, entry)
		end
	end

	table.sort(actionable, function(a, b)
		return compare(a, b, roundNumber)
	end)

	return actionable
end

export type CombatInitiativeEntry = {
	combatantId: string,
	teamIndex: number,
	slot: number,
	speed: number,
	currentHealth: number,
	skill: number?,
	resolve: number?,
	queuedCards: { QueuedCard },
}

-- Run 4B priority: higher effective Speed, lower current HP, higher Skill, higher Resolve,
-- then lower stable combatant ID. The legacy compare/order above remains for Run 2 contracts.
local function compareCombat(a: CombatInitiativeEntry, b: CombatInitiativeEntry): boolean
	if a.speed ~= b.speed then
		return a.speed > b.speed
	end
	if a.currentHealth ~= b.currentHealth then
		return a.currentHealth < b.currentHealth
	end
	local aSkill = a.skill or 0
	local bSkill = b.skill or 0
	if aSkill ~= bSkill then
		return aSkill > bSkill
	end
	local aResolve = a.resolve or 0
	local bResolve = b.resolve or 0
	if aResolve ~= bResolve then
		return aResolve > bResolve
	end
	return a.combatantId < b.combatantId
end

local function orderCombat(entries: { CombatInitiativeEntry }): { CombatInitiativeEntry }
	local actionable: { CombatInitiativeEntry } = {}
	for _, entry in entries do
		if #entry.queuedCards > 0 then
			table.insert(actionable, entry)
		end
	end
	table.sort(actionable, compareCombat)
	return actionable
end

return table.freeze({
	compare = compare,
	order = order,
	compareCombat = compareCombat,
	orderCombat = orderCombat,
})
