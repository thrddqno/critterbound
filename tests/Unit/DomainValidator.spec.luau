--!strict

return function(Harness)
	local Validator = require("../../src/shared/Validation/DomainValidator")
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
		instance.appearanceGenome.paletteId = "autumn"
		Harness.deepEqual(instance.abilityGenome, abilitiesBefore)
		Harness.expect(Validator.validateAppearanceGenome(instance.appearanceGenome).ok)
		Harness.expect(Validator.validateAbilityGenome(instance.abilityGenome).ok)
	end)

	Harness.test("valid card definitions", function()
		for _, definition in Fixtures.CardDefinitions do
			Harness.expect(Validator.validateCardDefinition(definition, validAbilityIds).ok)
		end
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

	Harness.test("invalid target rejected", function()
		local command = Harness.clone(Fixtures.ValidCommand)
		command.queuedCards[2].targetCombatantIds = { Fixtures.Combatants.feral.id }
		local result = Validator.validateBattleCommand(command, Fixtures.Context)
		Harness.expect(Harness.hasError(result, "INVALID_TARGET"))
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
