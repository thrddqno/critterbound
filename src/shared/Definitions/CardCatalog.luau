--!strict

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

local function card(id, className, cost, target, description, effects)
	return {
		schemaVersion = 1,
		id = `card.training.{id}`,
		displayName = string.gsub(id, "^%l", string.upper),
		class = className,
		abilityId = id,
		energyCost = cost,
		targetingRule = target,
		description = description,
		effects = effects,
	}
end

local cards = {
	card(
		"stone.guard",
		"Stone",
		1,
		"SELF",
		"Gain 22 shield.",
		{ { kind = "SHIELD", amount = 22 } }
	),
	card(
		"stone.bulwark",
		"Stone",
		2,
		"ALL_ALLIES",
		"All allies gain 10 shield.",
		{ { kind = "SHIELD", amount = 10 } }
	),
	card(
		"stone.quake",
		"Stone",
		2,
		"ALL_ENEMIES",
		"Deal 18 damage to all enemies.",
		{ { kind = "DAMAGE", amount = 18 } }
	),
	card(
		"stone.slam",
		"Stone",
		1,
		"FRONT_ENEMY",
		"Deal 32 damage to front enemy.",
		{ { kind = "DAMAGE", amount = 32 } }
	),
	card(
		"feral.strike",
		"Feral",
		1,
		"ENEMY",
		"Deal 38 damage to slowest enemy.",
		{ { kind = "DAMAGE", amount = 38 } }
	),
	card(
		"feral.pounce",
		"Feral",
		1,
		"FRONT_ENEMY",
		"Deal 34 damage to front enemy.",
		{ { kind = "DAMAGE", amount = 34 } }
	),
	card(
		"feral.frenzy",
		"Feral",
		1,
		"SELF",
		"Gain Attack Up for 2 rounds.",
		{ { kind = "STATUS", statusId = "ATTACK_UP", magnitude = 8, duration = 2 } }
	),
	card("feral.rend", "Feral", 2, "ENEMY", "Damage and poison slowest enemy.", {
		{ kind = "DAMAGE", amount = 25 },
		{ kind = "STATUS", statusId = "POISON", magnitude = 4, duration = 2 },
	}),
	card(
		"verdant.mend",
		"Verdant",
		1,
		"ALLY",
		"Heal an ally for 28.",
		{ { kind = "HEAL", amount = 28 } }
	),
	card(
		"verdant.renew",
		"Verdant",
		1,
		"SELF",
		"Heal self for 24.",
		{ { kind = "HEAL", amount = 24 } }
	),
	card(
		"verdant.grove",
		"Verdant",
		2,
		"ALL_ALLIES",
		"Heal all allies for 15.",
		{ { kind = "HEAL", amount = 15 } }
	),
	card(
		"verdant.seed",
		"Verdant",
		1,
		"ENEMY",
		"Poison slowest enemy for 2 rounds.",
		{ { kind = "STATUS", statusId = "POISON", magnitude = 6, duration = 2 } }
	),
	card(
		"tide.mend",
		"Tide",
		1,
		"ALLY",
		"Heal an ally for 26.",
		{ { kind = "HEAL", amount = 26 } }
	),
	card("tide.renew", "Tide", 1, "SELF", "Heal self for 22.", { { kind = "HEAL", amount = 22 } }),
	card(
		"tide.barrier",
		"Tide",
		2,
		"ALL_ALLIES",
		"All allies gain 9 shield.",
		{ { kind = "SHIELD", amount = 9 } }
	),
	card(
		"tide.surge",
		"Tide",
		1,
		"ENEMY",
		"Deal 42 damage to slowest enemy.",
		{ { kind = "DAMAGE", amount = 42 } }
	),
	card("gale.ward", "Gale", 1, "SELF", "Gain 20 shield.", { { kind = "SHIELD", amount = 20 } }),
	card(
		"gale.shelter",
		"Gale",
		2,
		"ALL_ALLIES",
		"All allies gain 8 shield.",
		{ { kind = "SHIELD", amount = 8 } }
	),
	card(
		"gale.gust",
		"Gale",
		1,
		"ENEMY",
		"Deal 40 damage to slowest enemy.",
		{ { kind = "DAMAGE", amount = 40 } }
	),
	card(
		"gale.haste",
		"Gale",
		1,
		"SELF",
		"Gain Speed Up for 2 rounds.",
		{ { kind = "STATUS", statusId = "SPEED_UP", magnitude = 8, duration = 2 } }
	),
	card(
		"shade.bite",
		"Shade",
		1,
		"ENEMY",
		"Deal 48 damage to slowest enemy.",
		{ { kind = "DAMAGE", amount = 48 } }
	),
	card(
		"shade.toxin",
		"Shade",
		1,
		"ENEMY",
		"Poison slowest enemy for 2 rounds.",
		{ { kind = "STATUS", statusId = "POISON", magnitude = 8, duration = 2 } }
	),
	card(
		"shade.weaken",
		"Shade",
		1,
		"ENEMY",
		"Weaken slowest enemy for 2 rounds.",
		{ { kind = "STATUS", statusId = "ATTACK_DOWN", magnitude = 6, duration = 2 } }
	),
	card(
		"shade.storm",
		"Shade",
		2,
		"ALL_ENEMIES",
		"Deal 22 damage to all enemies.",
		{ { kind = "DAMAGE", amount = 22 } }
	),
	card(
		"stone.rampart",
		"Stone",
		2,
		"ALL_ALLIES",
		"All allies gain 12 shield.",
		{ { kind = "SHIELD", amount = 12 } }
	),
	card("stone.crush", "Stone", 2, "FRONT_ENEMY", "Damage and weaken front enemy.", {
		{ kind = "DAMAGE", amount = 24 },
		{ kind = "STATUS", statusId = "ATTACK_DOWN", magnitude = 5, duration = 2 },
	}),
	card("feral.maul", "Feral", 1, "ENEMY", "Damage and poison slowest enemy.", {
		{ kind = "DAMAGE", amount = 30 },
		{ kind = "STATUS", statusId = "POISON", magnitude = 4, duration = 2 },
	}),
	card(
		"feral.fury",
		"Feral",
		2,
		"SELF",
		"Gain Attack Up for 3 rounds.",
		{ { kind = "STATUS", statusId = "ATTACK_UP", magnitude = 10, duration = 3 } }
	),
	card(
		"verdant.bloom",
		"Verdant",
		2,
		"ALL_ALLIES",
		"Heal all allies for 18.",
		{ { kind = "HEAL", amount = 18 } }
	),
	card("verdant.bramble", "Verdant", 2, "FRONT_ENEMY", "Damage and poison front enemy.", {
		{ kind = "DAMAGE", amount = 16 },
		{ kind = "STATUS", statusId = "POISON", magnitude = 5, duration = 2 },
	}),
	card(
		"tide.torrent",
		"Tide",
		2,
		"ALL_ENEMIES",
		"Deal 20 damage to all enemies.",
		{ { kind = "DAMAGE", amount = 20 } }
	),
	card("tide.purge", "Tide", 1, "ALLY", "Heal an ally for 24 and grant 8 shield.", {
		{ kind = "HEAL", amount = 24 },
		{ kind = "SHIELD", amount = 8 },
	}),
	card(
		"gale.squall",
		"Gale",
		2,
		"ALL_ENEMIES",
		"Deal 17 damage to all enemies.",
		{ { kind = "DAMAGE", amount = 17 } }
	),
	card(
		"gale.tailwind",
		"Gale",
		1,
		"SELF",
		"Gain Speed Up for 3 rounds.",
		{ { kind = "STATUS", statusId = "SPEED_UP", magnitude = 10, duration = 3 } }
	),
	card(
		"shade.curse",
		"Shade",
		1,
		"ENEMY",
		"Weaken slowest enemy for 3 rounds.",
		{ { kind = "STATUS", statusId = "ATTACK_DOWN", magnitude = 5, duration = 3 } }
	),
	card("shade.terror", "Shade", 2, "ALL_ENEMIES", "Damage and weaken all enemies.", {
		{ kind = "DAMAGE", amount = 16 },
		{ kind = "STATUS", statusId = "ATTACK_DOWN", magnitude = 4, duration = 2 },
	}),
}

local byId = {}
local byAbilityId = {}
for _, definition in cards do
	byId[definition.id] = definition
	byAbilityId[definition.abilityId] = definition
end

return table.freeze({
	getById = function(id: string)
		return if byId[id] == nil then nil else clone(byId[id])
	end,
	getByAbilityId = function(id: string)
		return if byAbilityId[id] == nil then nil else clone(byAbilityId[id])
	end,
	allById = function()
		return clone(byId)
	end,
})
