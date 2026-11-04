--!strict

local BattleHudLayout = {}

export type Rect = { x: number, y: number, width: number, height: number }

local function rect(x: number, y: number, width: number, height: number): Rect
	return { x = x, y = y, width = width, height = height }
end

local function compute(viewportWidth: number, viewportHeight: number)
	local width = math.max(viewportWidth, 800)
	local height = math.max(viewportHeight, 620)
	local compact = width < 1000 or height < 700
	local margin = if compact then 8 else 12
	local gap = if compact then 5 else 7
	local contentWidth = width - margin * 2
	local contentHeight = math.max(height - margin * 2, if compact then 660 else 680)
	local topHudHeight = if compact then 38 else 42
	local orderHeight = if compact then 44 else 50
	local queueHeight = if compact then 84 else 96
	local handHeight = if compact then 252 else 280
	local controlsWidth = if compact then 174 else 220
	local orderY = topHudHeight + gap
	local battlefieldY = orderY + orderHeight + gap
	local handY = contentHeight - handHeight
	local queueY = handY - gap - queueHeight
	local battlefieldHeight = math.max(190, queueY - gap - battlefieldY)
	local controlsX = contentWidth - controlsWidth
	local handAreaWidth = controlsX - gap
	local handWidth = handAreaWidth
	local handX = 0

	return {
		ignoreGuiInset = true,
		compact = compact,
		canvasHeight = contentHeight + margin * 2,
		content = rect(margin, margin, contentWidth, contentHeight),
		topHud = rect(0, 0, contentWidth, topHudHeight),
		orderStrip = rect(0, orderY, contentWidth, orderHeight),
		battlefield = rect(0, battlefieldY, contentWidth, battlefieldHeight),
		queue = rect(0, queueY, contentWidth, queueHeight),
		hand = rect(handX, handY, handWidth, handHeight),
		controls = rect(controlsX, handY, controlsWidth, handHeight),
	}
end

BattleHudLayout.compute = compute
return table.freeze(BattleHudLayout)
