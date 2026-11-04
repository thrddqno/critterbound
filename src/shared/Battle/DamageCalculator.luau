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
	sameClassMultiplier: number,
	skillMultiplier: number,
	damageModifier: number,
	modifiedDamage: number,
	criticalMultiplier: number,
	isCritical: boolean,
	damageBeforeShield: number,
	shieldAbsorbed: number,
	hpDamage: number,
}

-- Documented pipeline. Rounding happens once, after all multipliers and flat modifiers.
--   1. base card damage
--   2. class advantage/disadvantage
--   3. same-class multiplier
--   4. Skill combo multiplier
--   5. flat outgoing damage modifiers (signed), then clamp to zero
--   6. critical multiplier (1.5 on a successful eligible roll; otherwise 1.0)
--   7. floor once
--   8. shield absorption (handled by absorbShields)
--   9. HP damage, clamped to remaining health by the caller
local function calculate(
	source,
	target,
	baseDamage: number,
	cardClass: string,
	damageModifier: number,
	skillComboActive: boolean?,
	criticalRollSucceeded: boolean?
): Breakdown
	local classMultiplier = ClassAdvantage.multiplier(cardClass, target.class)
	local sameClassMultiplier = if cardClass == source.class
		then CombatConstants.SameClassMultiplier
		else CombatConstants.CrossClassMultiplier
	local skillMultiplier = if skillComboActive == true
		then 1 + CombatConstants.SkillMultiplierPerPoint * (source.stats.skill or 0)
		else 1
	local modifiedDamage = math.max(
		0,
		baseDamage * classMultiplier * sameClassMultiplier * skillMultiplier + damageModifier
	)
	local isCritical = criticalRollSucceeded == true and modifiedDamage > 0
	local appliedCriticalMultiplier = if isCritical
		then CombatConstants.CriticalDamageMultiplier
		else CombatConstants.NormalDamageMultiplier
	local damageBeforeShield = math.floor(modifiedDamage * appliedCriticalMultiplier)

	return {
		baseDamage = baseDamage,
		classMultiplier = classMultiplier,
		sameClassMultiplier = sameClassMultiplier,
		skillMultiplier = skillMultiplier,
		damageModifier = damageModifier,
		modifiedDamage = modifiedDamage,
		criticalMultiplier = appliedCriticalMultiplier,
		isCritical = isCritical,
		damageBeforeShield = damageBeforeShield,
		shieldAbsorbed = 0,
		hpDamage = damageBeforeShield,
	}
end

local function shieldAmount(
	baseAmount: number,
	cardClass: string,
	sourceClass: string
): (number, number)
	local sameClassMultiplier = if cardClass == sourceClass
		then CombatConstants.SameClassMultiplier
		else CombatConstants.CrossClassMultiplier
	return math.max(0, math.floor(baseAmount * sameClassMultiplier)), sameClassMultiplier
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
	shieldAmount = shieldAmount,
	absorbShields = absorbShields,
})
