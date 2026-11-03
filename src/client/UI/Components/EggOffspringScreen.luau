--!strict

local Theme = require(script.Parent.Parent.Theme)
local UIFactory = require(script.Parent.UIFactory)
local AssetCatalog = require(script.Parent.Parent.Parent.Assets.AssetCatalog)
local CritterSpriteRig = require(script.Parent.Parent.Parent.Rendering.CritterSpriteRig)

local EggOffspringScreen = {}

function EggOffspringScreen.mount(parent: Instance, props)
	local screen, root = UIFactory.screen(parent, "CritterboundEggOffspring")
	local title = UIFactory.label(root, "New Offspring", 28)
	title.Position = UDim2.fromOffset(18, 12)
	title.Size = UDim2.new(1, -320, 0, 42)
	local eggs = UIFactory.button(root, "Eggs")
	eggs.Position = UDim2.new(1, -306, 0, 10)
	eggs.Size = UDim2.fromOffset(136, 44)
	local back = UIFactory.button(root, "Main Menu")
	back.Position = UDim2.new(1, -154, 0, 10)
	back.Size = UDim2.fromOffset(136, 44)

	local panel = Instance.new("ScrollingFrame")
	panel.BackgroundColor3 = Theme.Panel
	panel.BorderColor3 = Theme.Border
	panel.Position = UDim2.fromOffset(18, 66)
	panel.Size = UDim2.new(1, -36, 1, -84)
	panel.AutomaticCanvasSize = Enum.AutomaticSize.Y
	panel.CanvasSize = UDim2.new()
	panel.ScrollBarThickness = 6
	panel.Parent = root
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 16)
	padding.PaddingRight = UDim.new(0, 16)
	padding.PaddingTop = UDim.new(0, 16)
	padding.PaddingBottom = UDim.new(0, 16)
	padding.Parent = panel

	local artHost = Instance.new("Frame")
	artHost.BackgroundColor3 = Theme.PanelAlt
	artHost.BorderColor3 = Theme.Border
	artHost.Size = UDim2.fromOffset(180, 180)
	artHost.Parent = panel
	local art = CritterSpriteRig.mount(artHost, {
		className = props.critter.class,
		appearanceGenome = props.critter.appearanceGenome,
		facing = "RIGHT",
		resolveAsset = function(id)
			return AssetCatalog:resolve(id)
		end,
		size = UDim2.fromOffset(160, 160),
	})

	local detail = UIFactory.label(panel, "", 16)
	detail.RichText = true
	detail.AutomaticSize = Enum.AutomaticSize.Y
	detail.Position = UDim2.fromOffset(200, 0)
	detail.Size = UDim2.new(1, -210, 0, 0)
	detail.Text = table.concat({
		`<b>{props.critter.displayName} — {props.critter.class}</b>`,
		`<b>Stats</b>\n{props.critter.statsText}`,
		`<b>Appearance</b>\n{props.critter.appearanceText}`,
		`<b>Abilities</b>\n{props.critter.abilityText}`,
		`<b>Restrictions</b>\n{props.critter.restrictionsText}`,
	}, "\n\n")

	local view = UIFactory.button(root, "View in Collection")
	view.AnchorPoint = Vector2.new(1, 1)
	view.Position = UDim2.new(1, -18, 1, -18)
	view.Size = UDim2.fromOffset(220, 48)

	local connections = {
		back.Activated:Connect(props.onBack),
		eggs.Activated:Connect(props.onEggs),
		view.Activated:Connect(props.onViewCollection),
	}

	return table.freeze({
		update = function() end,
		destroy = function()
			for _, connection in connections do
				connection:Disconnect()
			end
			art.destroy()
			screen:Destroy()
		end,
	})
end

return table.freeze(EggOffspringScreen)
