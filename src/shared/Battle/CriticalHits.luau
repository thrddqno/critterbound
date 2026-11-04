--!strict

local function requireSibling(name: string)
	if script ~= nil then
		return require((script.Parent :: any)[name])
	end
	return require(`./{name}`)
end

local CombatConstants = requireSibling("CombatConstants")

local function chance(morale: number): number
	return math.min(
		CombatConstants.MaximumCriticalChance,
		CombatConstants.BaseCriticalChance + CombatConstants.CriticalChancePerMorale * morale
	)
end

local function roll(state, morale: number, rng)
	local nextState, value = rng.next(state)
	local normalized = (value - 1) / (rng.Modulus - 1)
	return nextState, normalized < chance(morale)
end

return table.freeze({
	chance = chance,
	roll = roll,
})
