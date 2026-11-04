--!strict

export type Rng = { algorithm: string, state: number, drawCount: number }
export type Zones = {
	drawPileCardInstanceIds: { string },
	handCardInstanceIds: { string },
	discardCardInstanceIds: { string },
	removedCardInstanceIds: { string }?,
}

local function requireSibling(name: string)
	if script ~= nil then
		return require((script.Parent :: any)[name])
	end
	return require(`./{name}`)
end

local CardLifecycleManager = requireSibling("CardLifecycleManager")
local DeckRules = requireSibling("DeckRules")
local DrawManager = requireSibling("DrawManager")

local function draw(zones: Zones, count: number, rng: Rng, shuffleFn, options)
	local drawOptions = options or { maxHandSize = DeckRules.Default.MaxHandSize }
	return DrawManager.draw(zones, count, rng, shuffleFn, drawOptions)
end

return table.freeze({
	draw = draw,
	removeCards = CardLifecycleManager.removeCards,
})
