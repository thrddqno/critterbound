--!strict

-- Resolve sibling modules in Roblox and under the Lune test runner.
local function requireSibling(name: string)
	if script ~= nil then
		return require((script.Parent :: any)[name])
	end
	return require(`./{name}`)
end

local DamageCalculator = requireSibling("DamageCalculator")
local StatusEffects = requireSibling("StatusEffects")

-- Effects on one card execute in authored array order. All effects of a card share the
-- targets resolved once for that card. Card definitions are never mutated.

local function applyDamage(
	source,
	target,
	effect,
	roundNumber: number,
	cardClass: string,
	factory,
	events: { any }
): boolean
	local breakdown = DamageCalculator.calculate(
		target,
		effect.amount or 0,
		cardClass,
		StatusEffects.attackModifier(source)
	)
	local absorption = DamageCalculator.absorbShields(target.shields, breakdown.damageBeforeShield)
	local hpDamage = math.min(absorption.remainingDamage, target.currentHealth)
	local healthBefore = target.currentHealth
	target.shields = absorption.shields
	target.currentHealth = math.max(0, healthBefore - hpDamage)

	if absorption.absorbed > 0 then
		table.insert(
			events,
			factory.emit("SHIELD_ABSORBED", roundNumber, {
				sourceCombatantId = source.id,
				targetCombatantId = target.id,
				absorbed = absorption.absorbed,
				damageBeforeShield = breakdown.damageBeforeShield,
				remainingDamage = absorption.remainingDamage,
			}, source.id, { target.id })
		)
	end

	table.insert(
		events,
		factory.emit("DAMAGE_APPLIED", roundNumber, {
			sourceCombatantId = source.id,
			targetCombatantId = target.id,
			baseDamage = breakdown.baseDamage,
			classMultiplier = breakdown.classMultiplier,
			attackModifier = breakdown.attackModifier,
			defenseModifier = breakdown.defenseModifier,
			statusMultiplier = breakdown.statusMultiplier,
			damageBeforeShield = breakdown.damageBeforeShield,
			shieldAbsorbed = absorption.absorbed,
			hpDamage = hpDamage,
			healthBefore = healthBefore,
			healthAfter = target.currentHealth,
		}, source.id, { target.id })
	)

	return healthBefore > 0 and target.currentHealth == 0
end

local function applyHeal(source, target, effect, roundNumber: number, factory, events: { any })
	if target.currentHealth <= 0 then
		table.insert(
			events,
			factory.emit("HEAL_APPLIED", roundNumber, {
				sourceCombatantId = source.id,
				targetCombatantId = target.id,
				requested = effect.amount or 0,
				restored = 0,
				healthBefore = 0,
				healthAfter = 0,
				rejected = true,
				reason = "TARGET_DEFEATED",
			}, source.id, { target.id })
		)
		return
	end

	local amount = math.max(0, effect.amount or 0)
	local healthBefore = target.currentHealth
	local maximum = target.stats.maxHealth or healthBefore
	target.currentHealth = math.min(maximum, healthBefore + amount)
	table.insert(
		events,
		factory.emit("HEAL_APPLIED", roundNumber, {
			sourceCombatantId = source.id,
			targetCombatantId = target.id,
			requested = amount,
			restored = target.currentHealth - healthBefore,
			healthBefore = healthBefore,
			healthAfter = target.currentHealth,
			rejected = false,
		}, source.id, { target.id })
	)
end

local function applyShield(source, target, effect, roundNumber: number, factory, events: { any })
	if target.currentHealth <= 0 then
		return
	end
	target.shields = target.shields or {}
	local shield = {
		id = `shield:{target.id}:{roundNumber}:{#target.shields + 1}`,
		sourceCombatantId = source.id,
		amount = math.max(0, effect.amount or 0),
		expiresAtRound = roundNumber,
	}
	table.insert(target.shields, shield)
	table.insert(
		events,
		factory.emit("SHIELD_GRANTED", roundNumber, {
			sourceCombatantId = source.id,
			targetCombatantId = target.id,
			amount = shield.amount,
			expiresAtRound = shield.expiresAtRound,
			shieldCount = #target.shields,
		}, source.id, { target.id })
	)
end

local function applyCard(
	source,
	targetIds: { string },
	definition,
	combatantsById,
	roundNumber: number,
	factory,
	events: { any }
): { string }
	local defeated = {}
	local effects = definition.effects or {}
	local cardClass = definition.class or source.class

	for _, effect in effects do
		for _, targetId in targetIds do
			local target = combatantsById[targetId]
			if target ~= nil then
				if effect.kind == "DAMAGE" then
					if
						target.currentHealth > 0
						and applyDamage(
							source,
							target,
							effect,
							roundNumber,
							cardClass,
							factory,
							events
						)
					then
						table.insert(defeated, target.id)
					end
				elseif effect.kind == "HEAL" then
					applyHeal(source, target, effect, roundNumber, factory, events)
				elseif effect.kind == "SHIELD" then
					if target.currentHealth > 0 then
						applyShield(source, target, effect, roundNumber, factory, events)
					end
				elseif effect.kind == "STATUS" and target.currentHealth > 0 then
					StatusEffects.apply(
						target,
						effect.statusId,
						effect.magnitude or 0,
						effect.duration or 1,
						source.id,
						roundNumber,
						factory,
						events
					)
				end
			end
		end
	end

	return defeated
end

return table.freeze({
	applyCard = applyCard,
})
