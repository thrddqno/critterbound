--!strict

local ProfileMigrations = {}

local function requireShared(folder: string, name: string)
	if script ~= nil then
		return require(game:GetService("ReplicatedStorage").Shared[folder][name])
	end
	return require(`../../shared/{folder}/{name}`)
end

local CritterCatalog = requireShared("Definitions", "CritterCatalog")
local GeneRegistry = requireShared("Genetics", "GeneRegistry")

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

local function failure(code: string, message: string)
	return { ok = false, errors = { { code = code, message = message, path = "schemaVersion" } } }
end

local function arrayLength(value): number?
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

local function migrate(profile, currentVersion: number, hooks)
	if type(profile) ~= "table" or type(profile.schemaVersion) ~= "number" then
		return failure("CORRUPT_PROFILE", "Profile schemaVersion is missing")
	end
	if profile.schemaVersion > currentVersion then
		return failure("FUTURE_PROFILE_SCHEMA", "Profile was written by a newer server")
	end
	local value = profile
	while value.schemaVersion < currentVersion do
		local hook = hooks and hooks[value.schemaVersion]
		if type(hook) ~= "function" then
			return failure("MISSING_PROFILE_MIGRATION", "Profile migration path is incomplete")
		end
		local previousVersion = value.schemaVersion
		local ok, migrated = pcall(hook, value)
		if not ok or type(migrated) ~= "table" or migrated.schemaVersion ~= previousVersion + 1 then
			return failure("PROFILE_MIGRATION_FAILED", "Profile migration failed validation")
		end
		value = migrated
	end
	return { ok = true, value = value }
end

ProfileMigrations.migrate = migrate
ProfileMigrations.DefaultHooks = table.freeze({
	[1] = function(profile)
		if
			type(profile.inventory) ~= "table"
			or profile.inventory.schemaVersion ~= 1
			or type(profile.inventory.itemsById) ~= "table"
			or next(profile.inventory.itemsById) ~= nil
		then
			error("Run 6A inventory placeholder is corrupt")
		end
		local migrated = clone(profile)
		migrated.schemaVersion = 2
		migrated.inventory = {
			schemaVersion = 2,
			stacksByDefinitionId = {},
			uniqueItemsById = {},
			operationsById = {},
			operationOrder = {},
		}
		return migrated
	end,
	[2] = function(profile)
		if type(profile.ownedCritters) ~= "table" then
			error("Owned Critter collection is corrupt")
		end
		local migrated = clone(profile)
		for id, instance in migrated.ownedCritters do
			if
				type(id) ~= "string"
				or type(instance) ~= "table"
				or instance.schemaVersion ~= 1
				or type(instance.appearanceGenome) ~= "table"
				or instance.appearanceGenome.schemaVersion ~= 1
				or type(instance.abilityGenome) ~= "table"
				or instance.abilityGenome.schemaVersion ~= 1
			then
				error("Legacy Critter genome is corrupt")
			end
			local definition = CritterCatalog.getById(instance.definitionId)
			if definition == nil then
				error("Legacy Critter definition is unknown")
			end
			local appearance = instance.appearanceGenome
			local expectedSpecies = `starter.{string.lower(definition.class)}`
			if
				appearance.speciesId ~= expectedSpecies
				or appearance.bodyVariantId ~= "placeholder"
				or appearance.paletteId ~= "starter"
				or appearance.patternId ~= "placeholder"
			then
				error("Unknown legacy appearance combination")
			end
			local abilityIds = instance.abilityGenome.abilityIds
			if arrayLength(abilityIds) ~= 4 then
				error("Legacy abilities are corrupt")
			end
			for index, expectedAbilityId in definition.abilityIds do
				if abilityIds[index] ~= expectedAbilityId then
					error("Unknown legacy ability combination")
				end
			end
			local genomes = GeneRegistry.defaultGenomes(definition.class)
			if genomes == nil then
				error("Default genomes are unavailable")
			end
			instance.schemaVersion = 2
			instance.appearanceGenome = genomes.appearanceGenome
			instance.abilityGenome = genomes.abilityGenome
		end
		migrated.schemaVersion = 3
		return migrated
	end,
	[3] = function(profile)
		if type(profile.ownedCritters) ~= "table" then
			error("Owned Critter collection is corrupt")
		end
		local migrated = clone(profile)
		for _, instance in migrated.ownedCritters do
			if type(instance) ~= "table" or type(instance.breeding) ~= "table" then
				error("Owned Critter breeding flags are corrupt")
			end
			if type(instance.breeding.successfulBreedCount) ~= "number" then
				instance.breeding.successfulBreedCount = 0
			end
		end
		if type(migrated.eggs) ~= "table" then
			migrated.eggs = {}
		end
		if type(migrated.breedingOperationsById) ~= "table" then
			migrated.breedingOperationsById = {}
		end
		if type(migrated.breedingOperationOrder) ~= "table" then
			migrated.breedingOperationOrder = {}
		end
		migrated.schemaVersion = 4
		return migrated
	end,
	[4] = function(profile)
		if type(profile.ownedCritters) ~= "table" then
			error("Owned Critter collection is corrupt")
		end
		if
			profile.acquisitionOperationsById ~= nil
			and type(profile.acquisitionOperationsById) ~= "table"
		then
			error("Acquisition operation records are corrupt")
		end
		if
			profile.acquisitionOperationOrder ~= nil
			and type(profile.acquisitionOperationOrder) ~= "table"
		then
			error("Acquisition operation order is corrupt")
		end
		local migrated = clone(profile)
		migrated.acquisitionOperationsById = {}
		migrated.acquisitionOperationOrder = {}
		migrated.schemaVersion = 5
		return migrated
	end,
	[5] = function(profile)
		if type(profile.ownedCritters) ~= "table" then
			error("Owned Critter collection is corrupt")
		end
		local migrated = clone(profile)
		migrated.contracts = {
			schemaVersion = 1,
			instancesById = {},
			instanceOrder = {},
			entitlementsById = {},
			entitlementOrder = {},
			redemptionsById = {},
			redemptionOrder = {},
		}
		migrated.schemaVersion = 6
		return migrated
	end,
	[6] = function(profile)
		if
			type(profile.contracts) ~= "table"
			or profile.contracts.schemaVersion ~= 1
			or type(profile.contracts.instancesById) ~= "table"
		then
			error("Contract state is corrupt")
		end
		local migrated = clone(profile)
		local contracts = migrated.contracts
		contracts.schemaVersion = 2
		contracts.battleCompletionsById = {}
		contracts.battleCompletionOrder = {}
		for _, contractId in contracts.instanceOrder do
			local instance = contracts.instancesById[contractId]
			if
				type(instance) == "table"
				and (instance.status == "COMPLETED" or instance.status == "CLAIMED")
			then
				if type(instance.completedBattleId) ~= "string" then
					error("Completed contract evidence is corrupt")
				end
				if contracts.battleCompletionsById[instance.completedBattleId] ~= nil then
					error("Duplicate battle completion evidence is corrupt")
				end
				contracts.battleCompletionsById[instance.completedBattleId] = {
					schemaVersion = 1,
					battleId = instance.completedBattleId,
					contractInstanceId = contractId,
					ownerUserId = instance.ownerUserId,
					completedAt = instance.completedAt,
				}
				table.insert(contracts.battleCompletionOrder, instance.completedBattleId)
			end
		end
		migrated.schemaVersion = 7
		return migrated
	end,
	[7] = function(profile)
		if type(profile.ownedCritters) ~= "table" then
			error("Owned Critter collection is corrupt")
		end
		local migrated = clone(profile)
		for _, instance in migrated.ownedCritters do
			if
				type(instance) ~= "table"
				or instance.schemaVersion ~= 2
				or type(instance.baseStats) ~= "table"
			then
				error("Legacy Critter stats are corrupt")
			end
			for _, field in { "maxHealth", "attack", "defense", "speed" } do
				local value = instance.baseStats[field]
				if type(value) ~= "number" or value ~= value or value < 0 or value == math.huge then
					error("Legacy Critter stats are corrupt")
				end
			end
			local definition = CritterCatalog.getById(instance.definitionId)
			if definition == nil then
				error("Legacy Critter definition is unknown")
			end
			instance.schemaVersion = 3
			-- No inherited stat variation exists yet. Use class baseline rather than treating
			-- legacy maxHealth as the new Health attribute.
			instance.baseStats = clone(definition.baseStats)
		end
		migrated.schemaVersion = 8
		return migrated
	end,
})
return table.freeze(ProfileMigrations)
