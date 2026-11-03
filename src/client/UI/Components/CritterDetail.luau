--!strict

local UIFactory = require(script.Parent.UIFactory)
local AssetCatalog = require(script.Parent.Parent.Parent.Assets.AssetCatalog)
local CritterSpriteRig = require(script.Parent.Parent.Parent.Rendering.CritterSpriteRig)
local CritterDetail = {}

function CritterDetail.mount(parent: Instance, props)
	local root = Instance.new("Frame")
	root.BackgroundTransparency = 1
	root.Size = UDim2.new(1, 0, 0, 520)
	root.Parent = parent
	local art = CritterSpriteRig.mount(root, {
		className = props.critter.class,
		appearanceGenome = props.critter.appearanceGenome,
		facing = "RIGHT",
		resolveAsset = function(id)
			return AssetCatalog:resolve(id)
		end,
		size = UDim2.fromOffset(140, 140),
	})
	art.instance.AnchorPoint = Vector2.new(0, 0)
	art.instance.Position = UDim2.fromOffset(0, 0)
	local text = UIFactory.label(root, "", 15)
	text.AutomaticSize = Enum.AutomaticSize.Y
	text.Position = UDim2.fromOffset(152, 0)
	text.RichText = true
	text.Size = UDim2.new(1, -160, 0, 0)

	local function update(nextProps)
		local critter = nextProps.critter
		art.update({
			className = critter.class,
			appearanceGenome = critter.appearanceGenome,
			facing = "RIGHT",
			resolveAsset = function(id)
				return AssetCatalog:resolve(id)
			end,
			size = UDim2.fromOffset(140, 140),
		})
		text.Text = table.concat({
			`<b>{critter.displayName} — {critter.class}</b>`,
			`<b>Stats</b>\n{critter.statsText}`,
			`<b>Appearance</b>\n{critter.appearanceText}`,
			`<b>Abilities</b>\n{critter.abilityText}`,
			`<b>Equipment</b>\n{critter.equipmentText}`,
			`<b>Restrictions</b>\n{critter.restrictionsText}`,
		}, "\n\n")
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
