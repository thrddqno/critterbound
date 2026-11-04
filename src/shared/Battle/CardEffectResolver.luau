--!strict

-- Resolve sibling modules in Roblox and under the Lune test runner.
local function requireSibling(name: string)
	if script ~= nil then
		return require((script.Parent :: any)[name])
	end
	return require(`./{name}`)
end

local DamageCalculator = requireSibling("DamageCalculator")
local CombatStats = requireSibling("CombatStats")
local StatusEffects = requireSibling("StatusEffects")

-- Effects on one card execute in authored array order. All effects of a card share the
-- targets resolved once for that card. Card definitions are never mutated.

local function applyDamage(
	source,
	target,
	effect,
	roundNumber: number,
	cardClass: string,
	skillComboActive: boolean,
	criticalRollSucceeded: boolean,
	factory,
	events: { any }
): boolean
	local breakdown = DamageCalculator.calculate(
		source,
		target,
		effect.amount or 0,
		cardClass,
		StatusEffects.damageModifier(source),
		skillComboActive,
		criticalRollSucceeded
	)
	local absorption = DamageCalculator.absorbShields(target.shields, breakdown.damageBeforeShield)
	local hpDamage = math.min(absorption.remainingDamage, target.currentHealth)
	local healthBefore = target.currentHealth
	target.shields = absorption.shields
	target.currentHealth =
		CombatStats.clampHealth(healthBefore - hpDamage, target.stats.maxHealth or healthBefore)

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
			sameClassMultiplier = breakdown.sameClassMultiplier,
			skillMultiplier = breakdown.skillMultiplier,
			damageModifier = breakdown.damageModifier,
			modifiedDamage = breakdown.modifiedDamage,
			criticalMultiplier = breakdown.criticalMultiplier,
			isCritical = breakdown.isCritical,
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
	target.currentHealth = CombatStats.clampHealth(healthBefore + amount, maximum)
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

local function applyShield(
	source,
	target,
	effect,
	cardClass: string,
	roundNumber: number,
	factory,
	events: { any },
	eventKind: string?,
	metadata: any?
)
	if target.currentHealth <= 0 then
		return
	end
	target.shields = target.shields or {}
	local amount, sameClassMultiplier =
		DamageCalculator.shieldAmount(effect.amount or 0, cardClass, source.class)
	local shield = {
		id = `shield:{target.id}:{roundNumber}:{#target.shields + 1}`,
		sourceCombatantId = source.id,
		amount = amount,
		expiresAtRound = roundNumber,
	}
	table.insert(target.shields, shield)
	table.insert(
		events,
		factory.emit(eventKind or "SHIELD_GRANTED", roundNumber, {
			sourceCombatantId = source.id,
			targetCombatantId = target.id,
			amount = shield.amount,
			baseAmount = effect.amount or 0,
			sameClassMultiplier = sameClassMultiplier,
			expiresAtRound = shield.expiresAtRound,
			shieldCount = #target.shields,
			cardInstanceId = if metadata ~= nil then metadata.cardInstanceId else nil,
			effectIndex = if metadata ~= nil then metadata.effectIndex else nil,
			preparationOrder = if metadata ~= nil then metadata.preparationOrder else nil,
		}, source.id, { target.id })
	)
end

local function prepareShields(
	source,
	targetIds: { string },
	definition,
	combatantsById,
	roundNumber: number,
	factory,
	events: { any },
	cardInstanceId: string,
	nextPreparationOrder: () -> number
)
	local cardClass = definition.class or source.class
	for effectIndex, effect in definition.effects or {} do
		if effect.kind == "SHIELD" then
			for _, targetId in targetIds do
				local target = combatantsById[targetId]
				if target ~= nil and target.currentHealth > 0 then
					applyShield(
						source,
						target,
						effect,
						cardClass,
						roundNumber,
						factory,
						events,
						"SHIELD_PREPARED",
						{
							cardInstanceId = cardInstanceId,
							effectIndex = effectIndex,
							preparationOrder = nextPreparationOrder(),
						}
					)
				end
			end
		end
	end
end

local function applyCard(
	source,
	targetIds: { string },
	definition,
	combatantsById,
	roundNumber: number,
	factory,
	events: { any },
	options: any?
): { string }
	local defeated = {}
	local effects = definition.effects or {}
	local cardClass = definition.class or source.class
	local skillComboActive = options ~= nil and options.skillComboActive == true
	local rollCritical = if options ~= nil then options.rollCritical else nil
	local skipShieldEffects = options ~= nil and options.skipShieldEffects == true

	for _, effect in effects do
		for _, targetId in targetIds do
			local target = combatantsById[targetId]
			if target ~= nil then
				if effect.kind == "DAMAGE" then
					if target.currentHealth > 0 then
						local criticalEligible = effect.criticalEligible ~= false
							and (effect.triggered ~= true or effect.criticalEligible == true)
						local criticalRollSucceeded = if criticalEligible
								and rollCritical ~= nil
							then rollCritical(source)
							else false
						if
							applyDamage(
								source,
								target,
								effect,
								roundNumber,
								cardClass,
								skillComboActive,
								criticalRollSucceeded,
								factory,
								events
							)
						then
							table.insert(defeated, target.id)
						end
					end
				elseif effect.kind == "HEAL" then
					applyHeal(source, target, effect, roundNumber, factory, events)
				elseif effect.kind == "SHIELD" and not skipShieldEffects then
					if target.currentHealth > 0 then
						applyShield(source, target, effect, cardClass, roundNumber, factory, events)
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
	prepareShields = prepareShields,
})
