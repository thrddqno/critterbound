--!strict

local MODULUS = 2147483647
local MULTIPLIER = 16807

export type State = { algorithm: "PARK_MILLER_V1", state: number, drawCount: number }

local function new(seed: number)
	if seed ~= seed or seed % 1 ~= 0 or seed < 1 or seed >= MODULUS then
		return {
			ok = false,
			errors = {
				{
					code = "INVALID_RNG_SEED",
					message = "Seed must be an integer from 1 to 2147483646",
				},
			},
		}
	end
	return {
		ok = true,
		value = { algorithm = "PARK_MILLER_V1", state = seed, drawCount = 0 } :: State,
	}
end

local function nextValue(state: State): (State, number)
	local nextState = (state.state * MULTIPLIER) % MODULUS
	return { algorithm = "PARK_MILLER_V1", state = nextState, drawCount = state.drawCount + 1 },
		nextState
end

local function nextInteger(state: State, minimum: number, maximum: number): (State, number)
	assert(minimum % 1 == 0 and maximum % 1 == 0 and minimum <= maximum, "Invalid RNG range")
	local nextState, value = nextValue(state)
	return nextState, minimum + (value % (maximum - minimum + 1))
end

local function shuffle<T>(state: State, values: { T }): (State, { T })
	local result = table.clone(values)
	local current = state
	for index = #result, 2, -1 do
		local swapIndex
		current, swapIndex = nextInteger(current, 1, index)
		result[index], result[swapIndex] = result[swapIndex], result[index]
	end
	return current, result
end

return table.freeze({
	Algorithm = "PARK_MILLER_V1",
	Modulus = MODULUS,
	new = new,
	next = nextValue,
	nextInteger = nextInteger,
	shuffle = shuffle,
})
