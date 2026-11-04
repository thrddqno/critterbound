--!strict

export type BattlePhase = "PLANNING" | "RESOLVING" | "FINISHED"

local BattlePhase = table.freeze({
	PLANNING = "PLANNING" :: BattlePhase,
	RESOLVING = "RESOLVING" :: BattlePhase,
	FINISHED = "FINISHED" :: BattlePhase,
})

local VALID_PHASES: { [string]: boolean } = {
	PLANNING = true,
	RESOLVING = true,
	FINISHED = true,
}

local TRANSITIONS: { [string]: { [string]: boolean } } = {
	PLANNING = { RESOLVING = true },
	RESOLVING = { PLANNING = true, FINISHED = true },
	FINISHED = {},
}

local function isValid(value: unknown): boolean
	return type(value) == "string" and VALID_PHASES[value] == true
end

local function canTransition(from: BattlePhase, to: BattlePhase): boolean
	return TRANSITIONS[from][to] == true
end

return table.freeze({
	Phase = BattlePhase,
	isValid = isValid,
	canTransition = canTransition,
})
