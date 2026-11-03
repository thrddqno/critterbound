--!strict

local ProfileRepository = {}

local RECORD_VERSION = 1

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
	return { ok = false, errors = { { code = code, message = message } } }
end

local function new(dependencies)
	local deps = dependencies
	local repository = {}

	local function keyFor(userId: number): string
		return `player:{userId}`
	end

	local function updateWithRetry(key: string, transform)
		local lastError = nil
		for attempt = 1, deps.maxAttempts do
			local semanticFailure = nil
			local ok, value = pcall(function()
				return deps.store:UpdateAsync(key, function(current)
					local transformed = transform(clone(current))
					if not transformed.ok then
						semanticFailure = transformed
						return nil
					end
					semanticFailure = nil
					return transformed.value
				end)
			end)
			if ok then
				if semanticFailure ~= nil then
					return semanticFailure
				end
				return { ok = true, value = clone(value) }
			end
			lastError = value
			if attempt < deps.maxAttempts then
				local delay = math.min(deps.baseDelay * (2 ^ (attempt - 1)), deps.maxDelay)
				deps.wait(delay + deps.jitter())
			end
		end
		deps.log(
			`DataStore operation failed after {deps.maxAttempts} attempts: {tostring(lastError)}`
		)
		return failure("DATASTORE_UNAVAILABLE", "Player data is temporarily unavailable")
	end

	local function load(userId: number)
		local now = deps.clock()
		local token = deps.generateId()
		local preparedStarters =
			deps.starterGrant.prepare(userId, now, deps.generateId, deps.catalog)
		local key = keyFor(userId)
		local result = updateWithRetry(key, function(current)
			local isNew = current == nil
			local record = current
			if isNew then
				record = {
					recordVersion = RECORD_VERSION,
					profile = deps.schema.create(userId, now),
					sessionLock = nil,
				}
			elseif type(record) ~= "table" or record.recordVersion ~= RECORD_VERSION then
				return failure("CORRUPT_PROFILE", "Stored profile record is malformed")
			end

			local lock = record.sessionLock
			if lock ~= nil then
				if
					type(lock) ~= "table"
					or type(lock.token) ~= "string"
					or type(lock.jobId) ~= "string"
					or type(lock.expiresAt) ~= "number"
					or lock.expiresAt ~= lock.expiresAt
				then
					return failure("CORRUPT_PROFILE", "Stored profile session lock is malformed")
				end
				if lock.token ~= token and lock.expiresAt > now then
					return failure(
						"PROFILE_SESSION_ACTIVE",
						"Player data is active on another server"
					)
				end
			end

			local migrated = deps.migrations.migrate(
				record.profile,
				deps.schema.CurrentVersion,
				deps.migrationHooks
			)
			if not migrated.ok then
				return migrated
			end
			local profile = migrated.value
			local validation = deps.schema.validate(profile, userId, deps.catalog.allById(), isNew)
			if not validation.ok then
				return validation
			end
			if profile.starterGrantVersion < deps.starterGrant.Version then
				local granted = deps.starterGrant.apply(profile, preparedStarters)
				if not granted.ok then
					return granted
				end
				profile = granted.value
			end
			profile.updatedAt = now
			local finalValidation = deps.schema.validate(profile, userId, deps.catalog.allById())
			if not finalValidation.ok then
				return finalValidation
			end
			return {
				ok = true,
				value = {
					recordVersion = RECORD_VERSION,
					profile = clone(profile),
					sessionLock = {
						token = token,
						jobId = deps.jobId,
						expiresAt = now + deps.leaseSeconds,
					},
				},
			}
		end)
		if not result.ok then
			return result
		end
		return {
			ok = true,
			value = {
				userId = userId,
				key = key,
				lockToken = token,
				profile = clone(result.value.profile),
			},
		}
	end

	local function save(handle, candidateProfile)
		local now = deps.clock()
		local profile = clone(candidateProfile or handle.profile)
		profile.revision += 1
		profile.updatedAt = now
		local validation = deps.schema.validate(profile, handle.userId, deps.catalog.allById())
		if not validation.ok then
			return validation
		end
		local result = updateWithRetry(handle.key, function(current)
			if type(current) ~= "table" or current.recordVersion ~= RECORD_VERSION then
				return failure("CORRUPT_PROFILE", "Stored profile record is malformed")
			end
			local lock = current.sessionLock
			if type(lock) ~= "table" or lock.token ~= handle.lockToken then
				return failure("PROFILE_LOCK_LOST", "Profile session ownership was lost")
			end
			return {
				ok = true,
				value = {
					recordVersion = RECORD_VERSION,
					profile = clone(profile),
					sessionLock = {
						token = handle.lockToken,
						jobId = deps.jobId,
						expiresAt = now + deps.leaseSeconds,
					},
				},
			}
		end)
		if not result.ok then
			return result
		end
		handle.profile = clone(profile)
		return { ok = true, value = clone(profile) }
	end

	local function release(handle)
		local now = deps.clock()
		local profile = clone(handle.profile)
		profile.revision += 1
		profile.updatedAt = now
		local validation = deps.schema.validate(profile, handle.userId, deps.catalog.allById())
		if not validation.ok then
			return validation
		end
		local result = updateWithRetry(handle.key, function(current)
			if type(current) ~= "table" or current.recordVersion ~= RECORD_VERSION then
				return failure("CORRUPT_PROFILE", "Stored profile record is malformed")
			end
			local lock = current.sessionLock
			if
				lock == nil
				and type(current.profile) == "table"
				and current.profile.userId == handle.userId
				and current.profile.revision == profile.revision
				and current.profile.updatedAt == profile.updatedAt
			then
				return { ok = true, value = current }
			end
			if type(lock) ~= "table" or lock.token ~= handle.lockToken then
				return failure("PROFILE_LOCK_LOST", "Profile session ownership was lost")
			end
			return {
				ok = true,
				value = {
					recordVersion = RECORD_VERSION,
					profile = clone(profile),
					sessionLock = nil,
				},
			}
		end)
		if not result.ok then
			return result
		end
		handle.profile = clone(profile)
		return { ok = true, value = clone(profile) }
	end

	repository.load = load
	repository.save = save
	repository.release = release
	return table.freeze(repository)
end

ProfileRepository.new = new
return table.freeze(ProfileRepository)
