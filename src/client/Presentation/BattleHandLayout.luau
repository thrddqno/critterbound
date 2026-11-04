--!strict

-- Pure sizing math for the battle hand. The hand reserves a fixed header row for zone
-- counts, vertical padding, and the horizontal scrollbar so the full card frame always
-- fits inside the scrolling region instead of being clipped at the bottom.
local BattleHandLayout = {}

export type Layout = {
	headerHeight: number,
	cardAreaHeight: number,
	cardWidth: number,
	cardHeight: number,
	contentWidth: number,
	gap: number,
	horizontalPadding: number,
	verticalPadding: number,
	scrollbarThickness: number,
	needsScroll: boolean,
}

local HEADER_HEIGHT = 20
local SCROLLBAR_THICKNESS = 8

local function clamp(value: number, minimum: number, maximum: number): number
	return math.max(minimum, math.min(maximum, value))
end

local function compute(
	handWidth: number,
	cardAreaHeight: number,
	cardCount: number,
	compact: boolean?
): Layout
	local isCompact = compact == true
	local gap = if isCompact then 6 else 8
	local horizontalPadding = if isCompact then 6 else 8
	local verticalPadding = if isCompact then 5 else 6
	local usableHeight = math.max(0, cardAreaHeight)
	local cardHeight = math.max(0, usableHeight - verticalPadding * 2 - SCROLLBAR_THICKNESS)
	local minimumCardWidth = if isCompact then 118 else 132
	local maximumCardWidth = if isCompact then 144 else 164
	local count = math.max(cardCount, 1)
	local availableWidth = math.max(0, handWidth - horizontalPadding * 2)
	local fitWidth = (availableWidth - gap * (count - 1)) / count
	local cardWidth = math.floor(clamp(fitWidth, minimumCardWidth, maximumCardWidth))
	local contentWidth = horizontalPadding * 2 + cardWidth * count + gap * (count - 1)

	return {
		headerHeight = HEADER_HEIGHT,
		cardAreaHeight = cardAreaHeight,
		cardWidth = cardWidth,
		cardHeight = cardHeight,
		contentWidth = math.max(contentWidth, handWidth),
		gap = gap,
		horizontalPadding = horizontalPadding,
		verticalPadding = verticalPadding,
		scrollbarThickness = SCROLLBAR_THICKNESS,
		needsScroll = contentWidth > handWidth,
	}
end

BattleHandLayout.HEADER_HEIGHT = HEADER_HEIGHT
BattleHandLayout.SCROLLBAR_THICKNESS = SCROLLBAR_THICKNESS
BattleHandLayout.compute = compute
return table.freeze(BattleHandLayout)
