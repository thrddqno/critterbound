--!strict

return function(Harness)
	local Validator = require("../../src/shared/Validation/DomainValidator")
	local CardCatalog = require("../../src/shared/Definitions/CardCatalog")
	local Fixtures = require("../Fixtures/DomainFixtures")

	local definitionsById = {}
	local validAbilityIds = {}
	for _, definition in Fixtures.Definitions do
		definitionsById[definition.id] = definition
		for _, abilityId in definition.abilityIds do
			validAbilityIds[abilityId] = true
		end
	end

	Harness.test("valid creature definitions", function()
		for _, definition in Fixtures.Definitions do
			Harness.expect(Validator.validateCritterDefinition(definition).ok)
		end
	end)

	Harness.test("invalid creature definition", function()
		local invalid = Harness.clone(Fixtures.Definitions.Stone)
		invalid.abilityIds[4] = invalid.abilityIds[1]
		local result = Validator.validateCritterDefinition(invalid)
		Harness.expect(not result.ok)
		Harness.expect(Validator.isIdentifier("card.stone-guard:1"))
		Harness.expect(not Validator.isIdentifier("bad card id"))
		Harness.expect(Harness.hasError(result, "DUPLICATE_ABILITY_ID"))
	end)

	Harness.test("valid creature instances", function()
		for _, instance in Fixtures.Instances do
			Harness.expect(
				Validator.validateCritterInstance(instance, definitionsById, validAbilityIds).ok
			)
		end
	end)

	Harness.test("invalid creature instance", function()
		local invalid = Harness.clone(Fixtures.Instances.Feral)
		invalid.ownerUserId = 0
		invalid.definitionId = "missing.definition"
		local result = Validator.validateCritterInstance(invalid, definitionsById, validAbilityIds)
		Harness.expect(Harness.hasError(result, "INVALID_OWNER"))
		Harness.expect(Harness.hasError(result, "UNKNOWN_CRITTER_DEFINITION"))
	end)

	Harness.test("appearance and ability genomes stay separate", function()
		local instance = Harness.clone(Fixtures.Instances.Verdant)
		local abilitiesBefore = Harness.clone(instance.abilityGenome)
		instance.appearanceGenome.slots.color.D = "gene.appearance.eyes.universal.bright"
		Harness.deepEqual(instance.abilityGenome, abilitiesBefore)
		Harness.expect(
			not Validator.validateAppearanceGenome(instance.appearanceGenome, "Verdant").ok
		)
		Harness.expect(Validator.validateAbilityGenome(instance.abilityGenome, "Verdant").ok)
	end)

	Harness.test("valid card definitions", function()
		for _, definition in Fixtures.CardDefinitions do
			Harness.expect(Validator.validateCardDefinition(definition, validAbilityIds).ok)
		end
	end)

	Harness.test("optional ability pool requires unique complete base abilities", function()
		local definition = Harness.clone(Fixtures.Definitions.Stone)
		definition.abilityPool = {
			"stone.guard",
			"stone.bulwark",
			"stone.quake",
			"stone.slam",
			"stone.rampart",
		}
		Harness.expect(Validator.validateCritterDefinition(definition).ok)

		local duplicate = Harness.clone(definition)
		duplicate.abilityPool[5] = "stone.guard"
		Harness.expect(
			Harness.hasError(Validator.validateCritterDefinition(duplicate), "DUPLICATE_ABILITY_ID")
		)

		local missing = Harness.clone(definition)
		table.remove(missing.abilityPool, 4)
		Harness.expect(
			Harness.hasError(
				Validator.validateCritterDefinition(missing),
				"ABILITY_POOL_MISSING_BASE"
			)
		)
	end)

	Harness.test("battle commands accept only explicit cross-class compatibility", function()
		local bloom = CardCatalog.getByAbilityId("verdant.bloom")
		Harness.expect(bloom ~= nil)
		local context = Harness.clone(Fixtures.Context)
		local stoneId = Fixtures.Combatants.stone.id
		table.insert(context.combatantsById[stoneId].abilityIds, "verdant.bloom")
		local cardInstance = {
			id = "hand.stone.bloom.1",
			definitionId = bloom.id,
			sourceCritterInstanceId = Fixtures.Instances.Stone.id,
		}
		context.cardInstancesById[cardInstance.id] = cardInstance
		context.cardDefinitionsById[bloom.id] = bloom
		table.insert(context.handCardInstanceIds, cardInstance.id)
		local command = Harness.clone(Fixtures.ValidCommand)
		command.queuedCards = {
			{
				cardInstanceId = cardInstance.id,
				sourceCombatantId = stoneId,
				targetCombatantIds = {},
				queueIndex = 1,
			},
		}
		Harness.expect(Validator.validateBattleCommand(command, context).ok)

		context.combatantsById[stoneId].class = "Shade"
		Harness.expect(
			Harness.hasError(
				Validator.validateBattleCommand(command, context),
				"INVALID_CLASS_REFERENCE"
			)
		)
	end)

	Harness.test("invalid card definition", function()
		local invalid = Harness.clone(Fixtures.CardDefinitions.FeralStrike)
		invalid.id = "invalid card"
		invalid.abilityId = "missing.ability"
		local result = Validator.validateCardDefinition(invalid, validAbilityIds)
		Harness.expect(Harness.hasError(result, "INVALID_CARD_ID"))
		Harness.expect(Harness.hasError(result, "UNKNOWN_ABILITY"))
	end)

	Harness.test("valid team composition", function()
		Harness.expect(
			Validator.validateTeamComposition(Fixtures.Team, Fixtures.Context.combatantsById).ok
		)
	end)

	Harness.test("duplicate creature rejected", function()
		local team = Harness.clone(Fixtures.Team)
		local combatants = Harness.clone(Fixtures.Context.combatantsById)
		combatants[team.combatantIds[2]].critterInstanceId =
			combatants[team.combatantIds[1]].critterInstanceId
		local result = Validator.validateTeamComposition(team, combatants)
		Harness.expect(Harness.hasError(result, "DUPLICATE_CRITTER"))
	end)

	Harness.test("valid battle command", function()
		Harness.expect(Validator.validateBattleCommand(Fixtures.ValidCommand, Fixtures.Context).ok)
	end)

	Harness.test("insufficient energy rejected", function()
		local context = Harness.clone(Fixtures.Context)
		context.availableEnergy = 2
		local result = Validator.validateBattleCommand(Fixtures.ValidCommand, context)
		Harness.expect(Harness.hasError(result, "INSUFFICIENT_ENERGY"))
	end)

	Harness.test("duplicate card submission rejected", function()
		local command = Harness.clone(Fixtures.ValidCommand)
		command.queuedCards[2] = Harness.clone(command.queuedCards[1])
		command.queuedCards[2].queueIndex = 2
		local result = Validator.validateBattleCommand(command, Fixtures.Context)
		Harness.expect(Harness.hasError(result, "DUPLICATE_CARD"))
	end)

	Harness.test("forged fifth card for one Critter is rejected", function()
		local context = Harness.clone(Fixtures.Context)
		local command = Harness.clone(Fixtures.ValidCommand)
		context.availableEnergy = 100
		command.queuedCards = {}
		local source = Fixtures.Combatants.stone
		for index = 1, 5 do
			local cardId = `hand.stone.guard.{index}`
			context.cardInstancesById[cardId] = {
				id = cardId,
				definitionId = Fixtures.CardDefinitions.StoneGuard.id,
				sourceCritterInstanceId = source.critterInstanceId,
			}
			table.insert(context.handCardInstanceIds, cardId)
			table.insert(command.queuedCards, {
				cardInstanceId = cardId,
				sourceCombatantId = source.id,
				targetCombatantIds = {},
				queueIndex = index,
			})
		end
		local result = Validator.validateBattleCommand(command, context)
		Harness.expect(Harness.hasError(result, "CRITTER_QUEUE_LIMIT_EXCEEDED"))
	end)

	Harness.test("invalid ownership rejected", function()
		local command = Harness.clone(Fixtures.ValidCommand)
		command.actorUserId = 999
		local result = Validator.validateBattleCommand(command, Fixtures.Context)
		Harness.expect(Harness.hasError(result, "INVALID_OWNERSHIP"))
	end)

	Harness.test("card source ownership rejected", function()
		local context = Harness.clone(Fixtures.Context)
		context.cardInstancesById[Fixtures.CardInstances.feral.id].sourceCritterInstanceId =
			Fixtures.Instances.Stone.id
		local result = Validator.validateBattleCommand(Fixtures.ValidCommand, context)
		Harness.expect(Harness.hasError(result, "INVALID_OWNERSHIP"))
	end)

	Harness.test("card outside hand rejected", function()
		local context = Harness.clone(Fixtures.Context)
		context.handCardInstanceIds = { Fixtures.CardInstances.stone.id }
		local result = Validator.validateBattleCommand(Fixtures.ValidCommand, context)
		Harness.expect(Harness.hasError(result, "CARD_NOT_IN_HAND"))
	end)

	Harness.test("invalid class and ability references rejected", function()
		local context = Harness.clone(Fixtures.Context)
		local definition = context.cardDefinitionsById[Fixtures.CardInstances.feral.definitionId]
		definition.class = "Stone"
		definition.abilityId = "stone.guard"
		local result = Validator.validateBattleCommand(Fixtures.ValidCommand, context)
		Harness.expect(Harness.hasError(result, "INVALID_CLASS_REFERENCE"))
		Harness.expect(Harness.hasError(result, "INVALID_ABILITY_REFERENCE"))
	end)

	Harness.test("noncontiguous queue rejected", function()
		local command = Harness.clone(Fixtures.ValidCommand)
		command.queuedCards[1].queueIndex = 2
		local result = Validator.validateBattleCommand(command, Fixtures.Context)
		Harness.expect(Harness.hasError(result, "INVALID_QUEUE_ORDER"))
	end)

	Harness.test("forged automatic target rejected", function()
		local command = Harness.clone(Fixtures.ValidCommand)
		command.queuedCards[2].targetCombatantIds = { Fixtures.Combatants.feral.id }
		local result = Validator.validateBattleCommand(command, Fixtures.Context)
		Harness.expect(Harness.hasError(result, "INVALID_TARGET_COUNT"))
	end)

	Harness.test("card effects accept known kinds and reject malformed values", function()
		local definition = Harness.clone(Fixtures.CardDefinitions.FeralStrike)
		definition.effects = {
			{ kind = "DAMAGE", amount = 10 },
			{ kind = "SHIELD", amount = 5 },
			{ kind = "HEAL", amount = 5 },
			{ kind = "STATUS", statusId = "POISON", magnitude = 3, duration = 2 },
		}
		Harness.expect(Validator.validateCardDefinition(definition, validAbilityIds).ok)

		definition.effects = { { kind = "BURN" } }
		local kindResult = Validator.validateCardDefinition(definition, validAbilityIds)
		Harness.expect(Harness.hasError(kindResult, "INVALID_EFFECT_KIND"))

		definition.effects = { { kind = "DAMAGE", amount = -1 } }
		local amountResult = Validator.validateCardDefinition(definition, validAbilityIds)
		Harness.expect(Harness.hasError(amountResult, "INVALID_EFFECT_AMOUNT"))

		definition.effects = { { kind = "STATUS", statusId = "BURN", magnitude = 1, duration = 1 } }
		local statusResult = Validator.validateCardDefinition(definition, validAbilityIds)
		Harness.expect(Harness.hasError(statusResult, "INVALID_STATUS_ID"))

		definition.effects =
			{ { kind = "STATUS", statusId = "POISON", magnitude = 1, duration = 1.5 } }
		local durationResult = Validator.validateCardDefinition(definition, validAbilityIds)
		Harness.expect(Harness.hasError(durationResult, "INVALID_STATUS_DURATION"))

		definition.effects = {
			{ kind = "DAMAGE", amount = 1, triggered = true, criticalEligible = true },
		}
		Harness.expect(Validator.validateCardDefinition(definition, validAbilityIds).ok)

		definition.effects = { { kind = "HEAL", amount = 1, criticalEligible = true } }
		Harness.expect(
			Harness.hasError(
				Validator.validateCardDefinition(definition, validAbilityIds),
				"INVALID_CRITICAL_ELIGIBILITY"
			)
		)
	end)

	Harness.test("new targeting rules are valid card definitions", function()
		for _, rule in { "FRONT_ENEMY", "ALL_ALLIES", "ALL_ENEMIES" } do
			local definition = Harness.clone(Fixtures.CardDefinitions.FeralStrike)
			definition.id = `card.rule.{string.lower(rule)}`
			definition.targetingRule = rule
			Harness.expect(Validator.validateCardDefinition(definition, validAbilityIds).ok)
		end
	end)

	Harness.test("four core stats validate and retired stats are rejected", function()
		local definition = Harness.clone(Fixtures.Definitions.Feral)
		definition.baseStats.skill = 4
		definition.baseStats.morale = 2
		Harness.expect(Validator.validateCritterDefinition(definition).ok)

		definition.baseStats.morale = -1
		local result = Validator.validateCritterDefinition(definition)
		Harness.expect(Harness.hasError(result, "INVALID_STAT"))

		definition.baseStats.morale = 2
		definition.baseStats.attack = 10
		Harness.expect(
			Harness.hasError(Validator.validateCritterDefinition(definition), "RETIRED_STAT")
		)
	end)

	Harness.test("automatic targeting rules require an empty client target list", function()
		for _, rule in { "SELF", "ENEMY", "FRONT_ENEMY", "ALL_ALLIES", "ALL_ENEMIES" } do
			local context = Harness.clone(Fixtures.Context)
			context.cardDefinitionsById[Fixtures.CardInstances.feral.definitionId].targetingRule =
				rule
			local command = Harness.clone(Fixtures.ValidCommand)
			Harness.expect(Validator.validateBattleCommand(command, context).ok)

			command.queuedCards[2].targetCombatantIds = { Fixtures.Combatants.enemyStone.id }
			local result = Validator.validateBattleCommand(command, context)
			Harness.expect(Harness.hasError(result, "INVALID_TARGET_COUNT"))
		end
	end)

	Harness.test("single-target rules reject an empty target list", function()
		local context = Harness.clone(Fixtures.Context)
		context.cardDefinitionsById[Fixtures.CardInstances.feral.definitionId].targetingRule = "ANY"
		local command = Harness.clone(Fixtures.ValidCommand)
		command.queuedCards[2].targetCombatantIds = {}
		local result = Validator.validateBattleCommand(command, context)
		Harness.expect(Harness.hasError(result, "INVALID_TARGET_COUNT"))
	end)

	Harness.test("validation never mutates inputs", function()
		local command = Harness.clone(Fixtures.ValidCommand)
		local context = Harness.clone(Fixtures.Context)
		local commandBefore = Harness.clone(command)
		local contextBefore = Harness.clone(context)
		Validator.validateBattleCommand(command, context)
		Harness.deepEqual(command, commandBefore)
		Harness.deepEqual(context, contextBefore)
	end)
end
