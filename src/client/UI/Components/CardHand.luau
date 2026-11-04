--!strict

local CardView = require(script.Parent.CardView)
local BattleHandLayout = require(script.Parent.Parent.Parent.Presentation.BattleHandLayout)
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
	root.BackgroundColor3 = Color3.fromRGB(20, 23, 29)
	root.BackgroundTransparency = 0.12
	root.BorderSizePixel = 0
	root.CanvasSize = UDim2.new(0, 0, 0, 0)
	root.AutomaticCanvasSize = Enum.AutomaticSize.None
	root.ScrollBarThickness = BattleHandLayout.SCROLLBAR_THICKNESS
	root.ScrollingDirection = Enum.ScrollingDirection.X
	root.ClipsDescendants = true
	root.Parent = parent
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = root
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingBottom = UDim.new(0, BattleHandLayout.SCROLLBAR_THICKNESS + 6)
	padding.Parent = root
	local entries = {}
	local currentProps = props

	local function clear()
		for _, entry in entries do
			entry.handle.destroy()
		end
		table.clear(entries)
	end

	local function applyLayout()
		local size = root.AbsoluteSize
		local cardCount = #currentProps.cards
		local computed = BattleHandLayout.compute(size.X, size.Y, cardCount, currentProps.compact)
		root.CanvasSize = UDim2.fromOffset(computed.contentWidth, 0)
		root.ScrollBarThickness = computed.scrollbarThickness
		layout.Padding = UDim.new(0, computed.gap)
		padding.PaddingLeft = UDim.new(0, computed.horizontalPadding)
		padding.PaddingRight = UDim.new(0, computed.horizontalPadding)
		padding.PaddingTop = UDim.new(0, computed.verticalPadding)
		padding.PaddingBottom = UDim.new(0, computed.verticalPadding + computed.scrollbarThickness)
		for _, entry in entries do
			entry.props.width = computed.cardWidth
			entry.props.height = computed.cardHeight
			entry.handle.update(entry.props)
		end
	end

	local function update(nextProps: Props)
		currentProps = nextProps
		clear()
		local disabledReasons = nextProps.planningState.disabledReasons or {}
		local targetDescriptions = nextProps.planningState.targetDescriptions or {}
		for index, card in nextProps.cards do
			local cardProps = {
				card = card,
				asset = nextProps.resolveAsset(card.assetId),
				selected = nextProps.planningState.selectedCardInstanceId == card.id,
				disabled = disabledReasons[card.id] ~= nil,
				disabledReason = disabledReasons[card.id],
				targetDescription = targetDescriptions[card.id],
				compact = nextProps.compact,
				width = 0,
				height = 0,
				onActivated = nextProps.onCardSelected,
			}
			local handle = CardView.mount(root, cardProps)
			handle.instance.LayoutOrder = index
			table.insert(entries, { handle = handle, props = cardProps })
		end
		applyLayout()
	end

	local sizeConnection = root:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyLayout)

	update(props)
	return table.freeze({
		instance = root,
		update = update,
		destroy = function()
			sizeConnection:Disconnect()
			clear()
			root:Destroy()
		end,
	})
end

return table.freeze(CardHand)
