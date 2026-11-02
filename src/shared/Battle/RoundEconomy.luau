--!strict

local INITIAL_ENERGY = 3
local ENERGY_PER_ROUND = 2
local MAX_ENERGY = 10

local function initialEnergy(): number
	return INITIAL_ENERGY
end

local function nextRoundEnergy(current: number)
	if current ~= current or current % 1 ~= 0 or current < 0 or current > MAX_ENERGY then
		return {
			ok = false,
			errors = {
				{ code = "INVALID_ENERGY", message = "Energy must be an integer from 0 to 10" },
			},
		}
	end
	return { ok = true, value = math.min(current + ENERGY_PER_ROUND, MAX_ENERGY) }
end

return table.freeze({
	InitialEnergy = INITIAL_ENERGY,
	EnergyPerRound = ENERGY_PER_ROUND,
	MaxEnergy = MAX_ENERGY,
	initialEnergy = initialEnergy,
	nextRoundEnergy = nextRoundEnergy,
})
