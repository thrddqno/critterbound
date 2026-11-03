--!strict

local AssetRegistry = require(script.Parent.AssetRegistry)
local BloomSpriteManifest = require(script.Parent.BloomSpriteManifest)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GeneRegistry = require(ReplicatedStorage.Shared.Genetics.GeneRegistry)

-- Entries intentionally omit Roblox asset IDs until final art is supplied.
local entries = {}
for _, entry in BloomSpriteManifest do
	table.insert(entries, entry)
end
for _, entry in
	{
		{ id = "creature.stone.default", category = "CREATURE_BASE" },
		{ id = "creature.feral.default", category = "CREATURE_BASE" },
		{ id = "creature.tide.default", category = "CREATURE_BASE" },
		{ id = "creature.gale.default", category = "CREATURE_BASE" },
		{ id = "creature.shade.default", category = "CREATURE_BASE" },
		{ id = "card.stone.guard", category = "CARD_ART" },
		{ id = "card.feral.strike", category = "CARD_ART" },
		{ id = "card.verdant.mend", category = "CARD_ART" },
		{ id = "arena.training.background", category = "BATTLEFIELD_BACKGROUND" },
		{ id = "icon.class.stone", category = "CLASS_ICON" },
		{ id = "icon.class.feral", category = "CLASS_ICON" },
		{ id = "icon.class.verdant", category = "CLASS_ICON" },
		{ id = "item.equipment.training_charm", category = "EQUIPMENT_ICON" },
		{ id = "item.material.iron_shard", category = "EQUIPMENT_ICON" },
	}
do
	table.insert(entries, entry)
end

local known = {}
for _, entry in entries do
	known[entry.id] = true
end
for _, definition in GeneRegistry.allById() do
	if
		definition.kind == "APPEARANCE"
		and definition.assetId ~= nil
		and not known[definition.assetId]
	then
		table.insert(entries, { id = definition.assetId, category = "CREATURE_LAYER" })
		known[definition.assetId] = true
	end
end
for _, rigFamily in { "stone", "feral", "verdant", "tide", "gale", "shade" } do
	for _, slot in { "shadow", "mouth" } do
		local id = `creature.structural.{slot}.{rigFamily}`
		if not known[id] then
			table.insert(entries, { id = id, category = "CREATURE_LAYER" })
			known[id] = true
		end
	end
	for _, animationId in { "idle", "attack", "hit", "defeat" } do
		local id = `creature.animation.{rigFamily}.{animationId}`
		if not known[id] then
			table.insert(entries, { id = id, category = "CREATURE_ANIMATION" })
			known[id] = true
		end
	end
end

return AssetRegistry.new(entries)
