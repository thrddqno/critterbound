--!strict

local Theme = require(script.Parent.Parent.Theme)
local PlaceholderRenderer = require(script.Parent.Parent.Parent.Rendering.PlaceholderRenderer)
local CritterHealthBar = require(script.Parent.CritterHealthBar)

local CritterView = {}

export type Props = {
	critter: any,
	asset: any,
	side: "ALLY" | "ENEMY",
	compact: boolean?,
	selectable: boolean?,
	highlighted: boolean?,
	onActivated: ((string) -> ())?,
}

function CritterView.mount(parent: Instance, props: Props)
	local root = Instance.new("Frame")
	root.Name = "CritterView"
	root.BackgroundColor3 = Theme.Panel
	root.BorderColor3 = if props.side == "ALLY" then Theme.Ally else Theme.Enemy
	root.BorderSizePixel = 2
	root.ClipsDescendants = true
	root.Size = UDim2.new(0.32, -4, 1, 0)
	root.Parent = parent

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(5, 3)
	title.Size = UDim2.new(1, -10, 0, 20)
	title.TextColor3 = Theme.Text
	title.TextSize = 14
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = root

	local identity = Instance.new("TextLabel")
	identity.Name = "CombatantIdentity"
	identity.BackgroundTransparency = 1
	identity.Position = UDim2.fromOffset(5, 23)
	identity.Size = UDim2.new(1, -10, 0, 16)
	identity.TextColor3 = Theme.MutedText
	identity.TextSize = 10
	identity.TextTruncate = Enum.TextTruncate.AtEnd
	identity.TextXAlignment = Enum.TextXAlignment.Left
	identity.Parent = root

	local artHost = Instance.new("Frame")
	artHost.Name = "ArtHost"
	artHost.BackgroundTransparency = 1
	artHost.ClipsDescendants = true
	artHost.Position = UDim2.fromOffset(4, 41)
	artHost.Size = UDim2.new(1, -8, 1, -81)
	artHost.Parent = root

	local assetHandle = PlaceholderRenderer.mount(artHost, {
		asset = props.asset,
		aspectRatio = 1,
		dominantAxis = Enum.DominantAxis.Height,
		placeholderText = `Placeholder\n{props.critter.assetId}`,
		textSize = 11,
	})
	local healthHandle = CritterHealthBar.mount(root, props.critter)
	healthHandle.instance.Position = UDim2.new(0, 4, 1, -39)
	healthHandle.instance.Size = UDim2.new(1, -8, 0, 20)

	local speed = Instance.new("TextLabel")
	speed.Name = "Speed"
	speed.BackgroundTransparency = 1
	speed.Position = UDim2.new(0, 4, 1, -19)
	speed.Size = UDim2.new(1, -8, 0, 16)
	speed.TextColor3 = Theme.MutedText
	speed.TextSize = 12
	speed.TextXAlignment = Enum.TextXAlignment.Left
	speed.Parent = root

	local targetButton = Instance.new("TextButton")
	targetButton.Name = "TargetButton"
	targetButton.BackgroundTransparency = 1
	targetButton.Size = UDim2.fromScale(1, 1)
	targetButton.Text = ""
	targetButton.ZIndex = 10
	targetButton.Parent = root
	local currentProps = props
	local targetConnection = targetButton.Activated:Connect(function()
		if currentProps.selectable and currentProps.onActivated ~= nil then
			currentProps.onActivated(currentProps.critter.id)
		end
	end)

	local function update(nextProps: Props)
		currentProps = nextProps
		root.BorderColor3 = if nextProps.highlighted or nextProps.selectable
			then Theme.Action
			elseif nextProps.side == "ALLY" then Theme.Ally
			else Theme.Enemy
		root.BorderSizePixel = if nextProps.highlighted or nextProps.selectable then 4 else 2
		title.Text = `{nextProps.critter.displayName} · {nextProps.critter.class}`
		identity.Text = nextProps.critter.id
		local statuses = {}
		for _, status in nextProps.critter.statuses or {} do
			table.insert(statuses, `{status.statusId} x{status.stackCount or 1}`)
		end
		speed.Text = `Speed {nextProps.critter.speed}{if #statuses > 0
			then " · " .. table.concat(statuses, ", ")
			else ""}`
		title.TextTransparency = if nextProps.critter.defeated then 0.45 else 0
		artHost.Visible = not nextProps.critter.defeated
		targetButton.Active = nextProps.selectable == true
		assetHandle.update({
			asset = nextProps.asset,
			aspectRatio = 1,
			dominantAxis = Enum.DominantAxis.Height,
			placeholderText = `Placeholder\n{nextProps.critter.assetId}`,
			textSize = if nextProps.compact then 10 else 11,
		})
		healthHandle.update(nextProps.critter)
	end

	update(props)
	return table.freeze({
		instance = root,
		update = update,
		destroy = function()
			targetConnection:Disconnect()
			assetHandle.destroy()
			healthHandle.destroy()
			root:Destroy()
		end,
	})
end

return table.freeze(CritterView)
