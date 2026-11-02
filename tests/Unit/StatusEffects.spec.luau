--!strict

return function(Harness)
	local BattleEvents = require("../../src/shared/Battle/BattleEvents")
	local StatusEffects = require("../../src/shared/Battle/StatusEffects")

	local function combatant(overrides)
		local value = {
			id = "combatant.test",
			stats = { maxHealth = 100, attack = 20, defense = 20, speed = 20 },
			currentHealth = 100,
			statusEffects = {},
			shields = {},
		}
		for key, child in overrides or {} do
			value[key] = child
		end
		return value
	end

	local function context()
		return {
			factory = BattleEvents.create("battle.status.fixture", 0),
			events = {},
		}
	end

	Harness.test("poison ticks at round end, bypasses shields, and expires", function()
		local target = combatant()
		target.shields =
			{ { id = "shield.1", sourceCombatantId = "source", amount = 100, expiresAtRound = 1 } }
		local ctx = context()

		Harness.expect(
			StatusEffects.apply(target, "POISON", 5, 2, "source", 1, ctx.factory, ctx.events)
		)
		Harness.equal(target.statusEffects[1].expiresAtRound, 2)

		local defeated = StatusEffects.tickPoison({ target }, 1, ctx.factory, ctx.events)
		Harness.equal(#defeated, 0)
		Harness.equal(target.currentHealth, 95)
		Harness.equal(target.shields[1].amount, 100)

		defeated = StatusEffects.tickPoison({ target }, 2, ctx.factory, ctx.events)
		Harness.equal(#defeated, 0)
		Harness.equal(target.currentHealth, 90)

		StatusEffects.expire({ target }, 2, ctx.factory, ctx.events)
		Harness.equal(#target.statusEffects, 0)
		Harness.equal(#target.shields, 0)
	end)

	Harness.test("poison can defeat a Critter", function()
		local target = combatant({ currentHealth = 5 })
		local ctx = context()
		StatusEffects.apply(target, "POISON", 5, 1, "source", 1, ctx.factory, ctx.events)
		local defeated = StatusEffects.tickPoison({ target }, 1, ctx.factory, ctx.events)
		Harness.equal(#defeated, 1)
		Harness.equal(defeated[1], target.id)
		Harness.equal(target.currentHealth, 0)
	end)

	Harness.test("poison stacks up to its cap", function()
		local target = combatant()
		local ctx = context()
		for _ = 1, 6 do
			StatusEffects.apply(target, "POISON", 5, 2, "source", 1, ctx.factory, ctx.events)
		end
		Harness.equal(#target.statusEffects, 1)
		Harness.equal(target.statusEffects[1].stackCount, 5)
		StatusEffects.tickPoison({ target }, 1, ctx.factory, ctx.events)
		Harness.equal(target.currentHealth, 75)
	end)

	Harness.test("status duration counts the application round", function()
		local target = combatant()
		local ctx = context()
		StatusEffects.apply(target, "ATTACK_UP", 10, 2, "source", 1, ctx.factory, ctx.events)
		StatusEffects.expire({ target }, 1, ctx.factory, ctx.events)
		Harness.equal(#target.statusEffects, 1)
		StatusEffects.expire({ target }, 2, ctx.factory, ctx.events)
		Harness.equal(#target.statusEffects, 0)
	end)

	Harness.test("speed and attack modifiers stack deterministically", function()
		local target = combatant()
		target.statusEffects = {
			{
				id = "status.1",
				statusId = "SPEED_UP",
				sourceCombatantId = "source",
				targetCombatantId = target.id,
				magnitude = 10,
				duration = 2,
				stackCount = 2,
				appliedRound = 1,
				expiresAtRound = 2,
			},
			{
				id = "status.2",
				statusId = "SPEED_DOWN",
				sourceCombatantId = "source",
				targetCombatantId = target.id,
				magnitude = 5,
				duration = 2,
				stackCount = 1,
				appliedRound = 1,
				expiresAtRound = 2,
			},
			{
				id = "status.3",
				statusId = "ATTACK_UP",
				sourceCombatantId = "source",
				targetCombatantId = target.id,
				magnitude = 10,
				duration = 2,
				stackCount = 2,
				appliedRound = 1,
				expiresAtRound = 2,
			},
		}
		Harness.equal(StatusEffects.effectiveSpeed(target), 35)
		Harness.equal(StatusEffects.effectiveAttack(target), 40)
		Harness.equal(StatusEffects.attackModifier(target), 20)
	end)

	Harness.test("unknown status identifiers are rejected", function()
		local target = combatant()
		local ctx = context()
		Harness.expect(
			not StatusEffects.apply(target, "UNKNOWN", 1, 1, "source", 1, ctx.factory, ctx.events)
		)
		Harness.equal(#target.statusEffects, 0)
	end)
end
