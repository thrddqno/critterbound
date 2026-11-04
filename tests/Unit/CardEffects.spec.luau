--!strict

return function(Harness)
	local BattleEvents = require("../../src/shared/Battle/BattleEvents")
	local CardEffectResolver = require("../../src/shared/Battle/CardEffectResolver")
	local StatusEffects = require("../../src/shared/Battle/StatusEffects")

	local function combatant(id, class, health)
		return {
			id = id,
			class = class,
			stats = { maxHealth = 100, health = 25, speed = 20, skill = 3, morale = 3 },
			currentHealth = health,
			statusEffects = {},
			shields = {},
		}
	end

	local function context()
		return {
			factory = BattleEvents.create("battle.effects.fixture", 0),
			events = {},
		}
	end

	local function kinds(events)
		local result = {}
		for _, event in events do
			table.insert(result, event.kind)
		end
		return result
	end

	Harness.test("healing restores HP and clamps to maximum", function()
		local source = combatant("source", "Verdant", 100)
		local target = combatant("target", "Verdant", 50)
		local definition = {
			id = "card.heal",
			class = "Verdant",
			effects = { { kind = "HEAL", amount = 30 } },
		}
		local ctx = context()
		local defeated = CardEffectResolver.applyCard(
			source,
			{ "target" },
			definition,
			{ target = target },
			1,
			ctx.factory,
			ctx.events
		)
		Harness.equal(#defeated, 0)
		Harness.equal(target.currentHealth, 80)
		Harness.equal(ctx.events[1].payload.restored, 30)

		target.currentHealth = 90
		ctx = context()
		CardEffectResolver.applyCard(
			source,
			{ "target" },
			definition,
			{ target = target },
			1,
			ctx.factory,
			ctx.events
		)
		Harness.equal(target.currentHealth, 100)
		Harness.equal(ctx.events[1].payload.restored, 10)
	end)

	Harness.test("healing rejects defeated targets and never revives", function()
		local source = combatant("source", "Verdant", 100)
		local target = combatant("target", "Verdant", 0)
		local definition = {
			id = "card.heal",
			class = "Verdant",
			effects = { { kind = "HEAL", amount = 30 } },
		}
		local ctx = context()
		CardEffectResolver.applyCard(
			source,
			{ "target" },
			definition,
			{ target = target },
			1,
			ctx.factory,
			ctx.events
		)
		Harness.equal(target.currentHealth, 0)
		Harness.equal(ctx.events[1].payload.rejected, true)
		Harness.equal(ctx.events[1].payload.reason, "TARGET_DEFEATED")
	end)

	Harness.test("shields stack and absorb damage before HP", function()
		local source = combatant("source", "Stone", 100)
		local target = combatant("target", "Stone", 100)
		local shieldDefinition = {
			id = "card.shield",
			class = "Stone",
			effects = { { kind = "SHIELD", amount = 20 } },
		}
		local ctx = context()
		CardEffectResolver.applyCard(
			source,
			{ "target" },
			shieldDefinition,
			{ target = target },
			1,
			ctx.factory,
			ctx.events
		)
		Harness.equal(target.shields[1].amount, 22)
		Harness.equal(ctx.events[1].payload.sameClassMultiplier, 1.1)
		CardEffectResolver.applyCard(
			source,
			{ "target" },
			shieldDefinition,
			{ target = target },
			1,
			ctx.factory,
			ctx.events
		)
		Harness.equal(#target.shields, 2)

		local attackDefinition = {
			id = "card.attack",
			class = "Stone",
			effects = { { kind = "DAMAGE", amount = 30 } },
		}
		ctx = context()
		CardEffectResolver.applyCard(
			source,
			{ "target" },
			attackDefinition,
			{ target = target },
			1,
			ctx.factory,
			ctx.events
		)
		Harness.equal(target.currentHealth, 100)
		Harness.equal(#target.shields, 1)
		Harness.equal(target.shields[1].amount, 11)
		Harness.deepEqual(kinds(ctx.events), { "SHIELD_ABSORBED", "DAMAGE_APPLIED" })

		StatusEffects.expire({ target }, 1, ctx.factory, ctx.events)
		Harness.equal(#target.shields, 0)
	end)

	Harness.test("cross-class shields receive no same-class bonus", function()
		local source = combatant("source", "Feral", 100)
		local target = combatant("target", "Stone", 100)
		local ctx = context()
		CardEffectResolver.applyCard(source, { "target" }, {
			id = "card.cross-shield",
			class = "Stone",
			effects = { { kind = "SHIELD", amount = 20 } },
		}, { target = target }, 1, ctx.factory, ctx.events)
		Harness.equal(target.shields[1].amount, 20)
		Harness.equal(ctx.events[1].payload.sameClassMultiplier, 1.0)
	end)

	Harness.test("lethal damage defeats at zero with no Last Stand and clamps excess", function()
		local source = combatant("source", "Feral", 100)
		local target = combatant("target", "Stone", 5)
		local definition = {
			id = "card.attack",
			class = "Feral",
			effects = { { kind = "DAMAGE", amount = 30 } },
		}
		local ctx = context()
		local defeated = CardEffectResolver.applyCard(
			source,
			{ "target" },
			definition,
			{ target = target },
			1,
			ctx.factory,
			ctx.events
		)
		Harness.deepEqual(defeated, { "target" })
		Harness.equal(target.currentHealth, 0)
		Harness.equal(ctx.events[1].payload.hpDamage, 5)

		local healthy = combatant("healthy", "Stone", 100)
		local zeroDefinition = {
			id = "card.zero",
			class = "Stone",
			effects = { { kind = "DAMAGE", amount = 0 } },
		}
		ctx = context()
		defeated = CardEffectResolver.applyCard(
			source,
			{ "healthy" },
			zeroDefinition,
			{ healthy = healthy },
			1,
			ctx.factory,
			ctx.events
		)
		Harness.equal(#defeated, 0)
		Harness.equal(healthy.currentHealth, 100)
		Harness.equal(ctx.events[1].payload.hpDamage, 0)
	end)

	Harness.test(
		"multiple effects execute in authored order without mutating definitions",
		function()
			local source = combatant("source", "Shade", 100)
			local target = combatant("target", "Tide", 100)
			local definition = {
				id = "card.combo",
				class = "Shade",
				effects = {
					{ kind = "DAMAGE", amount = 10 },
					{ kind = "STATUS", statusId = "DAMAGE_DOWN", magnitude = 5, duration = 2 },
				},
			}
			local before = Harness.clone(definition)
			local ctx = context()
			CardEffectResolver.applyCard(
				source,
				{ "target" },
				definition,
				{ target = target },
				1,
				ctx.factory,
				ctx.events
			)
			Harness.deepEqual(kinds(ctx.events), { "DAMAGE_APPLIED", "STATUS_APPLIED" })
			Harness.equal(#target.statusEffects, 1)
			Harness.deepEqual(definition, before)
		end
	)

	Harness.test("only living direct-damage targets consume critical rolls", function()
		local source = combatant("source", "Feral", 100)
		local living = combatant("living", "Stone", 100)
		local defeated = combatant("defeated", "Stone", 0)
		local rollCount = 0
		local function rollCritical()
			rollCount += 1
			return true
		end
		local ctx = context()
		CardEffectResolver.applyCard(
			source,
			{ "living", "defeated", "missing" },
			{
				id = "card.direct",
				class = "Feral",
				effects = { { kind = "DAMAGE", amount = 0 } },
			},
			{ living = living, defeated = defeated },
			1,
			ctx.factory,
			ctx.events,
			{
				rollCritical = rollCritical,
			}
		)
		Harness.equal(rollCount, 1)
		Harness.equal(ctx.events[1].payload.damageBeforeShield, 0)
		Harness.expect(not ctx.events[1].payload.isCritical)
	end)

	Harness.test("healing shields and statuses never consume critical rolls", function()
		local source = combatant("source", "Verdant", 100)
		local target = combatant("target", "Verdant", 50)
		local rollCount = 0
		local ctx = context()
		CardEffectResolver.applyCard(
			source,
			{ "target" },
			{
				id = "card.non-damage",
				class = "Verdant",
				effects = {
					{ kind = "HEAL", amount = 5 },
					{ kind = "SHIELD", amount = 5 },
					{ kind = "STATUS", statusId = "POISON", magnitude = 1, duration = 1 },
				},
			},
			{ target = target },
			1,
			ctx.factory,
			ctx.events,
			{
				rollCritical = function()
					rollCount += 1
					return true
				end,
			}
		)
		Harness.equal(rollCount, 0)
	end)

	Harness.test("triggered damage requires explicit critical eligibility", function()
		local source = combatant("source", "Shade", 100)
		local target = combatant("target", "Tide", 100)
		local rollCount = 0
		local function apply(effect)
			local ctx = context()
			CardEffectResolver.applyCard(
				source,
				{ "target" },
				{
					id = "card.triggered",
					class = "Shade",
					effects = { effect },
				},
				{ target = target },
				1,
				ctx.factory,
				ctx.events,
				{
					rollCritical = function()
						rollCount += 1
						return false
					end,
				}
			)
		end
		apply({ kind = "DAMAGE", amount = 1, triggered = true })
		Harness.equal(rollCount, 0)
		apply({ kind = "DAMAGE", amount = 1, triggered = true, criticalEligible = true })
		Harness.equal(rollCount, 1)
	end)
end
