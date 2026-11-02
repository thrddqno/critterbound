--!strict

-- Resolve sibling modules in Roblox and under the Lune test runner.
local function requireSibling(name: string)
	if script ~= nil then
		return require((script.Parent :: any)[name])
	end
	return require(`./{name}`)
end

local CombatConstants = requireSibling("CombatConstants")

-- Run 4B assumption: no class chart existed before this run. The six classes form a ring.
-- Each class is advantaged against the next two classes and disadvantaged against the
-- previous two. Self and the opposite class are neutral. Values are balance-tunable but
-- changing the ring or multipliers is replay-breaking.

local RING = { "Verdant", "Tide", "Feral", "Gale", "Shade", "Stone" }
local RING_SIZE = #RING

local ADVANTAGE = CombatConstants.AdvantageMultiplier
local DISADVANTAGE = CombatConstants.DisadvantageMultiplier
local NEUTRAL = CombatConstants.NeutralMultiplier

local indexByClass: { [string]: number } = {}
for index, className in RING do
	indexByClass[className] = index
end

local function multiplier(sourceClass: string, targetClass: string): number
	local sourceIndex = indexByClass[sourceClass]
	local targetIndex = indexByClass[targetClass]
	if sourceIndex == nil or targetIndex == nil then
		return NEUTRAL
	end
	if sourceIndex == targetIndex then
		return NEUTRAL
	end

	local forward = (targetIndex - sourceIndex) % RING_SIZE
	if forward == 1 or forward == 2 then
		return ADVANTAGE
	end
	if forward == RING_SIZE - 1 or forward == RING_SIZE - 2 then
		return DISADVANTAGE
	end
	return NEUTRAL
end

return table.freeze({
	Ring = table.freeze(table.clone(RING)),
	Advantage = ADVANTAGE,
	Disadvantage = DISADVANTAGE,
	Neutral = NEUTRAL,
	multiplier = multiplier,
})
