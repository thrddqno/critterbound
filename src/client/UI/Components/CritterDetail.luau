--!strict

local UIFactory = require(script.Parent.UIFactory)
local AssetCatalog = require(script.Parent.Parent.Parent.Assets.AssetCatalog)
local PlaceholderRenderer = require(script.Parent.Parent.Parent.Rendering.PlaceholderRenderer)
local CritterDetail = {}

function CritterDetail.mount(parent: Instance, props)
	local root = Instance.new("Frame")
	root.BackgroundTransparency = 1
	root.Size = UDim2.new(1, 0, 0, 360)
	root.Parent = parent
	local art = PlaceholderRenderer.mount(root, {
		asset = AssetCatalog:resolve(`creature.{string.lower(props.critter.class)}.default`),
		size = UDim2.fromOffset(120, 120),
		placeholderText = props.critter.class,
	})
	art.instance.AnchorPoint = Vector2.new(0, 0)
	art.instance.Position = UDim2.fromOffset(0, 0)
	local text = UIFactory.label(root, "", 15)
	text.Position = UDim2.fromOffset(132, 0)
	text.Size = UDim2.new(1, -136, 1, 0)

	local function update(nextProps)
		local critter = nextProps.critter
		art.update({
			asset = AssetCatalog:resolve(`creature.{string.lower(critter.class)}.default`),
			size = UDim2.fromOffset(120, 120),
			placeholderText = critter.class,
		})
		text.Text = table.concat({
			`{critter.displayName} — {critter.class}`,
			critter.statsText,
			`Appearance: {critter.appearanceText}`,
			`Abilities: {critter.abilityText}`,
			`Equipment: {critter.equipmentText}`,
			`Acquisition: {critter.acquisitionText}`,
			`Breeding: {critter.breedingText}`,
			critter.tradeText,
		}, "\n")
	end
	update(props)
	return table.freeze({
		update = update,
		destroy = function()
			art.destroy()
			root:Destroy()
		end,
	})
end

return table.freeze(CritterDetail)
