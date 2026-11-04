--!strict

local Theme = require(script.Parent.Parent.Theme)
local BattleHudPresentation =
	require(script.Parent.Parent.Parent.Presentation.BattleHudPresentation)
local InitiativeTimeline = {}

export type Props = { entries: { any }, compact: boolean? }

function InitiativeTimeline.mount(parent: Instance, props: Props)
	local root = Instance.new("ScrollingFrame")
	root.Name = "InitiativeTimeline"
	root.AutomaticCanvasSize = Enum.AutomaticSize.X
	root.BackgroundColor3 = Theme.Background
	root.BackgroundTransparency = 0.12
	root.BorderSizePixel = 0
	root.CanvasSize = UDim2.fromOffset(0, 0)
	root.ScrollBarThickness = 4
	root.ScrollingDirection = Enum.ScrollingDirection.X
	root.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 5)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = root

	local cards = {}
	local function clear()
		for _, card in cards do
			card:Destroy()
		end
		table.clear(cards)
	end

	local function update(nextProps: Props)
		clear()
		local entries = BattleHudPresentation.orderChips(nextProps.entries)
		if #entries == 0 then
			local empty = Instance.new("TextLabel")
			empty.Name = "EmptyActionOrder"
			empty.BackgroundTransparency = 1
			empty.Size = UDim2.new(1, -12, 1, -4)
			empty.Text = "ACTION ORDER  ·  Awaiting committed plans"
			empty.TextColor3 = Theme.MutedText
			empty.TextSize = if nextProps.compact then 10 else 11
			empty.TextXAlignment = Enum.TextXAlignment.Left
			empty.Parent = root
			table.insert(cards, empty)
			return
		end
		for _, entry in entries do
			local card = Instance.new("Frame")
			card.Name = entry.combatantId
			card.BackgroundColor3 = Theme.PanelAlt
			card.BorderColor3 = if entry.side == "ALLY" then Theme.Ally else Theme.Enemy
			card.BorderSizePixel = 1
			card.LayoutOrder = entry.position
			card.Size = UDim2.new(0, if nextProps.compact then 112 else 132, 1, -4)
			card.Parent = root
			table.insert(cards, card)

			local heading = Instance.new("TextLabel")
			heading.BackgroundTransparency = 1
			heading.Position = UDim2.fromOffset(5, 2)
			heading.Size = UDim2.new(0, 30, 1, -4)
			heading.Text = tostring(entry.position)
			heading.TextColor3 = Theme.Text
			heading.TextSize = 20
			heading.Parent = card

			local name = Instance.new("TextLabel")
			name.BackgroundTransparency = 1
			name.Position = UDim2.fromOffset(38, 3)
			name.Size = UDim2.new(1, -42, 0.58, -3)
			name.Text = entry.displayName
			name.TextColor3 = Theme.Text
			name.TextSize = if nextProps.compact then 10 else 11
			name.TextTruncate = Enum.TextTruncate.AtEnd
			name.TextXAlignment = Enum.TextXAlignment.Left
			name.Parent = card

			local detail = Instance.new("TextLabel")
			detail.BackgroundTransparency = 1
			detail.Position = UDim2.new(0, 38, 0.52, 0)
			detail.Size = UDim2.new(1, -42, 0.48, -2)
			detail.Text = `{entry.class} · SPD {entry.speed}`
			detail.TextColor3 = Theme.MutedText
			detail.TextSize = 9
			detail.TextTruncate = Enum.TextTruncate.AtEnd
			detail.TextXAlignment = Enum.TextXAlignment.Left
			detail.Parent = card
		end
	end

	update(props)
	return table.freeze({
		instance = root,
		update = update,
		destroy = function()
			clear()
			root:Destroy()
		end,
	})
end

return table.freeze(InitiativeTimeline)
