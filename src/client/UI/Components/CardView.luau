--!strict

local Theme = require(script.Parent.Parent.Theme)
local PlaceholderRenderer = require(script.Parent.Parent.Parent.Rendering.PlaceholderRenderer)

local CardView = {}

export type Props = {
	card: any,
	asset: any,
	selected: boolean,
	disabled: boolean,
	disabledReason: string?,
	targetDescription: string?,
	compact: boolean?,
	width: number?,
	height: number?,
	onActivated: (any) -> (),
}

local function cardSize(props: Props): (number, number)
	local compact = props.compact == true
	local width = props.width or if compact then 136 else 156
	local height = props.height or if compact then 210 else 228
	return math.max(1, math.floor(width)), math.max(1, math.floor(height))
end

function CardView.mount(parent: Instance, props: Props)
	local button = Instance.new("TextButton")
	button.Name = "CardView"
	button.BackgroundColor3 = Theme.Panel
	button.BorderColor3 = Theme.Border
	button.BorderSizePixel = 1
	button.ClipsDescendants = true
	button.Text = ""
	button.AutoButtonColor = true
	button.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 7)
	corner.Parent = button

	-- Children use fixed pixel heights rather than scale offsets. A vertical UIListLayout
	-- plus scaled heights summed to more than the card frame, so the bottom of every card
	-- was clipped. Positioning each row explicitly keeps content inside the frame.
	local paddingLeft = 6
	local paddingRight = 6
	local paddingTop = 4
	local paddingBottom = 6

	local cost = Instance.new("TextLabel")
	cost.Name = "Cost"
	cost.BackgroundTransparency = 1
	cost.TextColor3 = Theme.Action
	cost.TextSize = 15
	cost.TextXAlignment = Enum.TextXAlignment.Left
	cost.TextTruncate = Enum.TextTruncate.AtEnd
	cost.Parent = button

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.TextColor3 = Theme.Text
	title.TextSize = 15
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = button

	local artHost = Instance.new("Frame")
	artHost.Name = "Artwork"
	artHost.BackgroundTransparency = 1
	artHost.ClipsDescendants = true
	artHost.Parent = button
	local assetHandle = PlaceholderRenderer.mount(artHost, {
		asset = props.asset,
		aspectRatio = 1.5,
		dominantAxis = Enum.DominantAxis.Height,
		textSize = 10,
	})

	local description = Instance.new("TextLabel")
	description.Name = "Description"
	description.BackgroundTransparency = 1
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
	identity.TextColor3 = Theme.MutedText
	identity.TextSize = 9
	identity.TextTruncate = Enum.TextTruncate.AtEnd
	identity.TextXAlignment = Enum.TextXAlignment.Left
	identity.Visible = false
	identity.Parent = button

	local function applySize(width: number, height: number)
		button.Size = UDim2.fromOffset(width, height)
		local contentWidth = math.max(1, width - paddingLeft - paddingRight)
		local costHeight = 20
		local titleHeight = 24
		local artGap = 2
		local artTop = paddingTop + costHeight + titleHeight + artGap
		local artHeight = math.clamp(math.floor(height * 0.28), 40, 78)
		local descriptionTop = artTop + artHeight + 4
		local descriptionHeight = math.max(0, height - descriptionTop - paddingBottom)

		cost.Position = UDim2.fromOffset(paddingLeft, paddingTop)
		cost.Size = UDim2.fromOffset(contentWidth, costHeight)
		title.Position = UDim2.fromOffset(paddingLeft, paddingTop + costHeight)
		title.Size = UDim2.fromOffset(contentWidth, titleHeight)
		artHost.Position = UDim2.fromOffset(paddingLeft, artTop)
		artHost.Size = UDim2.fromOffset(contentWidth, artHeight)
		description.Position = UDim2.fromOffset(paddingLeft, descriptionTop)
		description.Size = UDim2.fromOffset(contentWidth, descriptionHeight)
		identity.Position = UDim2.fromOffset(paddingLeft, height - paddingBottom)
		identity.Size = UDim2.fromOffset(contentWidth, 0)
	end

	local currentProps = props
	local connection = button.Activated:Connect(function()
		if not currentProps.disabled then
			currentProps.onActivated(currentProps.card)
		end
	end)

	local function update(nextProps: Props)
		currentProps = nextProps
		local width, height = cardSize(nextProps)
		applySize(width, height)
		title.Text = nextProps.card.displayName
		cost.Text = `COST {nextProps.card.energyCost}   ·   {nextProps.card.class}`
		local detail = nextProps.card.description or ""
		if nextProps.targetDescription ~= nil then
			detail ..= `\n{nextProps.targetDescription}`
		end
		if nextProps.disabledReason ~= nil then
			detail ..= `\n{nextProps.disabledReason}`
		end
		description.Text = detail
		description.TextColor3 = if nextProps.disabledReason ~= nil
			then Theme.Text
			else Theme.MutedText
		identity.Text = nextProps.card.id
		button.BackgroundColor3 = if nextProps.selected
			then Theme.Action
			elseif nextProps.disabled then Theme.Disabled
			else Theme.Panel
		button.Active = not nextProps.disabled
		button.BorderColor3 = if nextProps.selected then Theme.Text else Theme.Border
		button.BorderSizePixel = if nextProps.selected then 3 else 1
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
