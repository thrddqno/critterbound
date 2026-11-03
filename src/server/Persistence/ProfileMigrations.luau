--!strict

local ProfileMigrations = {}

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
})
return table.freeze(ProfileMigrations)
