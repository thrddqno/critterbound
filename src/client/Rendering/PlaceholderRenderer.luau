--!strict

local Theme = require(script.Parent.Parent.UI.Theme)

local PlaceholderRenderer = {}

export type Props = {
	asset: any,
	size: UDim2?,
	aspectRatio: number?,
	dominantAxis: Enum.DominantAxis?,
	placeholderText: string?,
	textSize: number?,
}

function PlaceholderRenderer.mount(parent: Instance, props: Props)
	local root = Instance.new("Frame")
	root.Name = "AssetPlaceholder"
	root.BackgroundColor3 = Theme.PanelAlt
	root.BorderColor3 = Theme.Border
	root.BorderSizePixel = 1
	root.ClipsDescendants = true
	root.AnchorPoint = Vector2.new(0.5, 0)
	root.Position = UDim2.fromScale(0.5, 0)
	root.Size = props.size or UDim2.fromScale(1, 1)
	root.Parent = parent

	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = props.aspectRatio or 1
	aspect.DominantAxis = props.dominantAxis or Enum.DominantAxis.Width
	aspect.Parent = root

	local image = Instance.new("ImageLabel")
	image.Name = "Image"
	image.BackgroundTransparency = 1
	image.Size = UDim2.fromScale(1, 1)
	image.ScaleType = Enum.ScaleType.Fit
	image.Parent = root

	local label = Instance.new("TextLabel")
	label.Name = "PlaceholderLabel"
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(6, 4)
	label.Size = UDim2.new(1, -12, 1, -8)
	label.TextColor3 = Theme.Text
	label.TextSize = props.textSize or 12
	label.TextWrapped = true
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Parent = root

	local function update(nextProps: Props)
		local asset = nextProps.asset
		aspect.AspectRatio = nextProps.aspectRatio or 1
		aspect.DominantAxis = nextProps.dominantAxis or Enum.DominantAxis.Width
		label.TextSize = nextProps.textSize or 12
		if asset.image ~= nil and not asset.isPlaceholder then
			image.Image = asset.image
			image.Visible = true
			label.Visible = false
		else
			image.Image = ""
			image.Visible = false
			label.Text = nextProps.placeholderText or asset.label
			label.Visible = true
		end
	end

	update(props)
	return table.freeze({
		instance = root,
		update = update,
		destroy = function()
			root:Destroy()
		end,
	})
end

return table.freeze(PlaceholderRenderer)
