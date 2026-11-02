--!strict

local AssetRegistry = require(script.Parent.AssetRegistry)

-- Entries intentionally omit Roblox asset IDs during architecture-only Run 3.
return AssetRegistry.new({
	{ id = "creature.stone.default", category = "CREATURE_BASE" },
	{ id = "creature.feral.default", category = "CREATURE_BASE" },
	{ id = "creature.verdant.default", category = "CREATURE_BASE" },
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
})
