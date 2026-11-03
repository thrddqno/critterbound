--!strict

local Theme = require(script.Parent.Parent.Theme)
local QueuePresentation = require(script.Parent.Parent.Parent.Presentation.QueuePresentation)

local CardQueue = {}

export type Props = {
	entries: { any },
	critters: { any },
	locked: boolean,
	compact: boolean?,
	onRemove: (string) -> (),
	onReorder: ((string, number) -> ())?,
}

function CardQueue.mount(parent: Instance, props: Props)
	local root = Instance.new("ScrollingFrame")
	root.Name = "CardQueue"
	root.AutomaticCanvasSize = Enum.AutomaticSize.X
	root.BackgroundColor3 = Theme.Panel
	root.BorderColor3 = Theme.Border
	root.BorderSizePixel = 1
	root.CanvasSize = UDim2.fromOffset(0, 0)
	root.ScrollBarThickness = 4
	root.ScrollingDirection = Enum.ScrollingDirection.X
	root.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = root

	local connections = {}
	local nodes = {}

	local function clear()
		for _, connection in connections do
			connection:Disconnect()
		end
		table.clear(connections)
		for _, node in nodes do
			node:Destroy()
		end
		table.clear(nodes)
	end

	local function update(nextProps: Props)
		clear()
		local groups = QueuePresentation.group(nextProps.entries, nextProps.critters)
		if #groups == 0 then
			local empty = Instance.new("TextLabel")
			empty.Name = "EmptyQueue"
			empty.BackgroundTransparency = 1
			empty.Size = UDim2.new(1, -8, 1, 0)
			empty.Text = "No cards queued"
			empty.TextColor3 = Theme.MutedText
			empty.TextSize = 13
			empty.TextXAlignment = Enum.TextXAlignment.Left
			empty.Parent = root
			table.insert(nodes, empty)
			return
		end

		local cardWidth = if nextProps.compact then 116 else 136
		for groupIndex, group in groups do
			local groupFrame = Instance.new("Frame")
			groupFrame.Name = group.sourceCombatantId
			groupFrame.BackgroundColor3 = Theme.PanelAlt
			groupFrame.BorderColor3 = Theme.Ally
			groupFrame.BorderSizePixel = 1
			groupFrame.LayoutOrder = groupIndex
			groupFrame.Size =
				UDim2.new(0, math.max(190, #group.entries * (cardWidth + 4) + 8), 1, -4)
			groupFrame.Parent = root
			table.insert(nodes, groupFrame)

			local heading = Instance.new("TextLabel")
			heading.BackgroundTransparency = 1
			heading.Position = UDim2.fromOffset(6, 2)
			heading.Size = UDim2.new(1, -12, 0, 18)
			heading.Text = `{group.displayName} · {group.sourceCombatantId}`
			heading.TextColor3 = Theme.Text
			heading.TextSize = 11
			heading.TextTruncate = Enum.TextTruncate.AtEnd
			heading.TextXAlignment = Enum.TextXAlignment.Left
			heading.Parent = groupFrame

			for entryIndex, entry in group.entries do
				local button = Instance.new("TextButton")
				button.Name = entry.card.id
				button.BackgroundColor3 = if nextProps.locked
					then Theme.Disabled
					else Theme.Background
				button.BorderColor3 = Theme.Border
				button.Position = UDim2.fromOffset(6 + (entryIndex - 1) * (cardWidth + 4), 22)
				button.Size = UDim2.new(0, cardWidth - 34, 1, -26)
				button.Text =
					`#{entry.sourceOrder}  {entry.card.displayName}\nEnergy {entry.card.energyCost}{if nextProps.locked
						then ""
						else " · Remove"}`
				button.TextColor3 = Theme.Text
				button.TextSize = if nextProps.compact then 10 else 11
				button.TextTruncate = Enum.TextTruncate.AtEnd
				button.TextWrapped = true
				button.Active = not nextProps.locked
				button.Parent = groupFrame
				table.insert(
					connections,
					button.Activated:Connect(function()
						if not nextProps.locked then
							nextProps.onRemove(entry.card.id)
						end
					end)
				)
				for offset, direction in { -1, 1 } do
					local reorder = Instance.new("TextButton")
					reorder.Name = if direction < 0 then "MoveLeft" else "MoveRight"
					reorder.BackgroundColor3 = Theme.Panel
					reorder.BorderColor3 = Theme.Border
					reorder.Position = UDim2.fromOffset(
						6 + (entryIndex - 1) * (cardWidth + 4) + cardWidth - 32,
						22 + (offset - 1) * 24
					)
					reorder.Size = UDim2.fromOffset(32, 22)
					reorder.Text = if direction < 0 then "<" else ">"
					reorder.TextColor3 = Theme.Text
					reorder.Active = not nextProps.locked
						and nextProps.onReorder ~= nil
						and entryIndex + direction >= 1
						and entryIndex + direction <= #group.entries
					reorder.Parent = groupFrame
					table.insert(
						connections,
						reorder.Activated:Connect(function()
							if reorder.Active and nextProps.onReorder ~= nil then
								nextProps.onReorder(entry.card.id, entry.sourceOrder + direction)
							end
						end)
					)
				end
			end
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

return table.freeze(CardQueue)
