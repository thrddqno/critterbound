--!strict

local CardView = require(script.Parent.CardView)
local CardHand = {}

export type Props = {
	cards: { any },
	planningState: any,
	resolveAsset: (string) -> any,
	onCardSelected: (any) -> (),
	compact: boolean?,
}

function CardHand.mount(parent: Instance, props: Props)
	local root = Instance.new("ScrollingFrame")
	root.Name = "CardHand"
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.CanvasSize = UDim2.new(0, 0, 0, 0)
	root.AutomaticCanvasSize = Enum.AutomaticSize.X
	root.ScrollBarThickness = 5
	root.ScrollingDirection = Enum.ScrollingDirection.X
	root.Parent = parent
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = root
	local handles = {}

	local function clear()
		for _, handle in handles do
			handle.destroy()
		end
		table.clear(handles)
	end

	local function update(nextProps: Props)
		clear()
		local queued = {}
		for _, entry in nextProps.planningState.queuedCards do
			queued[entry.card.id] = true
		end
		for index, card in nextProps.cards do
			table.insert(
				handles,
				CardView.mount(root, {
					card = card,
					asset = nextProps.resolveAsset(card.assetId),
					selected = nextProps.planningState.selectedCardInstanceId == card.id,
					disabled = nextProps.planningState.committed or queued[card.id],
					compact = nextProps.compact,
					onActivated = nextProps.onCardSelected,
				})
			)
			handles[#handles].instance.LayoutOrder = index
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

return table.freeze(CardHand)
