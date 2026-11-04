--!strict

local TradeEligibilityValidator = {}

local function failure(code, message, path)
	return { ok = false, errors = { { code = code, message = message, path = path } } }
end

local function isIdentifier(value): boolean
	return type(value) == "string"
		and #value >= 1
		and #value <= 96
		and string.match(value, "^[%w][%w_.:%-]*$") ~= nil
end

local function contains(values, expected): boolean
	if type(values) ~= "table" then
		return false
	end
	for _, value in values do
		if value == expected then
			return true
		end
	end
	return false
end

local function validate(profile, userId, critterId, lock, allowedLockToken)
	if type(profile) ~= "table" or type(profile.ownedCritters) ~= "table" then
		return failure("PROFILE_INVALID", "Profile is invalid", nil)
	end
	if not isIdentifier(critterId) then
		return failure("INVALID_CRITTER_ID", "Critter ID is malformed", "critterId")
	end
	local critter = profile.ownedCritters[critterId]
	if critter == nil then
		return failure("CRITTER_NOT_FOUND", "Critter does not exist", "critterId")
	end
	if profile.userId ~= userId or critter.ownerUserId ~= userId then
		return failure("CRITTER_NOT_OWNED", "Critter is not owned by this player", "critterId")
	end
	if type(critter.acquisition) ~= "table" or critter.acquisition.source == "STARTER" then
		return failure("STARTER_NOT_TRADABLE", "Starter Critters cannot be traded", "critterId")
	end
	if critter.tradable ~= true then
		return failure("CRITTER_NOT_TRADABLE", "Critter is marked nontradable", "critterId")
	end
	if
		contains(profile.selectedTeam, critterId)
		or (type(critter.equipmentIds) == "table" and next(critter.equipmentIds) ~= nil)
	then
		return failure("CRITTER_EQUIPPED", "Equipped Critters cannot be traded", "critterId")
	end
	if lock ~= nil and lock.token ~= allowedLockToken then
		return failure(
			"CRITTER_LOCKED",
			`Critter is in an active {tostring(lock.operationType)} operation`,
			"critterId"
		)
	end
	return { ok = true, value = { critterId = critterId } }
end

TradeEligibilityValidator.validate = validate
TradeEligibilityValidator.Validate = validate
return table.freeze(TradeEligibilityValidator)
