--!strict

local CritterAnimationState = {}
local TEMPORARY = table.freeze({ ATTACK = true, HIT = true })

function CritterAnimationState.new()
	return { id = "IDLE", revision = 0 }
end

function CritterAnimationState.transition(state, animationId: string)
	assert(
		animationId == "IDLE"
			or animationId == "ATTACK"
			or animationId == "HIT"
			or animationId == "DEFEAT",
		`Unknown animation state {animationId}`
	)
	if state.id == "DEFEAT" and animationId ~= "IDLE" then
		return state
	end
	return { id = animationId, revision = state.revision + 1 }
end

function CritterAnimationState.completion(state, revision: number)
	if state.revision ~= revision or not TEMPORARY[state.id] then
		return state
	end
	return { id = "IDLE", revision = state.revision + 1 }
end

return table.freeze(CritterAnimationState)
