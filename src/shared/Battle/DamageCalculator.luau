--!strict

-- Resolve sibling modules in Roblox and under the Lune test runner.
local function requireSibling(name: string)
	if script ~= nil then
		return require((script.Parent :: any)[name])
	end
	return require(`./{name}`)
end

local ClassAdvantage = requireSibling("ClassAdvantage")
local CombatConstants = requireSibling("CombatConstants")

export type Breakdown = {
	baseDamage: number,
	classMultiplier: number,
	attackModifier: number,
	defenseModifier: number,
	statusMultiplier: number,
	damageBeforeShield: number,
	shieldAbsorbed: number,
	hpDamage: number,
}

-- Documented pipeline. Rounding happens once, after all multipliers and flat modifiers.
--   1. base card damage
--   2. class advantage/disadvantage
--   3. attack modifiers (flat, signed)
--   4. defensive modifier (flat, floor(defense * 0.5))
--   5. status vulnerability multiplier (1.0 in Run 4B)
--   6. shield absorption (handled by absorbShields)
--   7. HP damage, clamped to remaining health by the caller
local function calculate(
	target,
	baseDamage: number,
	cardClass: string,
	attackModifier: number
): Breakdown
	local classMultiplier = ClassAdvantage.multiplier(cardClass, target.class)
	local afterClass = baseDamage * classMultiplier
	local afterAttack = math.max(0, afterClass + attackModifier)
	local defenseModifier =
		math.floor((target.stats.defense or 0) * CombatConstants.DefenseReductionRatio)
	local afterDefense = math.max(0, afterAttack - defenseModifier)
	local statusMultiplier = 1.0
	local damageBeforeShield = math.max(0, math.floor(afterDefense * statusMultiplier))

	return {
		baseDamage = baseDamage,
		classMultiplier = classMultiplier,
		attackModifier = attackModifier,
		defenseModifier = defenseModifier,
		statusMultiplier = statusMultiplier,
		damageBeforeShield = damageBeforeShield,
		shieldAbsorbed = 0,
		hpDamage = damageBeforeShield,
	}
end

export type Absorption = {
	absorbed: number,
	remainingDamage: number,
	shields: { any },
}

-- Shields absorb in grant order. Zero-value shields are removed. Callers emit events.
local function absorbShields(shields: { any }?, damage: number): Absorption
	local remaining = damage
	local absorbed = 0
	local nextShields = {}

	for _, shield in shields or {} do
		if remaining <= 0 then
			table.insert(nextShields, shield)
		else
			local amount = shield.amount or 0
			local used = math.min(amount, remaining)
			absorbed += used
			remaining -= used
			local left = amount - used
			if left > 0 then
				local copy = table.clone(shield)
				copy.amount = left
				table.insert(nextShields, copy)
			end
		end
	end

	return {
		absorbed = absorbed,
		remainingDamage = remaining,
		shields = nextShields,
	}
end

return table.freeze({
	calculate = calculate,
	absorbShields = absorbShields,
})
