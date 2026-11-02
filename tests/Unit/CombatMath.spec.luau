--!strict

return function(Harness)
	local ClassAdvantage = require("../../src/shared/Battle/ClassAdvantage")
	local DamageCalculator = require("../../src/shared/Battle/DamageCalculator")

	local function combatant(class, overrides)
		local stats = {
			maxHealth = 100,
			attack = 20,
			defense = 20,
			speed = 20,
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

	Harness.test("class ring awards advantage, disadvantage, and neutral", function()
		Harness.equal(ClassAdvantage.multiplier("Verdant", "Tide"), 1.15)
		Harness.equal(ClassAdvantage.multiplier("Feral", "Gale"), 1.15)
		Harness.equal(ClassAdvantage.multiplier("Feral", "Tide"), 0.85)
		Harness.equal(ClassAdvantage.multiplier("Feral", "Stone"), 1.0)
		Harness.equal(ClassAdvantage.multiplier("Feral", "Feral"), 1.0)
		Harness.equal(ClassAdvantage.multiplier("Unknown", "Tide"), 1.0)
	end)

	Harness.test("damage applies class, attack, and defense in documented order", function()
		local neutral = DamageCalculator.calculate(combatant("Stone"), 30, "Stone", 0)
		Harness.equal(neutral.classMultiplier, 1.0)
		Harness.equal(neutral.defenseModifier, 10)
		Harness.equal(neutral.damageBeforeShield, 20)

		local advantage = DamageCalculator.calculate(combatant("Gale"), 30, "Feral", 0)
		Harness.equal(advantage.classMultiplier, 1.15)
		Harness.equal(advantage.damageBeforeShield, 24)

		local disadvantage = DamageCalculator.calculate(combatant("Tide"), 30, "Feral", 0)
		Harness.equal(disadvantage.classMultiplier, 0.85)
		Harness.equal(disadvantage.damageBeforeShield, 15)
	end)

	Harness.test("attack modifiers are flat and damage clamps at zero", function()
		local buffed = DamageCalculator.calculate(combatant("Stone"), 30, "Stone", 10)
		Harness.equal(buffed.attackModifier, 10)
		Harness.equal(buffed.damageBeforeShield, 30)

		local debuffed = DamageCalculator.calculate(combatant("Stone"), 30, "Stone", -10)
		Harness.equal(debuffed.damageBeforeShield, 10)

		local zero = DamageCalculator.calculate(combatant("Stone"), 0, "Stone", 0)
		Harness.equal(zero.damageBeforeShield, 0)
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
