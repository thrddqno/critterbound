--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GeneRegistry = require(ReplicatedStorage.Shared.Genetics.GeneRegistry)
local AssetCatalog = require(script.Parent.Parent.Parent.Assets.AssetCatalog)
local CritterSpriteRig = require(script.Parent.Parent.Parent.Rendering.CritterSpriteRig)
local UIFactory = require(script.Parent.UIFactory)
local Theme = require(script.Parent.Parent.Theme)

local SpritePreviewScreen = {}
local CLASSES = { "Stone", "Feral", "Verdant", "Tide", "Gale", "Shade" }

local VARIANTS = table.freeze({
	body = "gene.appearance.body.verdant.compact",
	eyes = "gene.appearance.eyes.verdant.wide",
	tail = "gene.appearance.tail.verdant.leafy",
	markings = "gene.appearance.markings.verdant.speckled",
	accessories = "gene.appearance.accessories.verdant.sprout",
})

local function clone<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, child in value :: any do
		result[clone(key)] = clone(child)
	end
	return result :: any
end

function SpritePreviewScreen.mount(parent: Instance, props)
	local screen, root = UIFactory.screen(parent, "CritterboundSpritePreview")
	local title = UIFactory.label(root, "Layered Sprite Preview · Studio Only", 26)
	title.Position = UDim2.fromOffset(18, 12)
	title.Size = UDim2.new(1, -190, 0, 44)
	local back = UIFactory.button(root, "Main Menu")
	back.Position = UDim2.new(1, -154, 0, 10)
	back.Size = UDim2.fromOffset(136, 44)
	local showcase = Instance.new("Frame")
	showcase.Name = "ClassRigShowcase"
	showcase.BackgroundTransparency = 1
	showcase.Position = UDim2.fromScale(0.025, 0.1)
	showcase.Size = UDim2.fromScale(0.95, 0.36)
	showcase.Parent = root
	local showcaseLayout = Instance.new("UIListLayout")
	showcaseLayout.FillDirection = Enum.FillDirection.Horizontal
	showcaseLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	showcaseLayout.Padding = UDim.new(0.008, 0)
	showcaseLayout.SortOrder = Enum.SortOrder.LayoutOrder
	showcaseLayout.Parent = showcase
	local showcaseRigs = {}
	for index, className in CLASSES do
		local card = Instance.new("Frame")
		card.Name = `{className}Preview`
		card.BackgroundColor3 = Theme.Panel
		card.BorderColor3 = Theme.Border
		card.LayoutOrder = index
		card.Size = UDim2.new(1 / #CLASSES, -8, 1, 0)
		card.Parent = showcase
		local label = UIFactory.label(card, string.upper(className), 14)
		label.Size = UDim2.new(1, 0, 0, 24)
		label.TextXAlignment = Enum.TextXAlignment.Center
		local host = Instance.new("Frame")
		host.BackgroundTransparency = 1
		host.Position = UDim2.fromOffset(0, 24)
		host.Size = UDim2.new(1, 0, 1, -24)
		host.Parent = card
		local classGenomes = GeneRegistry.defaultGenomes(className)
		table.insert(
			showcaseRigs,
			CritterSpriteRig.mount(host, {
				className = className,
				appearanceGenome = classGenomes.appearanceGenome,
				facing = "RIGHT",
				resolveAsset = function(id)
					return AssetCatalog:resolve(id)
				end,
			})
		)
	end

	local artHost = Instance.new("Frame")
	artHost.BackgroundColor3 = Theme.Panel
	artHost.BorderColor3 = Theme.Border
	artHost.ClipsDescendants = true
	artHost.Position = UDim2.fromScale(0.04, 0.5)
	artHost.Size = UDim2.fromScale(0.34, 0.44)
	artHost.Parent = root

	local genomes = GeneRegistry.defaultGenomes("Verdant")
	local genome = clone(genomes.appearanceGenome)
	local defaults = clone(genome)
	local enabled = {}
	local rig = CritterSpriteRig.mount(artHost, {
		className = "Verdant",
		appearanceGenome = genome,
		facing = "RIGHT",
		resolveAsset = function(id)
			return AssetCatalog:resolve(id)
		end,
	})
	local controls = Instance.new("Frame")
	controls.BackgroundTransparency = 1
	controls.Position = UDim2.fromScale(0.41, 0.5)
	controls.Size = UDim2.fromScale(0.18, 0.44)
	controls.Parent = root
	UIFactory.list(controls, 4)
	local inspector = Instance.new("ScrollingFrame")
	inspector.Name = "AssetDebugInspector"
	inspector.AutomaticCanvasSize = Enum.AutomaticSize.Y
	inspector.BackgroundColor3 = Theme.Panel
	inspector.BorderColor3 = Theme.Border
	inspector.CanvasSize = UDim2.new()
	inspector.Position = UDim2.fromScale(0.62, 0.5)
	inspector.ScrollBarThickness = 5
	inspector.Size = UDim2.fromScale(0.34, 0.44)
	inspector.Parent = root
	local assetDiagnostics = AssetCatalog:diagnostics()
	local inspectorTitle =
		UIFactory.label(inspector, `Asset Inspector · {assetDiagnostics.warnings} pending`, 16)
	inspectorTitle.Position = UDim2.fromOffset(8, 6)
	inspectorTitle.Size = UDim2.new(1, -16, 0, 26)
	local inspectorText = UIFactory.label(inspector, "", 11)
	inspectorText.AutomaticSize = Enum.AutomaticSize.Y
	inspectorText.Position = UDim2.fromOffset(8, 36)
	inspectorText.Size = UDim2.new(1, -24, 0, 0)
	inspectorText.TextColor3 = Theme.MutedText
	inspectorText.TextWrapped = true
	inspectorText.TextXAlignment = Enum.TextXAlignment.Left
	inspectorText.TextYAlignment = Enum.TextYAlignment.Top
	local connections = { back.Activated:Connect(props.onBack) }

	local function render()
		rig.update({
			className = "Verdant",
			appearanceGenome = genome,
			facing = "RIGHT",
			resolveAsset = function(id)
				return AssetCatalog:resolve(id)
			end,
		})
		local lines = {}
		for _, layer in rig.debugLayers() do
			table.insert(
				lines,
				`{string.upper(layer.slot)}\n{layer.assetId}{if layer.importSlot ~= nil
					then "\nImport: " .. layer.importSlot
					else ""}{if layer.isPlaceholder then " · placeholder" else ""}`
			)
		end
		inspectorText.Text = table.concat(lines, "\n\n")
	end
	render()
	for _, slot in { "body", "eyes", "tail", "markings", "accessories" } do
		local button = UIFactory.button(controls, `Swap {slot}`)
		button.Size = UDim2.new(1, 0, 0, 27)
		button.TextSize = 13
		table.insert(
			connections,
			button.Activated:Connect(function()
				enabled[slot] = not enabled[slot]
				genome.slots[slot] = if enabled[slot]
					then { D = VARIANTS[slot], R1 = VARIANTS[slot], R2 = VARIANTS[slot] }
					else clone(defaults.slots[slot])
				render()
			end)
		)
	end
	for _, animationId in { "IDLE", "ATTACK", "HIT", "DEFEAT" } do
		local button = UIFactory.button(controls, animationId)
		button.Size = UDim2.new(1, 0, 0, 27)
		button.TextSize = 13
		table.insert(
			connections,
			button.Activated:Connect(function()
				rig.play(animationId)
			end)
		)
	end

	return table.freeze({
		update = function() end,
		destroy = function()
			for _, connection in connections do
				connection:Disconnect()
			end
			rig.destroy()
			for _, showcaseRig in showcaseRigs do
				showcaseRig.destroy()
			end
			screen:Destroy()
		end,
	})
end

return table.freeze(SpritePreviewScreen)
