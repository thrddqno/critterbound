--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AppearanceResolver = require(ReplicatedStorage.Shared.Genetics.AppearanceResolver)
local CritterSpriteModel = require(script.Parent.CritterSpriteModel)
local CritterAnimationController = require(script.Parent.CritterAnimationController)

local CritterSpriteRig = {}

export type Props = {
	className: string,
	appearanceGenome: any,
	facing: string?,
	resolveAsset: (string) -> any,
	size: UDim2?,
}

local function toColor(value): Color3
	return Color3.fromRGB(value.red, value.green, value.blue)
end

local function resolveModel(props: Props)
	local result = AppearanceResolver.resolveDominant(props.appearanceGenome, props.className)
	if result.ok then
		return CritterSpriteModel.build(result.value, props.facing)
	end
	local lower = string.lower(props.className)
	return CritterSpriteModel.build({
		bodyRigFamily = "round",
		spriteRigId = lower,
		baseAssetId = `creature.{lower}.default`,
		layers = {},
	}, props.facing)
end

local function mirroredAttachment(value, facing: string, widthScale: number?, heightScale: number?)
	return {
		x = if facing == "LEFT" then 1 - value.position.x else value.position.x,
		y = value.position.y,
		width = value.size.width * (widthScale or 1),
		height = value.size.height * (heightScale or 1),
		rotation = if facing == "LEFT" then -value.rotation else value.rotation,
	}
end

local function addPart(
	parent: Instance,
	name: string,
	attachment,
	partColor: Color3,
	zIndex: number,
	transparency: number?
)
	local part = Instance.new("Frame")
	part.Name = name
	part.AnchorPoint = Vector2.new(0.5, 0.5)
	part.BackgroundColor3 = partColor
	part.BackgroundTransparency = transparency or 0
	part.BorderSizePixel = 0
	part.Position = UDim2.fromScale(attachment.x, attachment.y)
	part.Rotation = attachment.rotation
	part.Size = UDim2.fromScale(attachment.width, attachment.height)
	part.ZIndex = zIndex
	part.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = part
	return part
end

local function addOutline(part: GuiObject, zIndex: number, outlineColor: Color3)
	local stroke = Instance.new("UIStroke")
	stroke.Name = "Outline"
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = outlineColor
	stroke.Thickness = 1.5
	stroke.Transparency = 0.2
	stroke.Parent = part
	part.ZIndex = zIndex
end

local function clearChildren(parent: Instance)
	for _, child in parent:GetChildren() do
		child:Destroy()
	end
end

local function renderPlaceholder(handle, layer, model)
	clearChildren(handle.placeholder)
	local facing = model.facing
	local attachments = model.attachments
	local style = model.style
	local colors = {}
	for name, value in model.palette do
		colors[name] = toColor(value)
	end
	local z = layer.order + 1
	local function attachment(name: string, widthScale: number?, heightScale: number?)
		return mirroredAttachment(attachments[name], facing, widthScale, heightScale)
	end
	local function outlined(name: string, anchor, partColor: Color3, offset: number?)
		local part = addPart(handle.placeholder, name, anchor, partColor, z + (offset or 0))
		addOutline(part, z + (offset or 0), colors.outline)
		return part
	end

	if layer.slot == "shadow" then
		addPart(handle.placeholder, "Shadow", attachment("shadow"), colors.shadow, z, 0.3)
	elseif layer.slot == "tail" then
		outlined("Tail", attachment("tail"), colors.body)
		if string.find(layer.assetId, ".leafy", 1, true) ~= nil then
			outlined("TailLeaf", attachment("tailTip", 1.15, 1.35), colors.belly, 1)
		elseif style == "TIDE" then
			outlined("FlowingTailFin", attachment("tailTip", 1.15, 1.25), colors.accent, 1)
		elseif style == "GALE" then
			outlined("TailFeather", attachment("tailTip", 0.9, 1.3), colors.wing, 1)
		elseif style == "SHADE" then
			outlined("TailWisp", attachment("tailTip", 1.15, 0.65), colors.accent, 1)
		elseif style == "FERAL" then
			outlined("TailSpike", attachment("tailTip", 1.15, 0.55), colors.accent, 1)
		else
			outlined("TailTip", attachment("tailTip", 0.8, 0.8), colors.head, 1)
		end
	elseif layer.slot == "wings" then
		outlined(
			if style == "TIDE" then "TopFin" else "LeftWing",
			attachment("wingLeft"),
			colors.wing
		)
		outlined(
			if style == "TIDE" then "LowerFin" else "RightWing",
			attachment("wingRight"),
			colors.wing
		)
	elseif layer.slot == "body" then
		local compactBody = string.find(layer.assetId, ".compact", 1, true) ~= nil
		if style == "SHADE" then
			outlined("LeftWisp", attachment("wispLeft"), colors.accent)
			outlined("RightWisp", attachment("wispRight"), colors.accent)
		end
		outlined("LeftFoot", attachment("leftFoot"), colors.head)
		outlined("RightFoot", attachment("rightFoot"), colors.head)
		if style == "STONE" then
			outlined("RockShoulderLeft", attachment("shoulderLeft"), colors.accent, 1)
			outlined("RockShoulderRight", attachment("shoulderRight"), colors.accent, 1)
		elseif style == "SHADE" then
			outlined("BodyPuffLeft", attachment("shoulderLeft"), colors.body, 1)
			outlined("BodyPuffRight", attachment("shoulderRight"), colors.body, 1)
		end
		outlined(
			"Body",
			attachment("body", if compactBody then 1.12 else 1, if compactBody then 0.84 else 1),
			colors.body,
			1
		)
		outlined("Head", attachment("head", if compactBody then 1.08 else 1), colors.head, 2)
		if style == "FERAL" then
			outlined("Snout", attachment("snout"), colors.head, 3)
			outlined("PointedEarLeft", attachment("earLeft", 0.65, 1), colors.accent, 2)
			outlined("PointedEarRight", attachment("earRight", 0.65, 1), colors.accent, 2)
			outlined("BackSpike", attachment("crest", 0.55, 1), colors.accent, 2)
		elseif style == "VERDANT" then
			outlined("LeafEarLeft", attachment("earLeft"), colors.belly, 2)
			outlined("LeafEarRight", attachment("earRight"), colors.belly, 2)
			outlined("LeafCrown", attachment("crest", 0.7, 0.85), colors.accent, 3)
		elseif style == "TIDE" then
			outlined("HeadFin", attachment("crest", 0.55, 1), colors.accent, 2)
			outlined("Muzzle", attachment("snout"), colors.head, 3)
		elseif style == "GALE" then
			outlined("FeatherCrestCenter", attachment("crest", 0.55, 1), colors.accent, 3)
			outlined("FeatherCrestLeft", attachment("earLeft", 0.55, 1), colors.wing, 2)
			outlined("FeatherCrestRight", attachment("earRight", 0.55, 1), colors.wing, 2)
		elseif style == "SHADE" then
			outlined("ShadowTuftLeft", attachment("earLeft", 0.7, 0.8), colors.accent, 2)
			outlined("ShadowTuftRight", attachment("earRight", 0.7, 0.8), colors.accent, 2)
		end
	elseif layer.slot == "color" then
		addPart(handle.placeholder, "BellyColor", attachment("belly"), colors.belly, z, 0.12)
	elseif layer.slot == "markings" then
		local area = attachment("markings")
		if string.find(layer.assetId, ".speckled", 1, true) ~= nil then
			for index, offset in { -0.19, 0, 0.19 } do
				addPart(handle.placeholder, `Speckle{index}`, {
					x = area.x + offset * area.width,
					y = area.y + (if index == 2 then 0.09 else -0.08) * area.height,
					width = area.width * 0.13,
					height = area.width * 0.13,
					rotation = 0,
				}, colors.marking, z)
			end
		else
			for index, offset in { -0.18, 0.18 } do
				addPart(handle.placeholder, `BodyStripe{index}`, {
					x = area.x,
					y = area.y + offset * area.height,
					width = area.width * 0.72,
					height = area.height * 0.12,
					rotation = if index == 1 then -7 else 7,
				}, colors.marking, z, 0.08)
			end
		end
	elseif layer.slot == "eyes" then
		local wide = string.find(layer.assetId, ".wide", 1, true) ~= nil
		for _, name in { "leftEye", "rightEye" } do
			local eyeAttachment =
				attachment(name, if wide then 1.35 else 1, if wide then 1.2 else 1)
			local eye = outlined(
				if name == "leftEye" then "LeftEye" else "RightEye",
				eyeAttachment,
				colors.eye
			)
			local pupil = Instance.new("Frame")
			pupil.Name = "Pupil"
			pupil.AnchorPoint = Vector2.new(0.5, 0.5)
			pupil.BackgroundColor3 = colors.pupil
			pupil.BorderSizePixel = 0
			pupil.Position = UDim2.fromScale(if facing == "LEFT" then 0.42 else 0.58, 0.56)
			pupil.Size = UDim2.fromScale(0.38, 0.46)
			pupil.ZIndex = z + 1
			pupil.Parent = eye
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(1, 0)
			corner.Parent = pupil
		end
	elseif layer.slot == "mouth" then
		addPart(handle.placeholder, "Mouth", attachment("mouth"), colors.mouth, z)
	elseif layer.slot == "accessories" then
		local base = attachment("accessory")
		if string.find(layer.assetId, ".sprout", 1, true) ~= nil then
			addPart(handle.placeholder, "SproutStem", {
				x = base.x,
				y = base.y + base.height * 0.18,
				width = base.width * 0.08,
				height = base.height * 0.85,
				rotation = 0,
			}, colors.marking, z)
			outlined("SproutLeafLeft", {
				x = base.x - base.width * 0.16,
				y = base.y - base.height * 0.12,
				width = base.width * 0.42,
				height = base.height * 0.38,
				rotation = -25,
			}, colors.belly, 1)
			outlined("SproutLeafRight", {
				x = base.x + base.width * 0.16,
				y = base.y - base.height * 0.12,
				width = base.width * 0.42,
				height = base.height * 0.38,
				rotation = 25,
			}, colors.belly, 1)
		else
			outlined("AccessoryBand", {
				x = base.x,
				y = base.y + base.height * 0.72,
				width = base.width * 0.72,
				height = base.height * 0.22,
				rotation = 0,
			}, colors.accessory)
		end
	end
end

function CritterSpriteRig.mount(parent: Instance, props: Props)
	local root = Instance.new("Frame")
	root.Name = "CritterSpriteRig"
	root.BackgroundTransparency = 1
	root.ClipsDescendants = true
	root.Size = props.size or UDim2.fromScale(1, 1)
	root.Parent = parent

	local canvas = Instance.new("CanvasGroup")
	canvas.Name = "RigCanvas"
	canvas.AnchorPoint = Vector2.new(0.5, 0.5)
	canvas.BackgroundTransparency = 1
	canvas.ClipsDescendants = true
	canvas.Position = UDim2.fromScale(0.5, 0.5)
	canvas.Size = UDim2.fromScale(0.94, 0.94)
	canvas.Parent = root
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.Parent = canvas

	local function updateAspect()
		aspect.DominantAxis = if root.AbsoluteSize.X > root.AbsoluteSize.Y
			then Enum.DominantAxis.Height
			else Enum.DominantAxis.Width
	end
	local sizeConnection = root:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateAspect)
	updateAspect()

	local layerHandles = {}
	local debugLayers = {}
	local animation = CritterAnimationController.new(canvas)

	local function createLayer(slot: string)
		local host = Instance.new("Frame")
		host.Name = `Layer_{slot}`
		host.BackgroundTransparency = 1
		host.Size = UDim2.fromScale(1, 1)
		host.Parent = canvas
		local placeholder = Instance.new("Frame")
		placeholder.Name = "PlaceholderParts"
		placeholder.BackgroundTransparency = 1
		placeholder.Size = UDim2.fromScale(1, 1)
		placeholder.Parent = host
		local image = Instance.new("ImageLabel")
		image.Name = "Image"
		image.BackgroundTransparency = 1
		image.Size = UDim2.fromScale(1, 1)
		image.ScaleType = Enum.ScaleType.Fit
		image.Visible = false
		image.Parent = host
		local handle = { host = host, placeholder = placeholder, image = image, renderKey = nil }
		layerHandles[slot] = handle
		return handle
	end

	local function applySpritePlacement(image: ImageLabel, sprite, facing: string)
		image.ImageRectOffset = Vector2.zero
		image.ImageRectSize = Vector2.zero
		image.Rotation = 0
		if sprite == nil then
			image.AnchorPoint = Vector2.zero
			image.Position = UDim2.fromScale(0, 0)
			image.Size = UDim2.fromScale(1, 1)
			return
		end
		local pivotX = if facing == "LEFT" then 1 - sprite.pivot.x else sprite.pivot.x
		local positionX = if facing == "LEFT" then 1 - sprite.position.x else sprite.position.x
		image.AnchorPoint = Vector2.new(pivotX, sprite.pivot.y)
		image.Position = UDim2.fromScale(positionX, sprite.position.y)
		image.Size = UDim2.fromScale(sprite.size.width, sprite.size.height)
	end

	local function update(nextProps: Props)
		local model = resolveModel(nextProps)
		root.Size = nextProps.size or UDim2.fromScale(1, 1)
		canvas:SetAttribute("Facing", model.facing)
		canvas:SetAttribute("RigFamily", model.rigFamily)
		canvas:SetAttribute("SpriteRigId", model.spriteRigId)
		root:SetAttribute("Facing", model.facing)
		root:SetAttribute("RigFamily", model.rigFamily)
		root:SetAttribute("SpriteRigId", model.spriteRigId)
		animation.configure(model.spriteRigId, model.animation)
		local used = {}
		local nextDebugLayers = {}
		for _, layer in model.layers do
			used[layer.slot] = true
			local handle = layerHandles[layer.slot] or createLayer(layer.slot)
			handle.host.ZIndex = layer.order + 1
			handle.placeholder.ZIndex = layer.order + 1
			handle.image.ZIndex = layer.order + 1
			local asset = nextProps.resolveAsset(layer.assetId)
			applySpritePlacement(handle.image, asset.sprite, model.facing)
			handle.image.Image = asset.image or ""
			handle.image.Visible = asset.image ~= nil and not asset.isPlaceholder
			handle.placeholder.Visible = not handle.image.Visible
			local renderKey = `{model.spriteRigId}|{model.facing}|{layer.assetId}`
			if handle.placeholder.Visible and handle.renderKey ~= renderKey then
				handle.renderKey = renderKey
				renderPlaceholder(handle, layer, model)
			end
			handle.host.Visible = layer.visible
			table.insert(nextDebugLayers, {
				slot = layer.slot,
				assetId = asset.requestedId,
				resolvedId = asset.resolvedId,
				isPlaceholder = asset.isPlaceholder,
				importSlot = asset.importSlot,
			})
		end
		for slot, handle in layerHandles do
			handle.host.Visible = used[slot] == true
		end
		debugLayers = nextDebugLayers
	end

	update(props)
	return table.freeze({
		instance = root,
		update = update,
		play = animation.play,
		animationState = animation.state,
		debugLayers = function()
			return table.clone(debugLayers)
		end,
		setSheetFrame = function(slot: string, sheetAssetId: string, frame)
			local handle = layerHandles[slot]
			if handle == nil then
				return
			end
			handle.image.Image = sheetAssetId
			handle.image.ImageRectOffset = Vector2.new(frame.x, frame.y)
			handle.image.ImageRectSize = Vector2.new(frame.width, frame.height)
			handle.image.Visible = true
			handle.placeholder.Visible = false
		end,
		destroy = function()
			sizeConnection:Disconnect()
			animation.destroy()
			root:Destroy()
		end,
	})
end

return table.freeze(CritterSpriteRig)
