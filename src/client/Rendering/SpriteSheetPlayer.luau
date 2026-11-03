--!strict

local SpriteSheetPlayer = {}

function SpriteSheetPlayer.frameAt(clip, elapsedSeconds: number)
	assert(#clip.frames > 0, "Animation clip requires frames")
	local total = 0
	for _, frame in clip.frames do
		total += frame.durationSeconds
	end
	if total <= 0 then
		return clip.frames[1], 1, true
	end
	local completed = not clip.looped and elapsedSeconds >= total
	local cursor = if clip.looped then elapsedSeconds % total else math.min(elapsedSeconds, total)
	local accumulated = 0
	for index, frame in clip.frames do
		accumulated += frame.durationSeconds
		if cursor < accumulated or index == #clip.frames then
			return frame, index, completed
		end
	end
	return clip.frames[#clip.frames], #clip.frames, completed
end

return table.freeze(SpriteSheetPlayer)
