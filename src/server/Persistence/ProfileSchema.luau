--!strict

local ProfileSchema = {}

local function requireShared(folder: string, name: string)
	if script ~= nil then
		return require(game:GetService("ReplicatedStorage").Shared[folder][name])
	end
	return require(`../../shared/{folder}/{name}`)
end

local InventoryValidator = requireShared("Validation", "InventoryValidator")
local TeamValidator = requireShared("Validation", "TeamValidator")
local ItemRegistry = requireShared("Items", "ItemRegistry")

local CURRENT_VERSION = 2
local MAX_OWNED_CRITTERS = 500

local function clone<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, child in value :: any do
		result[clone(key)] = clone(child)
	end
	return result :: any
end

local function failure(code: string, message: string, path: string?)
	return { ok = false, errors = { { code = code, message = message, path = path } } }
end

local function isInteger(value: any, minimum: number): boolean
	return type(value) == "number"
		and value == value
		and value < math.huge
		and value >= minimum
		and value % 1 == 0
end

local function isIdentifier(value: any): boolean
	return type(value) == "string"
		and #value >= 1
		and #value <= 96
		and string.match(value, "^[%w][%w_.:%-]*$") ~= nil
end

local function arrayLength(value: any): number?
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
	return if count == maximum then count else nil
end

local function validStats(stats: any): boolean
	if type(stats) ~= "table" then
		return false
	end
	for _, field in { "maxHealth", "attack", "defense", "speed" } do
		local value = stats[field]
		if type(value) ~= "number" or value ~= value or value < 0 or value == math.huge then
			return false
		end
	end
	if stats.maxHealth <= 0 then
		return false
	end
	for _, field in { "skill", "resolve" } do
		local value = stats[field]
		if
			value ~= nil
			and (type(value) ~= "number" or value ~= value or value < 0 or value == math.huge)
		then
			return false
		end
	end
	return true
end

local function validateInstance(instance: any, id: string, userId: number, definitionsById: any)
	if type(instance) ~= "table" or instance.schemaVersion ~= 1 or instance.id ~= id then
		return failure(
			"INVALID_CRITTER_INSTANCE",
			"Owned Critter record is malformed",
			`ownedCritters.{id}`
		)
	end
	if
		not isIdentifier(id)
		or instance.ownerUserId ~= userId
		or not isIdentifier(instance.definitionId)
	then
		return failure(
			"INVALID_CRITTER_OWNERSHIP",
			"Owned Critter identity or owner is invalid",
			`ownedCritters.{id}`
		)
	end
	local definition = definitionsById[instance.definitionId]
	if definition == nil then
		return failure(
			"UNKNOWN_CRITTER_DEFINITION",
			"Owned Critter definition is unknown",
			`ownedCritters.{id}.definitionId`
		)
	end
	if not validStats(instance.baseStats) then
		return failure(
			"INVALID_CRITTER_STATS",
			"Owned Critter base stats are invalid",
			`ownedCritters.{id}.baseStats`
		)
	end
	local appearance = instance.appearanceGenome
	if type(appearance) ~= "table" or appearance.schemaVersion ~= 1 then
		return failure(
			"INVALID_APPEARANCE_GENOME",
			"Appearance genome is malformed",
			`ownedCritters.{id}.appearanceGenome`
		)
	end
	for _, field in { "speciesId", "bodyVariantId", "paletteId", "patternId" } do
		if not isIdentifier(appearance[field]) then
			return failure(
				"INVALID_APPEARANCE_GENOME",
				"Appearance trait is invalid",
				`ownedCritters.{id}.appearanceGenome.{field}`
			)
		end
	end
	local ability = instance.abilityGenome
	if
		type(ability) ~= "table"
		or ability.schemaVersion ~= 1
		or arrayLength(ability.abilityIds) ~= 4
	then
		return failure(
			"INVALID_ABILITY_GENOME",
			"Ability genome is malformed",
			`ownedCritters.{id}.abilityGenome`
		)
	end
	local knownAbilities = {}
	for _, abilityId in definition.abilityIds do
		knownAbilities[abilityId] = true
	end
	local seenAbilities = {}
	for index, abilityId in ability.abilityIds do
		if
			not isIdentifier(abilityId)
			or not knownAbilities[abilityId]
			or seenAbilities[abilityId]
		then
			return failure(
				"INVALID_ABILITY_GENOME",
				"Ability genome contains invalid abilities",
				`ownedCritters.{id}.abilityGenome.abilityIds[{index}]`
			)
		end
		seenAbilities[abilityId] = true
	end
	local acquisition = instance.acquisition
	if
		type(acquisition) ~= "table"
		or not isIdentifier(acquisition.source)
		or not isInteger(acquisition.acquiredAt, 0)
		or not isInteger(acquisition.sourceVersion, 1)
	then
		return failure(
			"INVALID_ACQUISITION",
			"Acquisition metadata is malformed",
			`ownedCritters.{id}.acquisition`
		)
	end
	local breeding = instance.breeding
	local parentCount = if type(breeding) == "table" then arrayLength(breeding.parentIds) else nil
	if
		type(breeding) ~= "table"
		or type(breeding.breedable) ~= "boolean"
		or not isInteger(breeding.generation, 0)
		or parentCount == nil
		or parentCount > 2
	then
		return failure(
			"INVALID_BREEDING_FLAGS",
			"Breeding flags are malformed",
			`ownedCritters.{id}.breeding`
		)
	end
	for index, parentId in breeding.parentIds do
		if not isIdentifier(parentId) then
			return failure(
				"INVALID_BREEDING_FLAGS",
				"Breeding parent reference is invalid",
				`ownedCritters.{id}.breeding.parentIds[{index}]`
			)
		end
	end
	local equipmentCount = arrayLength(instance.equipmentIds)
	if type(instance.tradable) ~= "boolean" or equipmentCount == nil or equipmentCount > 1 then
		return failure(
			"INVALID_CRITTER_REFERENCES",
			"Trading or equipment references are malformed",
			`ownedCritters.{id}`
		)
	end
	for index, equipmentId in instance.equipmentIds do
		if not isIdentifier(equipmentId) then
			return failure(
				"INVALID_EQUIPMENT_REFERENCE",
				"Equipment reference is invalid",
				`ownedCritters.{id}.equipmentIds[{index}]`
			)
		end
	end
	return { ok = true, value = true }
end

local function create(userId: number, now: number)
	return {
		schemaVersion = CURRENT_VERSION,
		userId = userId,
		revision = 0,
		createdAt = now,
		updatedAt = now,
		starterGrantVersion = 0,
		ownedCritters = {},
		selectedTeam = {},
		inventory = {
			schemaVersion = 2,
			stacksByDefinitionId = {},
			uniqueItemsById = {},
			operationsById = {},
			operationOrder = {},
		},
		progression = { schemaVersion = 1, flags = {}, counters = {} },
	}
end

local function validate(
	profile: any,
	expectedUserId: number,
	definitionsById: any,
	allowEmptyTeam: boolean?
)
	if type(profile) ~= "table" then
		return failure("CORRUPT_PROFILE", "Profile must be a table", nil)
	end
	if profile.schemaVersion ~= CURRENT_VERSION then
		return failure(
			"UNSUPPORTED_PROFILE_SCHEMA",
			"Profile schema version is unsupported",
			"schemaVersion"
		)
	end
	if profile.userId ~= expectedUserId or not isInteger(profile.userId, 1) then
		return failure(
			"PROFILE_USER_MISMATCH",
			"Profile user does not match DataStore key",
			"userId"
		)
	end
	for _, field in { "revision", "createdAt", "updatedAt", "starterGrantVersion" } do
		if not isInteger(profile[field], 0) then
			return failure("CORRUPT_PROFILE", `Profile {field} is invalid`, field)
		end
	end
	if type(profile.ownedCritters) ~= "table" then
		return failure("CORRUPT_PROFILE", "ownedCritters must be a table", "ownedCritters")
	end
	local ownedCount = 0
	for id, instance in profile.ownedCritters do
		ownedCount += 1
		if ownedCount > MAX_OWNED_CRITTERS then
			return failure(
				"CRITTER_LIMIT_EXCEEDED",
				"Owned Critter limit exceeded",
				"ownedCritters"
			)
		end
		if type(id) ~= "string" then
			return failure(
				"INVALID_CRITTER_INSTANCE",
				"Owned Critter keys must be strings",
				"ownedCritters"
			)
		end
		local result = validateInstance(instance, id, expectedUserId, definitionsById)
		if not result.ok then
			return result
		end
	end
	local teamValidation = TeamValidator.validateTeam(
		profile.selectedTeam,
		expectedUserId,
		profile.ownedCritters,
		definitionsById,
		allowEmptyTeam
	)
	if not teamValidation.ok then
		return teamValidation
	end
	local inventoryValidation = InventoryValidator.validateInventory(
		profile.inventory,
		expectedUserId,
		profile.ownedCritters,
		ItemRegistry
	)
	if not inventoryValidation.ok then
		return inventoryValidation
	end
	if
		type(profile.progression) ~= "table"
		or profile.progression.schemaVersion ~= 1
		or type(profile.progression.flags) ~= "table"
		or type(profile.progression.counters) ~= "table"
		or next(profile.progression.flags) ~= nil
		or next(profile.progression.counters) ~= nil
	then
		return failure(
			"INVALID_PROGRESSION_PLACEHOLDER",
			"Progression placeholder is malformed",
			"progression"
		)
	end
	return { ok = true, value = true }
end

ProfileSchema.CurrentVersion = CURRENT_VERSION
ProfileSchema.clone = clone
ProfileSchema.create = create
ProfileSchema.validate = validate
return table.freeze(ProfileSchema)
