--!strict

local Theme = require(script.Parent.Parent.Theme)
local PlaceholderRenderer = require(script.Parent.Parent.Parent.Rendering.PlaceholderRenderer)

local CardView = {}

export type Props = {
	card: any,
	asset: any,
	selected: boolean,
	disabled: boolean,
	compact: boolean?,
	onActivated: (any) -> (),
}

function CardView.mount(parent: Instance, props: Props)
	local button = Instance.new("TextButton")
	button.Name = "CardView"
	button.BackgroundColor3 = Theme.Panel
	button.BorderColor3 = Theme.Border
	button.BorderSizePixel = 1
	button.ClipsDescendants = true
	button.Size = UDim2.new(0, if props.compact then 132 else 150, 1, -5)
	button.Text = ""
	button.AutoButtonColor = true
	button.Parent = parent

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 3)
	padding.PaddingBottom = UDim.new(0, 3)
	padding.PaddingLeft = UDim.new(0, 5)
	padding.PaddingRight = UDim.new(0, 5)
	padding.Parent = button

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 2)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = button

	local artHost = Instance.new("Frame")
	artHost.Name = "Artwork"
	artHost.BackgroundTransparency = 1
	artHost.ClipsDescendants = true
	artHost.LayoutOrder = 1
	artHost.Size = UDim2.fromScale(1, 0.3)
	artHost.Parent = button
	local assetHandle = PlaceholderRenderer.mount(artHost, {
		asset = props.asset,
		aspectRatio = 1.5,
		dominantAxis = Enum.DominantAxis.Height,
		textSize = 10,
	})

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.LayoutOrder = 2
	title.Size = UDim2.fromScale(1, 0.14)
	title.TextColor3 = Theme.Text
	title.TextSize = 14
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = button

	local cost = Instance.new("TextLabel")
	cost.Name = "Cost"
	cost.BackgroundTransparency = 1
	cost.LayoutOrder = 3
	cost.Size = UDim2.fromScale(1, 0.1)
	cost.TextColor3 = Theme.Text
	cost.TextSize = 12
	cost.TextXAlignment = Enum.TextXAlignment.Left
	cost.Parent = button

	local description = Instance.new("TextLabel")
	description.Name = "Description"
	description.BackgroundTransparency = 1
	description.LayoutOrder = 4
	description.Size = UDim2.fromScale(1, 0.22)
	description.TextColor3 = Theme.MutedText
	description.TextSize = 11
	description.TextTruncate = Enum.TextTruncate.AtEnd
	description.TextWrapped = true
	description.TextXAlignment = Enum.TextXAlignment.Left
	description.TextYAlignment = Enum.TextYAlignment.Top
	description.Parent = button

	local identity = Instance.new("TextLabel")
	identity.Name = "CardIdentity"
	identity.BackgroundTransparency = 1
	identity.LayoutOrder = 5
	identity.Size = UDim2.fromScale(1, 0.1)
	identity.TextColor3 = Theme.MutedText
	identity.TextSize = 9
	identity.TextTruncate = Enum.TextTruncate.AtEnd
	identity.TextXAlignment = Enum.TextXAlignment.Left
	identity.Parent = button

	local currentProps = props
	local connection = button.Activated:Connect(function()
		if not currentProps.disabled then
			currentProps.onActivated(currentProps.card)
		end
	end)

	local function update(nextProps: Props)
		currentProps = nextProps
		button.Size = UDim2.new(0, if nextProps.compact then 132 else 150, 1, -5)
		title.Text = nextProps.card.displayName
		cost.Text = `Energy {nextProps.card.energyCost} · {nextProps.card.class}`
		description.Text = nextProps.card.description or `Target: {nextProps.card.targetingRule}`
		identity.Text = nextProps.card.id
		button.BackgroundColor3 = if nextProps.selected
			then Theme.Action
			elseif nextProps.disabled then Theme.Disabled
			else Theme.Panel
		button.Active = not nextProps.disabled
		assetHandle.update({
			asset = nextProps.asset,
			aspectRatio = 1.5,
			dominantAxis = Enum.DominantAxis.Height,
			textSize = 10,
		})
	end

	update(props)
	return table.freeze({
		instance = button,
		update = update,
		destroy = function()
			connection:Disconnect()
			assetHandle.destroy()
			button:Destroy()
		end,
	})
end

return table.freeze(CardView)
