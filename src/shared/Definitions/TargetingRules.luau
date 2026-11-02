--!strict

export type TargetingRule = "SELF" | "ALLY" | "ENEMY" | "ANY"

return table.freeze({
	SELF = "SELF" :: TargetingRule,
	ALLY = "ALLY" :: TargetingRule,
	ENEMY = "ENEMY" :: TargetingRule,
	ANY = "ANY" :: TargetingRule,
})
