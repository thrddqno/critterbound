--!strict

local function requireRendering(name: string)
	if script ~= nil then
		return require(script.Parent[name])
	end
	return require(`./{name}`)
end

local SpriteRigCatalog = requireRendering("SpriteRigCatalog")
local CritterSpriteModel = {}

local ORDER = table.freeze({
	shadow = 0,
	tail = 5,
	wings = 8,
	body = 10,
	color = 15,
	markings = 20,
	eyes = 50,
	mouth = 60,
	accessories = 70,
})

local function layer(rig, slot: string, assetId: string, placeholder: boolean?)
	local pivot = SpriteRigCatalog.pivot(rig.id, slot)
	return {
		id = slot,
		slot = slot,
		assetId = assetId,
		order = rig.layerOrder[slot] or ORDER[slot],
		anchor = pivot,
		pivot = pivot,
		visible = true,
		placeholder = placeholder,
	}
end

function CritterSpriteModel.build(appearance, facing: string?)
	assert(type(appearance) == "table", "Resolved appearance required")
	local rigFamily = appearance.bodyRigFamily or "round"
	local spriteRigId = appearance.spriteRigId or rigFamily
	local rig = SpriteRigCatalog.get(spriteRigId)
	local bySlot = {}
	for _, value in appearance.layers or {} do
		bySlot[value.slot] = value
	end
	local layers = {
		layer(rig, "shadow", `creature.structural.shadow.{rig.id}`, true),
		layer(rig, "body", appearance.baseAssetId, false),
	}
	for _, slot in { "color", "markings", "tail", "wings", "eyes" } do
		local value = bySlot[slot]
		if value ~= nil then
			table.insert(layers, layer(rig, slot, value.assetId, false))
		end
	end
	table.insert(layers, layer(rig, "mouth", `creature.structural.mouth.{rig.id}`, true))
	if bySlot.accessories ~= nil then
		table.insert(layers, layer(rig, "accessories", bySlot.accessories.assetId, false))
	end
	table.sort(layers, function(a, b)
		return a.order < b.order
	end)
	return {
		rigFamily = rigFamily,
		spriteRigId = rig.id,
		style = rig.style,
		palette = rig.palette,
		animation = rig.animation,
		facing = if facing == "LEFT" then "LEFT" else "RIGHT",
		nativeSize = rig.nativeSize,
		attachments = rig.attachments,
		layers = layers,
	}
end

CritterSpriteModel.LayerOrder = ORDER
return table.freeze(CritterSpriteModel)
