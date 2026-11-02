--!strict

local Theme = require(script.Parent.Parent.Theme)
local InitiativeTimeline = {}

export type Props = { entries: { any }, compact: boolean? }

function InitiativeTimeline.mount(parent: Instance, props: Props)
	local root = Instance.new("ScrollingFrame")
	root.Name = "InitiativeTimeline"
	root.AutomaticCanvasSize = Enum.AutomaticSize.X
	root.BackgroundColor3 = Theme.Panel
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
		for _, entry in nextProps.entries do
			local card = Instance.new("Frame")
			card.Name = entry.combatantId
			card.BackgroundColor3 = Theme.PanelAlt
			card.BorderColor3 = if entry.side == "ALLY" then Theme.Ally else Theme.Enemy
			card.BorderSizePixel = 2
			card.LayoutOrder = entry.position
			card.Size = UDim2.new(0, if nextProps.compact then 150 else 180, 1, -4)
			card.Parent = root
			table.insert(cards, card)

			local heading = Instance.new("TextLabel")
			heading.BackgroundTransparency = 1
			heading.Position = UDim2.fromOffset(6, 2)
			heading.Size = UDim2.new(1, -12, 0, 18)
			heading.Text =
				`#{entry.position} · {if entry.side == "ALLY" then "PLAYER" else "ENEMY"} · Speed {entry.speed}`
			heading.TextColor3 = Theme.Text
			heading.TextSize = if nextProps.compact then 10 else 11
			heading.TextTruncate = Enum.TextTruncate.AtEnd
			heading.TextXAlignment = Enum.TextXAlignment.Left
			heading.Parent = card

			local name = Instance.new("TextLabel")
			name.BackgroundTransparency = 1
			name.Position = UDim2.fromOffset(6, 20)
			name.Size = UDim2.new(1, -12, 0, 18)
			name.Text = `{entry.displayName} · {entry.class}`
			name.TextColor3 = Theme.Text
			name.TextSize = 12
			name.TextTruncate = Enum.TextTruncate.AtEnd
			name.TextXAlignment = Enum.TextXAlignment.Left
			name.Parent = card

			local identity = Instance.new("TextLabel")
			identity.BackgroundTransparency = 1
			identity.Position = UDim2.fromOffset(6, 38)
			identity.Size = UDim2.new(1, -12, 1, -40)
			identity.Text = `{entry.teamId} · {entry.combatantId}`
			identity.TextColor3 = Theme.MutedText
			identity.TextSize = 9
			identity.TextTruncate = Enum.TextTruncate.AtEnd
			identity.TextXAlignment = Enum.TextXAlignment.Left
			identity.Parent = card
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
