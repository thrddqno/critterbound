--!strict

-- Import slots only. Add reviewed Roblox image URIs here after transparent PNG layers are supplied.
-- Every layer is authored on the same 1024x1024 canvas and aligned to Bloom's ground pivot.
local function sprite(slot: string, pivotX: number, pivotY: number)
	return {
		slot = slot,
		canvasSize = { width = 1024, height = 1024 },
		pivot = { x = pivotX, y = pivotY },
		position = { x = pivotX, y = pivotY },
		size = { width = 1, height = 1 },
	}
end

return table.freeze({
	{
		id = "creature.structural.shadow.verdant",
		category = "CREATURE_LAYER",
		importSlot = "bloom/shadow.png",
		sprite = sprite("shadow", 0.5, 0.88),
	},
	{
		id = "creature.layer.tail.verdant.default",
		category = "CREATURE_LAYER",
		importSlot = "bloom/tail_default.png",
		sprite = sprite("tail", 0.5, 0.88),
	},
	{
		id = "creature.layer.wings.verdant.default",
		category = "CREATURE_LAYER",
		importSlot = "bloom/wings_default.png",
		sprite = sprite("wings", 0.5, 0.88),
	},
	{
		id = "creature.verdant.default",
		category = "CREATURE_BASE",
		importSlot = "bloom/body_default.png",
		sprite = sprite("body", 0.5, 0.88),
	},
	{
		id = "creature.layer.color.verdant.default",
		category = "CREATURE_LAYER",
		importSlot = "bloom/color_default.png",
		sprite = sprite("color", 0.5, 0.88),
	},
	{
		id = "creature.layer.markings.verdant.default",
		category = "CREATURE_LAYER",
		importSlot = "bloom/markings_default.png",
		sprite = sprite("markings", 0.5, 0.88),
	},
	{
		id = "creature.layer.eyes.verdant.default",
		category = "CREATURE_LAYER",
		importSlot = "bloom/eyes_default.png",
		sprite = sprite("eyes", 0.5, 0.88),
	},
	{
		id = "creature.structural.mouth.verdant",
		category = "CREATURE_LAYER",
		importSlot = "bloom/mouth_default.png",
		sprite = sprite("mouth", 0.5, 0.88),
	},
	{
		id = "creature.layer.accessories.verdant.default",
		category = "CREATURE_LAYER",
		importSlot = "bloom/accessory_default.png",
		sprite = sprite("accessories", 0.5, 0.88),
	},
})
