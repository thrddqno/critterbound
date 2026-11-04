--!strict

local TradeEligibilityService = {}

local function failure(code, message)
	return { ok = false, errors = { { code = code, message = message } } }
end

local function new(dependencies)
	local deps = dependencies
	local service = {}

	local function validateSnapshot(userId, critterId, allowedLockToken)
		local profileResult = deps.profileService.ReadProfile(userId)
		if not profileResult.ok then
			return profileResult
		end
		local lock = deps.profileService.GetOwnershipLock(critterId)
		return deps.validator.validate(
			profileResult.value,
			userId,
			critterId,
			lock,
			allowedLockToken
		)
	end

	local function checkEligibility(userId, critterId)
		return validateSnapshot(userId, critterId, nil)
	end

	local function validateTransferCandidate(profile, userId, critterId, lockToken)
		local lock = deps.profileService.GetOwnershipLock(critterId)
		if
			lock == nil
			or lock.token ~= lockToken
			or lock.ownerUserId ~= userId
			or lock.operationType ~= "TRANSFER"
		then
			return failure("TRANSFER_LOCK_REQUIRED", "Active transfer ownership lock is required")
		end
		return deps.validator.validate(profile, userId, critterId, lock, lockToken)
	end

	local function acquireTransferLock(userId, critterId)
		local initial = checkEligibility(userId, critterId)
		if not initial.ok then
			return initial
		end
		local acquired =
			deps.profileService.AcquireOwnershipLocks(userId, { critterId }, "TRANSFER")
		if not acquired.ok then
			return acquired
		end
		local token = acquired.value.token
		local revalidated = validateSnapshot(userId, critterId, token)
		if not revalidated.ok then
			deps.profileService.ReleaseOwnershipLocks(userId, token)
			return revalidated
		end
		return {
			ok = true,
			value = {
				critterId = critterId,
				lockToken = token,
				expiresAt = acquired.value.expiresAt,
			},
		}
	end

	local function revalidateTransfer(userId, critterId, lockToken)
		local profileResult = deps.profileService.ReadProfile(userId)
		if not profileResult.ok then
			return profileResult
		end
		local validation =
			validateTransferCandidate(profileResult.value, userId, critterId, lockToken)
		if not validation.ok then
			deps.profileService.ReleaseOwnershipLocks(userId, lockToken)
		end
		return validation
	end

	local function releaseTransferLock(userId, lockToken)
		return deps.profileService.ReleaseOwnershipLocks(userId, lockToken)
	end

	service.CheckEligibility = checkEligibility
	service.AcquireTransferLock = acquireTransferLock
	service.ValidateTransferCandidate = validateTransferCandidate
	service.RevalidateTransfer = revalidateTransfer
	service.ReleaseTransferLock = releaseTransferLock
	return table.freeze(service)
end

TradeEligibilityService.new = new
return table.freeze(TradeEligibilityService)
