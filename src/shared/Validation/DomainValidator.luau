--!strict

export type DomainError = {
	code: string,
	message: string,
	path: string?,
}

export type ValidationSuccess = {
	ok: true,
	value: true,
}

export type ValidationFailure = {
	ok: false,
	errors: { DomainError },
}

export type ValidationResult = ValidationSuccess | ValidationFailure

type AnyRecord = { [any]: any }
type RecordsById = { [string]: AnyRecord }

local function requireDefinition(name: string)
	if script ~= nil then
		return require((script.Parent.Parent.Definitions :: any)[name])
	end
	return require(`../Definitions/{name}`)
end

local TargetingRules = requireDefinition("TargetingRules")

export type BattleValidationContext = {
	team: AnyRecord,
	combatantsById: RecordsById,
	cardInstancesById: RecordsById,
	cardDefinitionsById: RecordsById,
	handCardInstanceIds: { string },
	availableEnergy: number,
}

local VALID_CLASSES: { [string]: boolean } = {
	Verdant = true,
	Tide = true,
	Feral = true,
	Gale = true,
	Shade = true,
	Stone = true,
}

local VALID_TARGETING_RULES: { [string]: boolean } = {
	SELF = true,
	ALLY = true,
	ENEMY = true,
	ANY = true,
	FRONT_ENEMY = true,
	ALL_ALLIES = true,
	ALL_ENEMIES = true,
}

local VALID_EFFECT_KINDS: { [string]: boolean } = {
	DAMAGE = true,
	HEAL = true,
	SHIELD = true,
	STATUS = true,
}

local VALID_STATUS_IDS: { [string]: boolean } = {
	POISON = true,
	ATTACK_UP = true,
	ATTACK_DOWN = true,
	SPEED_UP = true,
	SPEED_DOWN = true,
}

local MAX_EFFECTS_PER_CARD = 8

local function addError(errors: { DomainError }, code: string, message: string, path: string?)
	table.insert(errors, {
		code = code,
		message = message,
		path = path,
	})
end

local function finish(errors: { DomainError }): ValidationResult
	if #errors == 0 then
		return { ok = true, value = true }
	end

	return { ok = false, errors = errors }
end

local function isIdentifier(value: unknown): boolean
	return type(value) == "string"
		and #value >= 1
		and #value <= 64
		and string.match(value, "^[%w][%w_.:%-]*$") ~= nil
end

local function isFiniteNumber(value: unknown): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function isNonNegativeInteger(value: unknown): boolean
	if type(value) ~= "number" then
		return false
	end

	return value == value
		and value > -math.huge
		and value < math.huge
		and value >= 0
		and value % 1 == 0
end

local function isPositiveInteger(value: unknown): boolean
	if type(value) ~= "number" then
		return false
	end

	return value == value
		and value > -math.huge
		and value < math.huge
		and value >= 1
		and value % 1 == 0
end

local function getArrayLength(value: unknown): number?
	if type(value) ~= "table" then
		return nil
	end

	local count = 0
	local maximum = 0

	for key in value do
		if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
			return nil
		end

		count += 1
		maximum = math.max(maximum, key)
	end

	if count ~= maximum then
		return nil
	end

	return count
end

local function hasString(values: { any }, expected: string): boolean
	for _, value in values do
		if value == expected then
			return true
		end
	end

	return false
end

local function validateIdentifier(
	errors: { DomainError },
	value: unknown,
	path: string,
	code: string
)
	if not isIdentifier(value) then
		addError(errors, code, "Expected 1-64 identifier characters", path)
	end
end

local function validateStats(errors: { DomainError }, value: unknown, path: string)
	if type(value) ~= "table" then
		addError(errors, "INVALID_STATS", "Expected stat table", path)
		return
	end

	local stats = value :: { [any]: any }

	for _, field in { "maxHealth", "attack", "defense", "speed" } do
		local fieldValue = stats[field]
		if not isFiniteNumber(fieldValue) or fieldValue < 0 then
			addError(errors, "INVALID_STAT", "Expected finite non-negative stat", `{path}.{field}`)
		end
	end

	for _, field in { "skill", "resolve" } do
		local fieldValue = stats[field]
		if fieldValue ~= nil and (not isFiniteNumber(fieldValue) or fieldValue < 0) then
			addError(
				errors,
				"INVALID_STAT",
				"Expected finite non-negative optional stat",
				`{path}.{field}`
			)
		end
	end

	if isFiniteNumber(stats.maxHealth) and stats.maxHealth <= 0 then
		addError(
			errors,
			"INVALID_MAX_HEALTH",
			"maxHealth must be greater than zero",
			`{path}.maxHealth`
		)
	end
end

local function validateAbilityIds(
	errors: { DomainError },
	value: unknown,
	path: string,
	requireFour: boolean
)
	local length = getArrayLength(value)
	if length == nil then
		addError(errors, "INVALID_ABILITY_LIST", "Expected dense ability identifier array", path)
		return
	end

	if requireFour and length ~= 4 then
		addError(errors, "INVALID_ABILITY_COUNT", "Expected exactly four ability identifiers", path)
	end

	local seen: { [string]: boolean } = {}
	for index, abilityId in value :: { any } do
		validateIdentifier(errors, abilityId, `{path}[{index}]`, "INVALID_ABILITY_ID")
		if type(abilityId) == "string" then
			if seen[abilityId] then
				addError(
					errors,
					"DUPLICATE_ABILITY_ID",
					"Ability identifiers must be unique",
					`{path}[{index}]`
				)
			end
			seen[abilityId] = true
		end
	end
end

local function validateAppearanceGenome(value: unknown): ValidationResult
	local errors: { DomainError } = {}
	if type(value) ~= "table" then
		addError(errors, "INVALID_APPEARANCE_GENOME", "Expected appearance genome table", nil)
		return finish(errors)
	end

	local genome = value :: { [any]: any }
	if genome.schemaVersion ~= 1 then
		addError(
			errors,
			"UNSUPPORTED_SCHEMA",
			"Appearance genome schemaVersion must be 1",
			"schemaVersion"
		)
	end

	for _, field in { "speciesId", "bodyVariantId", "paletteId", "patternId" } do
		validateIdentifier(errors, genome[field], field, "INVALID_APPEARANCE_TRAIT")
	end

	return finish(errors)
end

local function validateAbilityGenome(value: unknown): ValidationResult
	local errors: { DomainError } = {}
	if type(value) ~= "table" then
		addError(errors, "INVALID_ABILITY_GENOME", "Expected ability genome table", nil)
		return finish(errors)
	end

	local genome = value :: { [any]: any }
	if genome.schemaVersion ~= 1 then
		addError(
			errors,
			"UNSUPPORTED_SCHEMA",
			"Ability genome schemaVersion must be 1",
			"schemaVersion"
		)
	end
	validateAbilityIds(errors, genome.abilityIds, "abilityIds", true)

	return finish(errors)
end

local function appendNestedErrors(errors: { DomainError }, result: ValidationResult, prefix: string)
	if result.ok then
		return
	end

	for _, nestedError in result.errors do
		local path = prefix
		if nestedError.path ~= nil then
			path = `{prefix}.{nestedError.path}`
		end
		addError(errors, nestedError.code, nestedError.message, path)
	end
end

local function validateCritterDefinition(value: unknown): ValidationResult
	local errors: { DomainError } = {}
	if type(value) ~= "table" then
		addError(errors, "INVALID_CRITTER_DEFINITION", "Expected CritterDefinition table", nil)
		return finish(errors)
	end

	local definition = value :: { [any]: any }
	if definition.schemaVersion ~= 1 then
		addError(
			errors,
			"UNSUPPORTED_SCHEMA",
			"CritterDefinition schemaVersion must be 1",
			"schemaVersion"
		)
	end
	validateIdentifier(errors, definition.id, "id", "INVALID_CRITTER_DEFINITION_ID")
	if
		type(definition.displayName) ~= "string"
		or #definition.displayName < 1
		or #definition.displayName > 48
	then
		addError(
			errors,
			"INVALID_DISPLAY_NAME",
			"Expected display name with 1-48 characters",
			"displayName"
		)
	end
	if type(definition.class) ~= "string" or not VALID_CLASSES[definition.class] then
		addError(errors, "INVALID_CLASS", "Unknown Critter class", "class")
	end
	validateStats(errors, definition.baseStats, "baseStats")
	validateAbilityIds(errors, definition.abilityIds, "abilityIds", true)

	return finish(errors)
end

local function validateCritterInstance(
	value: unknown,
	definitionsById: RecordsById?,
	validAbilityIds: { [string]: boolean }?
): ValidationResult
	local errors: { DomainError } = {}
	if type(value) ~= "table" then
		addError(errors, "INVALID_CRITTER_INSTANCE", "Expected CritterInstance table", nil)
		return finish(errors)
	end

	local instance = value :: { [any]: any }
	if instance.schemaVersion ~= 1 then
		addError(
			errors,
			"UNSUPPORTED_SCHEMA",
			"CritterInstance schemaVersion must be 1",
			"schemaVersion"
		)
	end
	validateIdentifier(errors, instance.id, "id", "INVALID_CRITTER_INSTANCE_ID")
	validateIdentifier(
		errors,
		instance.definitionId,
		"definitionId",
		"INVALID_CRITTER_DEFINITION_ID"
	)
	if not isPositiveInteger(instance.ownerUserId) then
		addError(errors, "INVALID_OWNER", "ownerUserId must be a positive integer", "ownerUserId")
	end

	appendNestedErrors(
		errors,
		validateAppearanceGenome(instance.appearanceGenome),
		"appearanceGenome"
	)
	appendNestedErrors(errors, validateAbilityGenome(instance.abilityGenome), "abilityGenome")
	validateStats(errors, instance.baseStats, "baseStats")

	local acquisition = instance.acquisition
	if
		type(acquisition) ~= "table"
		or not isIdentifier(acquisition.source)
		or not isNonNegativeInteger(acquisition.acquiredAt)
		or not isPositiveInteger(acquisition.sourceVersion)
	then
		addError(
			errors,
			"INVALID_ACQUISITION",
			"Expected valid acquisition metadata",
			"acquisition"
		)
	end

	local breeding = instance.breeding
	local parentCount = if type(breeding) == "table"
		then getArrayLength(breeding.parentIds)
		else nil
	if
		type(breeding) ~= "table"
		or type(breeding.breedable) ~= "boolean"
		or not isNonNegativeInteger(breeding.generation)
		or parentCount == nil
		or parentCount > 2
	then
		addError(errors, "INVALID_BREEDING_FLAGS", "Expected valid breeding flags", "breeding")
	else
		for index, parentId in breeding.parentIds do
			validateIdentifier(
				errors,
				parentId,
				`breeding.parentIds[{index}]`,
				"INVALID_BREEDING_PARENT"
			)
		end
	end
	if type(instance.tradable) ~= "boolean" then
		addError(errors, "INVALID_TRADING_FLAG", "tradable must be boolean", "tradable")
	end
	local equipmentCount = getArrayLength(instance.equipmentIds)
	if equipmentCount == nil then
		addError(
			errors,
			"INVALID_EQUIPMENT_REFERENCES",
			"Expected dense equipment identifier array",
			"equipmentIds"
		)
	else
		for index, equipmentId in instance.equipmentIds do
			validateIdentifier(
				errors,
				equipmentId,
				`equipmentIds[{index}]`,
				"INVALID_EQUIPMENT_REFERENCE"
			)
		end
	end

	if
		definitionsById ~= nil
		and type(instance.definitionId) == "string"
		and definitionsById[instance.definitionId] == nil
	then
		addError(
			errors,
			"UNKNOWN_CRITTER_DEFINITION",
			"Critter definition does not exist",
			"definitionId"
		)
	end

	if validAbilityIds ~= nil and type(instance.abilityGenome) == "table" then
		local abilityIds = instance.abilityGenome.abilityIds
		if getArrayLength(abilityIds) ~= nil then
			for index, abilityId in abilityIds do
				if type(abilityId) == "string" and not validAbilityIds[abilityId] then
					addError(
						errors,
						"UNKNOWN_ABILITY",
						"Ability definition does not exist",
						`abilityGenome.abilityIds[{index}]`
					)
				end
			end
		end
	end

	return finish(errors)
end

local function validateCardEffects(errors: { DomainError }, value: unknown, path: string)
	if value == nil then
		return
	end

	local length = getArrayLength(value)
	if length == nil then
		addError(errors, "INVALID_CARD_EFFECTS", "Expected dense card effect array", path)
		return
	end
	if length > MAX_EFFECTS_PER_CARD then
		addError(
			errors,
			"INVALID_CARD_EFFECTS",
			`A card may declare at most {MAX_EFFECTS_PER_CARD} effects`,
			path
		)
		return
	end

	for index, effect in value :: { any } do
		local effectPath = `{path}[{index}]`
		if type(effect) ~= "table" then
			addError(errors, "INVALID_CARD_EFFECT", "Expected card effect table", effectPath)
			continue
		end

		local kind = effect.kind
		if type(kind) ~= "string" or not VALID_EFFECT_KINDS[kind] then
			addError(errors, "INVALID_EFFECT_KIND", "Unknown card effect kind", `{effectPath}.kind`)
			continue
		end

		if kind == "DAMAGE" or kind == "HEAL" or kind == "SHIELD" then
			if not isFiniteNumber(effect.amount) or effect.amount < 0 then
				addError(
					errors,
					"INVALID_EFFECT_AMOUNT",
					"Effect amount must be finite and non-negative",
					`{effectPath}.amount`
				)
			end
		elseif kind == "STATUS" then
			if type(effect.statusId) ~= "string" or not VALID_STATUS_IDS[effect.statusId] then
				addError(
					errors,
					"INVALID_STATUS_ID",
					"Unknown status identifier",
					`{effectPath}.statusId`
				)
			end
			if not isFiniteNumber(effect.magnitude) or effect.magnitude < 0 then
				addError(
					errors,
					"INVALID_STATUS_MAGNITUDE",
					"Status magnitude must be finite and non-negative",
					`{effectPath}.magnitude`
				)
			end
			if not isNonNegativeInteger(effect.duration) then
				addError(
					errors,
					"INVALID_STATUS_DURATION",
					"Status duration must be a non-negative integer",
					`{effectPath}.duration`
				)
			end
		end
	end
end

local function validateCardDefinition(
	value: unknown,
	validAbilityIds: { [string]: boolean }?
): ValidationResult
	local errors: { DomainError } = {}
	if type(value) ~= "table" then
		addError(errors, "INVALID_CARD_DEFINITION", "Expected CardDefinition table", nil)
		return finish(errors)
	end

	local definition = value :: { [any]: any }
	if definition.schemaVersion ~= 1 then
		addError(
			errors,
			"UNSUPPORTED_SCHEMA",
			"CardDefinition schemaVersion must be 1",
			"schemaVersion"
		)
	end
	validateIdentifier(errors, definition.id, "id", "INVALID_CARD_ID")
	validateIdentifier(errors, definition.abilityId, "abilityId", "INVALID_ABILITY_ID")
	if
		type(definition.displayName) ~= "string"
		or #definition.displayName < 1
		or #definition.displayName > 48
	then
		addError(
			errors,
			"INVALID_DISPLAY_NAME",
			"Expected display name with 1-48 characters",
			"displayName"
		)
	end
	if type(definition.class) ~= "string" or not VALID_CLASSES[definition.class] then
		addError(errors, "INVALID_CLASS", "Unknown Critter class", "class")
	end
	if not isNonNegativeInteger(definition.energyCost) then
		addError(
			errors,
			"INVALID_ENERGY_COST",
			"energyCost must be a non-negative integer",
			"energyCost"
		)
	end
	if
		type(definition.targetingRule) ~= "string"
		or not VALID_TARGETING_RULES[definition.targetingRule]
	then
		addError(errors, "INVALID_TARGETING_RULE", "Unknown targeting rule", "targetingRule")
	end
	validateCardEffects(errors, definition.effects, "effects")
	if
		validAbilityIds ~= nil
		and type(definition.abilityId) == "string"
		and not validAbilityIds[definition.abilityId]
	then
		addError(errors, "UNKNOWN_ABILITY", "Ability definition does not exist", "abilityId")
	end

	return finish(errors)
end

local function validateTeamComposition(
	teamValue: unknown,
	combatantsById: RecordsById
): ValidationResult
	local errors: { DomainError } = {}
	if type(teamValue) ~= "table" then
		addError(errors, "INVALID_TEAM", "Expected BattleTeam table", nil)
		return finish(errors)
	end

	local team = teamValue :: { [any]: any }
	validateIdentifier(errors, team.id, "id", "INVALID_TEAM_ID")
	if not isPositiveInteger(team.ownerUserId) then
		addError(errors, "INVALID_OWNER", "ownerUserId must be a positive integer", "ownerUserId")
	end

	local length = getArrayLength(team.combatantIds)
	if length ~= 3 then
		addError(
			errors,
			"INVALID_TEAM_SIZE",
			"Battle team must contain exactly three combatants",
			"combatantIds"
		)
		return finish(errors)
	end

	local seenCombatants: { [string]: boolean } = {}
	local seenCritters: { [string]: boolean } = {}
	local seenSlots: { [number]: boolean } = {}

	for index, combatantId in team.combatantIds do
		validateIdentifier(errors, combatantId, `combatantIds[{index}]`, "INVALID_COMBATANT_ID")
		if type(combatantId) == "string" then
			if seenCombatants[combatantId] then
				addError(
					errors,
					"DUPLICATE_COMBATANT",
					"Combatant identifiers must be unique",
					`combatantIds[{index}]`
				)
			end
			seenCombatants[combatantId] = true

			local combatant = combatantsById[combatantId]
			if combatant == nil then
				addError(
					errors,
					"UNKNOWN_COMBATANT",
					"Combatant does not exist",
					`combatantIds[{index}]`
				)
			else
				if combatant.teamId ~= team.id then
					addError(
						errors,
						"INVALID_COMBATANT_TEAM",
						"Combatant belongs to another team",
						`combatantIds[{index}]`
					)
				end
				if
					not isPositiveInteger(combatant.slot)
					or combatant.slot > 3
					or seenSlots[combatant.slot]
				then
					addError(
						errors,
						"INVALID_TEAM_SLOT",
						"Team slots must be unique values 1-3",
						`combatantIds[{index}]`
					)
				else
					seenSlots[combatant.slot] = true
				end
				if type(combatant.critterInstanceId) == "string" then
					if seenCritters[combatant.critterInstanceId] then
						addError(
							errors,
							"DUPLICATE_CRITTER",
							"Creature instance identifiers must be unique",
							`combatantIds[{index}]`
						)
					end
					seenCritters[combatant.critterInstanceId] = true
				else
					addError(
						errors,
						"INVALID_CRITTER_INSTANCE_ID",
						"Combatant needs a creature instance",
						`combatantIds[{index}]`
					)
				end
			end
		end
	end

	return finish(errors)
end

local function validateTarget(
	errors: { DomainError },
	queuedCard: AnyRecord,
	cardDefinition: AnyRecord,
	sourceCombatant: AnyRecord,
	combatantsById: RecordsById,
	path: string
)
	local rule = cardDefinition.targetingRule
	if type(rule) == "string" and TargetingRules.isAutomatic(rule) then
		local derivedCount = getArrayLength(queuedCard.targetCombatantIds)
		if derivedCount ~= 0 then
			addError(
				errors,
				"INVALID_TARGET_COUNT",
				"Automatic targeting rules require an empty client target list",
				`{path}.targetCombatantIds`
			)
		end
		return
	end

	local targetCount = getArrayLength(queuedCard.targetCombatantIds)
	if targetCount ~= 1 then
		addError(
			errors,
			"INVALID_TARGET_COUNT",
			"Targeting rule requires exactly one target",
			`{path}.targetCombatantIds`
		)
		return
	end

	local targetId = queuedCard.targetCombatantIds[1]
	local target = combatantsById[targetId]
	if target == nil then
		addError(
			errors,
			"INVALID_TARGET",
			"Target combatant does not exist",
			`{path}.targetCombatantIds[1]`
		)
		return
	end

	local legal = rule == "ANY"
		or (
			rule == "ALLY"
			and target.teamId == sourceCombatant.teamId
			and targetId ~= sourceCombatant.id
		)

	if not legal then
		addError(
			errors,
			"INVALID_TARGET",
			"Target does not satisfy card targeting rule",
			`{path}.targetCombatantIds[1]`
		)
	end
end

local function validateBattleCommand(
	value: unknown,
	context: BattleValidationContext
): ValidationResult
	local errors: { DomainError } = {}
	if type(value) ~= "table" then
		addError(errors, "INVALID_BATTLE_COMMAND", "Expected BattleCommand table", nil)
		return finish(errors)
	end

	local command = value :: { [any]: any }
	if command.commandType ~= "COMMIT_PLAN" then
		addError(errors, "INVALID_COMMAND_KIND", "Expected COMMIT_PLAN command", "commandType")
	end
	validateIdentifier(errors, command.id, "id", "INVALID_COMMAND_ID")
	validateIdentifier(errors, command.battleId, "battleId", "INVALID_BATTLE_ID")
	if command.actorUserId ~= context.team.ownerUserId or command.teamId ~= context.team.id then
		addError(errors, "INVALID_OWNERSHIP", "Command actor does not own team", "actorUserId")
	end

	local queueLength = getArrayLength(command.queuedCards)
	if queueLength == nil or queueLength > 24 then
		addError(
			errors,
			"INVALID_QUEUE_LENGTH",
			"Queued cards must be a dense array with at most 24 entries",
			"queuedCards"
		)
		return finish(errors)
	end

	local hand: { [string]: boolean } = {}
	for _, cardInstanceId in context.handCardInstanceIds do
		hand[cardInstanceId] = true
	end

	local submittedCards: { [string]: boolean } = {}
	local queueIndicesBySource: { [string]: { number } } = {}
	local spentEnergy = 0

	for index, queuedValue in command.queuedCards do
		local path = `queuedCards[{index}]`
		if type(queuedValue) ~= "table" then
			addError(errors, "INVALID_QUEUED_CARD", "Expected QueuedCard table", path)
			continue
		end

		local queuedCard = queuedValue :: { [any]: any }
		validateIdentifier(
			errors,
			queuedCard.cardInstanceId,
			`{path}.cardInstanceId`,
			"INVALID_CARD_ID"
		)
		validateIdentifier(
			errors,
			queuedCard.sourceCombatantId,
			`{path}.sourceCombatantId`,
			"INVALID_COMBATANT_ID"
		)
		if not isPositiveInteger(queuedCard.queueIndex) then
			addError(
				errors,
				"INVALID_QUEUE_INDEX",
				"queueIndex must be a positive integer",
				`{path}.queueIndex`
			)
		end

		local cardInstanceId = queuedCard.cardInstanceId
		if type(cardInstanceId) ~= "string" then
			continue
		end
		if submittedCards[cardInstanceId] then
			addError(
				errors,
				"DUPLICATE_CARD",
				"Card instance may be submitted only once",
				`{path}.cardInstanceId`
			)
		end
		submittedCards[cardInstanceId] = true
		if not hand[cardInstanceId] then
			addError(
				errors,
				"CARD_NOT_IN_HAND",
				"Card instance is not available in hand",
				`{path}.cardInstanceId`
			)
		end

		local sourceId = queuedCard.sourceCombatantId
		local sourceCombatant = context.combatantsById[sourceId]
		local cardInstance = context.cardInstancesById[cardInstanceId]
		if sourceCombatant == nil or not hasString(context.team.combatantIds, sourceId) then
			addError(
				errors,
				"INVALID_OWNERSHIP",
				"Source combatant does not belong to team",
				`{path}.sourceCombatantId`
			)
			continue
		end
		if cardInstance == nil then
			addError(
				errors,
				"UNKNOWN_CARD_INSTANCE",
				"Card instance does not exist",
				`{path}.cardInstanceId`
			)
			continue
		end
		if cardInstance.sourceCritterInstanceId ~= sourceCombatant.critterInstanceId then
			addError(
				errors,
				"INVALID_OWNERSHIP",
				"Card does not belong to source Critter",
				`{path}.cardInstanceId`
			)
		end

		local cardDefinition = context.cardDefinitionsById[cardInstance.definitionId]
		if cardDefinition == nil then
			addError(
				errors,
				"UNKNOWN_CARD_DEFINITION",
				"Card definition does not exist",
				`{path}.cardInstanceId`
			)
			continue
		end
		if cardDefinition.class ~= sourceCombatant.class then
			addError(
				errors,
				"INVALID_CLASS_REFERENCE",
				"Card class does not match source Critter",
				`{path}.cardInstanceId`
			)
		end
		if not hasString(sourceCombatant.abilityIds, cardDefinition.abilityId) then
			addError(
				errors,
				"INVALID_ABILITY_REFERENCE",
				"Source Critter does not own card ability",
				`{path}.cardInstanceId`
			)
		end
		if isNonNegativeInteger(cardDefinition.energyCost) then
			spentEnergy += cardDefinition.energyCost
		end
		validateTarget(
			errors,
			queuedCard,
			cardDefinition,
			sourceCombatant,
			context.combatantsById,
			path
		)

		if type(sourceId) == "string" and isPositiveInteger(queuedCard.queueIndex) then
			local indices = queueIndicesBySource[sourceId]
			if indices == nil then
				indices = {}
				queueIndicesBySource[sourceId] = indices
			end
			table.insert(indices, queuedCard.queueIndex)
		end
	end

	for sourceId, indices in queueIndicesBySource do
		table.sort(indices)
		for expected, actual in indices do
			if actual ~= expected then
				addError(
					errors,
					"INVALID_QUEUE_ORDER",
					"Per-Critter queue indices must be contiguous from one",
					`queuedCards.{sourceId}`
				)
				break
			end
		end
	end

	if
		not isNonNegativeInteger(context.availableEnergy)
		or spentEnergy > context.availableEnergy
	then
		addError(
			errors,
			"INSUFFICIENT_ENERGY",
			"Queued cards exceed available energy",
			"queuedCards"
		)
	end

	return finish(errors)
end

return table.freeze({
	isIdentifier = isIdentifier,
	validateAppearanceGenome = validateAppearanceGenome,
	validateAbilityGenome = validateAbilityGenome,
	validateCritterDefinition = validateCritterDefinition,
	validateCritterInstance = validateCritterInstance,
	validateCardDefinition = validateCardDefinition,
	validateTeamComposition = validateTeamComposition,
	validateBattleCommand = validateBattleCommand,
})
