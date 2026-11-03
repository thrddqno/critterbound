--!strict

export type TargetingRule =
	"SELF"
	| "ALLY"
	| "ENEMY"
	| "ANY"
	| "FRONT_ENEMY"
	| "ALL_ALLIES"
	| "ALL_ENEMIES"

local AUTOMATIC: { [string]: boolean } = table.freeze({
	SELF = true,
	ENEMY = true,
	FRONT_ENEMY = true,
	ALL_ALLIES = true,
	ALL_ENEMIES = true,
})

local function isAutomatic(rule: string): boolean
	return AUTOMATIC[rule] == true
end

return table.freeze({
	SELF = "SELF" :: TargetingRule,
	ALLY = "ALLY" :: TargetingRule,
	ENEMY = "ENEMY" :: TargetingRule,
	ANY = "ANY" :: TargetingRule,
	FRONT_ENEMY = "FRONT_ENEMY" :: TargetingRule,
	ALL_ALLIES = "ALL_ALLIES" :: TargetingRule,
	ALL_ENEMIES = "ALL_ENEMIES" :: TargetingRule,
	Automatic = AUTOMATIC,
	isAutomatic = isAutomatic,
})
