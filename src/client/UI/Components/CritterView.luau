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

	local function update(nextProps: Props)
		root.BorderColor3 = if nextProps.side == "ALLY" then Theme.Ally else Theme.Enemy
		title.Text = `{nextProps.critter.displayName} · {nextProps.critter.class}`
		identity.Text = nextProps.critter.id
		speed.Text = `Speed {nextProps.critter.speed}`
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
			assetHandle.destroy()
			healthHandle.destroy()
			root:Destroy()
		end,
	})
end

return table.freeze(CritterView)
