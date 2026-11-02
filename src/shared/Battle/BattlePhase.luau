--!strict

export type BattlePhase =
	"CREATED"
	| "ROUND_START"
	| "PLANNING"
	| "COMMITTED"
	| "RESOLVING"
	| "ROUND_END"
	| "COMPLETED"

local BattlePhase = table.freeze({
	CREATED = "CREATED" :: BattlePhase,
	ROUND_START = "ROUND_START" :: BattlePhase,
	PLANNING = "PLANNING" :: BattlePhase,
	COMMITTED = "COMMITTED" :: BattlePhase,
	RESOLVING = "RESOLVING" :: BattlePhase,
	ROUND_END = "ROUND_END" :: BattlePhase,
	COMPLETED = "COMPLETED" :: BattlePhase,
})

local VALID_PHASES: { [string]: boolean } = {
	CREATED = true,
	ROUND_START = true,
	PLANNING = true,
	COMMITTED = true,
	RESOLVING = true,
	ROUND_END = true,
	COMPLETED = true,
}

local TRANSITIONS: { [string]: { [string]: boolean } } = {
	CREATED = { ROUND_START = true },
	ROUND_START = { PLANNING = true },
	PLANNING = { COMMITTED = true },
	COMMITTED = { RESOLVING = true },
	RESOLVING = { ROUND_END = true },
	ROUND_END = { ROUND_START = true, COMPLETED = true },
	COMPLETED = {},
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
