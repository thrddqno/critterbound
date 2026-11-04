--!strict

local BASE_MAX_HEALTH = 150
local MAX_HEALTH_PER_HEALTH = 4

local function isFiniteNonNegative(value: any): boolean
	return type(value) == "number"
		and value == value
		and value < math.huge
		and value >= 0
		and value % 1 == 0
end

local function maxHealth(health: number): number
	assert(isFiniteNonNegative(health), "Health must be a finite non-negative integer")
	return BASE_MAX_HEALTH + MAX_HEALTH_PER_HEALTH * health
end

local function clampHealth(currentHealth: number, maximumHealth: number): number
	assert(isFiniteNonNegative(maximumHealth), "Maximum HP must be a finite non-negative integer")
	if type(currentHealth) ~= "number" or currentHealth ~= currentHealth then
		return 0
	end
	return math.clamp(currentHealth, 0, maximumHealth)
end

return table.freeze({
	BaseMaxHealth = BASE_MAX_HEALTH,
	MaxHealthPerHealth = MAX_HEALTH_PER_HEALTH,
	isValidHealth = isFiniteNonNegative,
	maxHealth = maxHealth,
	clampHealth = clampHealth,
})
