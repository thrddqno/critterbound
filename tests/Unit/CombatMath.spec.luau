--!strict

return function(Harness)
	local ClassAdvantage = require("../../src/shared/Battle/ClassAdvantage")
	local CardCatalog = require("../../src/shared/Definitions/CardCatalog")
	local DamageCalculator = require("../../src/shared/Battle/DamageCalculator")

	local function combatant(class, overrides)
		local stats = {
			maxHealth = 100,
			health = 25,
			speed = 20,
			skill = 3,
			morale = 3,
		}
		for key, value in overrides or {} do
			stats[key] = value
		end
		return {
			id = `combatant.{class}`,
			class = class,
			stats = stats,
			currentHealth = stats.maxHealth,
			statusEffects = {},
			shields = {},
		}
	end

	local function source(class, skill)
		return combatant(class, { skill = skill or 0 })
	end

	Harness.test("class ring awards advantage, disadvantage, and neutral", function()
		Harness.equal(ClassAdvantage.multiplier("Verdant", "Tide"), 1.15)
		Harness.equal(ClassAdvantage.multiplier("Feral", "Gale"), 1.15)
		Harness.equal(ClassAdvantage.multiplier("Feral", "Tide"), 0.85)
		Harness.equal(ClassAdvantage.multiplier("Feral", "Stone"), 1.0)
		Harness.equal(ClassAdvantage.multiplier("Feral", "Feral"), 1.0)
		Harness.equal(ClassAdvantage.multiplier("Unknown", "Tide"), 1.0)
	end)

	Harness.test("ordinary damage ignores retired Attack and Defense stats", function()
		local neutral =
			DamageCalculator.calculate(source("Feral"), combatant("Stone"), 30, "Stone", 0)
		Harness.equal(neutral.classMultiplier, 1.0)
		Harness.equal(neutral.damageBeforeShield, 30)

		local advantage =
			DamageCalculator.calculate(source("Stone"), combatant("Gale"), 30, "Feral", 0)
		Harness.equal(advantage.classMultiplier, 1.15)
		Harness.equal(advantage.damageBeforeShield, 34)

		local disadvantage =
			DamageCalculator.calculate(source("Stone"), combatant("Tide"), 30, "Feral", 0)
		Harness.equal(disadvantage.classMultiplier, 0.85)
		Harness.equal(disadvantage.damageBeforeShield, 25)
	end)

	Harness.test("compatibility damage modifiers are flat and damage clamps at zero", function()
		local attacker = source("Feral")
		local target = combatant("Stone")
		local buffed = DamageCalculator.calculate(attacker, target, 30, "Stone", 10)
		Harness.equal(buffed.damageModifier, 10)
		Harness.equal(buffed.damageBeforeShield, 40)

		local debuffed = DamageCalculator.calculate(attacker, target, 30, "Stone", -10)
		Harness.equal(debuffed.damageBeforeShield, 20)

		local zero = DamageCalculator.calculate(attacker, target, 10, "Stone", -100)
		Harness.equal(zero.damageBeforeShield, 0)
	end)

	Harness.test("same-class and Skill combo multipliers apply before flat modifiers", function()
		local result = DamageCalculator.calculate(
			source("Feral", 5),
			combatant("Stone"),
			30,
			"Feral",
			-2,
			true
		)
		Harness.equal(result.classMultiplier, 1.0)
		Harness.equal(result.sameClassMultiplier, 1.1)
		Harness.equal(result.skillMultiplier, 1.15)
		Harness.equal(result.damageModifier, -2)
		Harness.equal(result.criticalMultiplier, 1.0)
		Harness.equal(result.damageBeforeShield, 35)
	end)

	Harness.test("cross-class damage skips same-class bonus and rounds only at end", function()
		local result =
			DamageCalculator.calculate(source("Stone", 1), combatant("Gale"), 17, "Feral", 1, true)
		Harness.equal(result.classMultiplier, 1.15)
		Harness.equal(result.sameClassMultiplier, 1.0)
		Harness.equal(result.skillMultiplier, 1.03)
		Harness.equal(result.damageBeforeShield, 21)
	end)

	Harness.test("critical damage applies 1.5 after flat modifiers and rounds once", function()
		local result = DamageCalculator.calculate(
			source("Feral", 5),
			combatant("Stone"),
			17,
			"Feral",
			2,
			true,
			true
		)
		Harness.expect(math.abs(result.modifiedDamage - 23.505) < 1e-12)
		Harness.equal(result.criticalMultiplier, 1.5)
		Harness.equal(result.damageBeforeShield, 35)
		Harness.expect(result.isCritical)
	end)

	Harness.test("zero modified damage suppresses critical outcome", function()
		local result = DamageCalculator.calculate(
			source("Feral"),
			combatant("Stone"),
			10,
			"Feral",
			-100,
			false,
			true
		)
		Harness.equal(result.damageBeforeShield, 0)
		Harness.equal(result.criticalMultiplier, 1.0)
		Harness.expect(not result.isCritical)
	end)

	Harness.test("all legacy Attack cards retain explicit damage compatibility effects", function()
		local expected = {
			["feral.frenzy"] = "DAMAGE_UP",
			["feral.fury"] = "DAMAGE_UP",
			["stone.crush"] = "DAMAGE_DOWN",
			["shade.weaken"] = "DAMAGE_DOWN",
			["shade.curse"] = "DAMAGE_DOWN",
			["shade.terror"] = "DAMAGE_DOWN",
		}
		for abilityId, statusId in expected do
			local definition = CardCatalog.getByAbilityId(abilityId)
			local found = false
			for _, effect in definition.effects do
				if effect.kind == "STATUS" and effect.statusId == statusId then
					found = true
				end
			end
			Harness.expect(found, `{abilityId} must retain a compatibility status`)
		end
	end)

	Harness.test("shields stack and absorb in grant order", function()
		local absorption = DamageCalculator.absorbShields({
			{ id = "shield.1", amount = 10 },
			{ id = "shield.2", amount = 5 },
		}, 12)
		Harness.equal(absorption.absorbed, 12)
		Harness.equal(absorption.remainingDamage, 0)
		Harness.equal(#absorption.shields, 1)
		Harness.equal(absorption.shields[1].amount, 3)
		Harness.equal(absorption.shields[1].id, "shield.2")

		local overflow = DamageCalculator.absorbShields({
			{ id = "shield.1", amount = 4 },
		}, 10)
		Harness.equal(overflow.absorbed, 4)
		Harness.equal(overflow.remainingDamage, 6)
		Harness.equal(#overflow.shields, 0)
	end)

	Harness.test("shield absorption is deterministic and does not mutate input", function()
		local shields = {
			{ id = "shield.1", amount = 10 },
			{ id = "shield.2", amount = 5 },
		}
		local before = Harness.clone(shields)
		local first = DamageCalculator.absorbShields(shields, 7)
		local second = DamageCalculator.absorbShields(shields, 7)
		Harness.deepEqual(first, second)
		Harness.deepEqual(shields, before)
	end)
end
