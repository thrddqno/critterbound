--!strict

-- Fisher-Yates with rejection sampling. Rejection avoids modulo bias while preserving the
-- injected deterministic RNG stream.
local function nextUnbiasedInteger(state, minimum: number, maximum: number, rng)
	local range = maximum - minimum + 1
	local sampleCount = rng.Modulus - 1
	local acceptedMaximum = math.floor(sampleCount / range) * range
	local current = state
	while true do
		local value
		current, value = rng.next(current)
		if value <= acceptedMaximum then
			return current, minimum + ((value - 1) % range)
		end
	end
end

local function shuffle(state, values, rng)
	local result = table.clone(values)
	local current = state
	for index = #result, 2, -1 do
		local swapIndex
		current, swapIndex = nextUnbiasedInteger(current, 1, index, rng)
		result[index], result[swapIndex] = result[swapIndex], result[index]
	end
	return current, result
end

return table.freeze({ shuffle = shuffle })
