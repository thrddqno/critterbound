--!strict

local function requireSibling(name: string)
	if script ~= nil then
		return require((script.Parent :: any)[name])
	end
	return require(`./{name}`)
end

local DamageCalculator = requireSibling("DamageCalculator")

export type Config = {
	Enabled: boolean,
	StartingRound: number,
	InitialDamage: number,
	DamageIncrement: number,
	BypassesShields: boolean,
}

local function isNonNegativeInteger(value: any): boolean
	return type(value) == "number" and value >= 0 and value % 1 == 0
end

local function validate(config: any): boolean
	return type(config) == "table"
		and type(config.Enabled) == "boolean"
		and isNonNegativeInteger(config.StartingRound)
		and config.StartingRound >= 1
		and isNonNegativeInteger(config.InitialDamage)
		and isNonNegativeInteger(config.DamageIncrement)
		and type(config.BypassesShields) == "boolean"
end

local function damageForRound(config: Config?, roundNumber: number): number?
	if
		config == nil
		or not validate(config)
		or not config.Enabled
		or roundNumber < config.StartingRound
	then
		return nil
	end
	return config.InitialDamage + config.DamageIncrement * (roundNumber - config.StartingRound)
end

-- Caller supplies stable team/slot combatant order. Every living target is mutated before the
-- caller evaluates victory, allowing simultaneous environmental defeat.
local function apply(
	state,
	orderedCombatants: { any },
	roundNumber: number,
	config: Config?,
	factory,
	events
)
	local damage = damageForRound(config, roundNumber)
	if damage == nil or state.lastBloodMoonRound == roundNumber then
		return { applied = false, damage = damage or 0, defeatedCombatantIds = {} }
	end

	local defeated = {}
	for _, combatant in orderedCombatants do
		if combatant.currentHealth > 0 then
			local healthBefore = combatant.currentHealth
			local shieldAbsorbed = 0
			if not (config :: Config).BypassesShields then
				local absorption = DamageCalculator.absorbShields(combatant.shields or {}, damage)
				combatant.shields = absorption.shields
				shieldAbsorbed = absorption.absorbed
			end
			local hpDamage = math.min(healthBefore, math.max(0, damage - shieldAbsorbed))
			combatant.currentHealth = healthBefore - hpDamage
			local wasDefeated = combatant.currentHealth == 0
			table.insert(
				events,
				factory.emit("BLOOD_MOON_DAMAGE", roundNumber, {
					source = "BLOOD_MOON",
					roundNumber = roundNumber,
					targetCombatantId = combatant.id,
					damage = damage,
					hpDamage = hpDamage,
					shieldAbsorbed = shieldAbsorbed,
					bypassesShields = (config :: Config).BypassesShields,
					healthBefore = healthBefore,
					healthAfter = combatant.currentHealth,
					defeated = wasDefeated,
				}, nil, { combatant.id })
			)
			if wasDefeated then
				table.insert(defeated, combatant.id)
			end
		end
	end
	state.lastBloodMoonRound = roundNumber
	return { applied = true, damage = damage, defeatedCombatantIds = defeated }
end

return table.freeze({
	validate = validate,
	damageForRound = damageForRound,
	apply = apply,
})
