--!strict

local BreedingValidator = {}

local function clone(value)
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, child in value do
		result[clone(key)] = clone(child)
	end
	return result
end

local function failure(code, message, path)
	return { ok = false, errors = { { code = code, message = message, path = path } } }
end

local function success(value)
	return { ok = true, value = value }
end

local function isIdentifier(value)
	return type(value) == "string"
		and #value >= 1
		and #value <= 96
		and string.match(value, "^[%w][%w_.:%-]*$") ~= nil
end

local function arrayLength(value)
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

local function validate(profile, parentAId, parentBId, catalog, genomeValidator)
	if type(profile) ~= "table" or type(profile.ownedCritters) ~= "table" then
		return failure("PROFILE_INVALID", "Profile is invalid", nil)
	end
	if not isIdentifier(parentAId) or not isIdentifier(parentBId) then
		return failure("INVALID_PARENT_ID", "Parent ID is malformed", nil)
	end
	if parentAId == parentBId then
		return failure("SAME_PARENT", "Parents must be different Critters", nil)
	end

	local parentA = profile.ownedCritters[parentAId]
	local parentB = profile.ownedCritters[parentBId]
	if parentA == nil or parentB == nil then
		return failure("PARENT_NOT_FOUND", "Parent Critter does not exist", nil)
	end
	if parentA.ownerUserId ~= profile.userId or parentB.ownerUserId ~= profile.userId then
		return failure("PARENT_NOT_OWNED", "Parent Critter is not owned by this player", nil)
	end

	for _, parent in { parentA, parentB } do
		if type(parent.breeding) ~= "table" or parent.breeding.breedable ~= true then
			return failure("PARENT_NOT_BREEDABLE", "Parent Critter cannot breed", nil)
		end
		if
			type(parent.breeding.successfulBreedCount) ~= "number"
			or parent.breeding.successfulBreedCount >= 5
		then
			return failure("BREED_LIMIT_REACHED", "Parent has reached its breed limit", nil)
		end
		local parentCount = arrayLength(parent.breeding.parentIds)
		if parentCount == nil or (parentCount ~= 0 and parentCount ~= 2) then
			return failure("INVALID_ANCESTRY", "Parent ancestry is invalid", nil)
		end
		local definition = catalog.getById(parent.definitionId)
		if definition == nil then
			return failure("UNKNOWN_CRITTER_DEFINITION", "Parent definition is unknown", nil)
		end
		local genomeResult = genomeValidator.validate(
			parent.appearanceGenome,
			parent.abilityGenome,
			definition.class
		)
		if not genomeResult.ok then
			return { ok = false, errors = genomeResult.errors }
		end
	end

	local parentsAIds = parentA.breeding.parentIds or {}
	local parentsBIds = parentB.breeding.parentIds or {}

	-- Parent-child restriction.
	for _, parentId in parentsAIds do
		if parentId == parentBId then
			return failure("PARENT_CHILD", "Parent-child breeding is not allowed", nil)
		end
	end
	for _, parentId in parentsBIds do
		if parentId == parentAId then
			return failure("PARENT_CHILD", "Parent-child breeding is not allowed", nil)
		end
	end

	-- Full/half sibling restriction.
	for _, idA in parentsAIds do
		for _, idB in parentsBIds do
			if idA == idB then
				return failure("SIBLINGS", "Sibling breeding is not allowed", nil)
			end
		end
	end

	return success({ parentA = parentA, parentB = parentB })
end

BreedingValidator.validate = validate
BreedingValidator.Validate = validate
return table.freeze(BreedingValidator)
