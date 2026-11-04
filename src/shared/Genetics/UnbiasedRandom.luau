--!strict

local function requireBattle(name: string)
	if script ~= nil then
		return require(script.Parent.Parent.Battle[name])
	end
	return require(`../Battle/{name}`)
end

local DeterministicRng = requireBattle("DeterministicRng")

local UnbiasedRandom = {}
local SOURCE_SIZE = DeterministicRng.Modulus - 1

-- Rejection sampling removes the modulo bias in DeterministicRng.nextInteger.
local function nextInteger(state, minimum: number, maximum: number)
	assert(minimum % 1 == 0 and maximum % 1 == 0 and minimum <= maximum, "Invalid RNG range")
	local range = maximum - minimum + 1
	assert(range <= SOURCE_SIZE, "RNG range exceeds source size")
	local acceptanceLimit = math.floor(SOURCE_SIZE / range) * range
	local current = state
	while true do
		local value
		current, value = DeterministicRng.next(current)
		local zeroBased = value - 1
		if zeroBased < acceptanceLimit then
			return current, minimum + (zeroBased % range)
		end
	end
end

UnbiasedRandom.Algorithm = DeterministicRng.Algorithm
UnbiasedRandom.Modulus = DeterministicRng.Modulus
UnbiasedRandom.new = DeterministicRng.new
UnbiasedRandom.nextInteger = nextInteger

return table.freeze(UnbiasedRandom)
