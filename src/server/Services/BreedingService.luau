--!strict

local BreedingService = {}

local MAX_OPERATION_RECORDS = 64

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

local function failure(code, message)
	return { ok = false, errors = { { code = code, message = message } } }
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

local function integer(value)
	return type(value) == "number"
		and value == value
		and value >= 0
		and value < math.huge
		and value % 1 == 0
end

local function new(dependencies)
	local deps = dependencies
	local activeMutation = {}
	local service = {}

	local function readProfile(userId)
		return deps.profileService.ReadProfile(userId)
	end

	local function findEggByCommand(profile, commandId)
		for _, egg in profile.eggs or {} do
			if egg.breedingCommandId == commandId then
				return egg
			end
		end
		return nil
	end

	local function eligibleResult(profile, parentAId, parentBId)
		local validation = deps.validator.validate(
			profile,
			parentAId,
			parentBId,
			deps.catalog,
			deps.genomeValidator
		)
		return validation
	end

	local function checkEligibility(userId, parentAId, parentBId)
		if not isIdentifier(parentAId) or not isIdentifier(parentBId) then
			return failure("INVALID_PARENT_ID", "Parent ID is malformed")
		end
		local profileResult = readProfile(userId)
		if not profileResult.ok then
			return profileResult
		end
		local validation = eligibleResult(profileResult.value, parentAId, parentBId)
		print(`[Critterbound] Breeding check {parentAId} x {parentBId}: eligible={validation.ok}`)
		return success({
			eligible = validation.ok,
			errors = if validation.ok then {} else validation.errors,
		})
	end

	local function previewCompatibility(userId, parentAId, parentBId)
		if not isIdentifier(parentAId) or not isIdentifier(parentBId) then
			return failure("INVALID_PARENT_ID", "Parent ID is malformed")
		end
		local profileResult = readProfile(userId)
		if not profileResult.ok then
			return profileResult
		end
		local validation = eligibleResult(profileResult.value, parentAId, parentBId)
		if not validation.ok then
			print(
				`[Critterbound] Breeding preview {parentAId} x {parentBId}: ineligible {validation.errors[1] and validation.errors[1].code}`
			)
			return success({
				eligible = false,
				errors = validation.errors,
				possibleOffspringClasses = {},
				mutationEnabled = false,
			})
		end
		local parentA = profileResult.value.ownedCritters[parentAId]
		local parentB = profileResult.value.ownedCritters[parentBId]
		local classA = deps.catalog.getById(parentA.definitionId).class
		local classB = deps.catalog.getById(parentB.definitionId).class
		local possible = if classA == classB then { classA } else { classA, classB }
		print(
			`[Critterbound] Breeding preview {parentAId} x {parentBId}: compatible {table.concat(
				possible,
				","
			)}`
		)
		return success({
			eligible = true,
			errors = {},
			possibleOffspringClasses = possible,
			mutationEnabled = false,
			inheritanceRules = "Each of 36 allele positions independently chooses parent A or B, then D/R1/R2 with 75/20/5 weights.",
		})
	end

	local function breed(userId, parentAId, parentBId, commandId, expectedRevision)
		if not isIdentifier(parentAId) or not isIdentifier(parentBId) then
			return failure("INVALID_PARENT_ID", "Parent ID is malformed")
		end
		if not isIdentifier(commandId) or not integer(expectedRevision) then
			return failure("INVALID_COMMAND", "Command ID and expected revision are required")
		end
		if parentAId == parentBId then
			return failure("SAME_PARENT", "Parents must be different Critters")
		end

		local profileResult = readProfile(userId)
		if not profileResult.ok then
			return profileResult
		end
		local profile = profileResult.value
		local existingOperation = profile.breedingOperationsById
			and profile.breedingOperationsById[commandId]
		if existingOperation ~= nil then
			if
				existingOperation.parentAId ~= parentAId
				or existingOperation.parentBId ~= parentBId
			then
				return failure(
					"COMMAND_ID_CONFLICT",
					"Command ID was used for another breeding operation"
				)
			end
			local egg = profile.eggs and profile.eggs[existingOperation.eggId]
			if egg == nil then
				return failure("BREEDING_OPERATION_CORRUPT", "Recorded breeding result is missing")
			end
			return success({
				revision = profile.revision,
				egg = clone(egg),
				duplicate = true,
			})
		end
		local durableEgg = findEggByCommand(profile, commandId)
		if durableEgg ~= nil then
			if durableEgg.parentAId ~= parentAId or durableEgg.parentBId ~= parentBId then
				return failure(
					"COMMAND_ID_CONFLICT",
					"Command ID was used for another breeding operation"
				)
			end
			return success({
				revision = profile.revision,
				egg = clone(durableEgg),
				duplicate = true,
			})
		end

		if activeMutation[userId] then
			return failure("COMMAND_IN_PROGRESS", "Another breeding command is running")
		end
		local lockResult =
			deps.profileService.AcquireOwnershipLocks(userId, { parentAId, parentBId }, "BREEDING")
		if not lockResult.ok then
			return lockResult
		end
		local lockToken = lockResult.value.token
		activeMutation[userId] = lockToken
		local ok, result = pcall(function()
			local rngResult = deps.rng.new(deps.rngSeed())
			if not rngResult.ok then
				return rngResult
			end
			local rngState = rngResult.value
			local mutationResult = deps.profileService.UpdateProfile(userId, function(candidate)
				if candidate.revision ~= expectedRevision then
					return failure("STALE_REVISION", "Profile revision is stale")
				end
				local validation = deps.validator.validate(
					candidate,
					parentAId,
					parentBId,
					deps.catalog,
					deps.genomeValidator
				)
				if not validation.ok then
					return validation
				end
				local parentA = candidate.ownedCritters[parentAId]
				local parentB = candidate.ownedCritters[parentBId]
				local classA = deps.catalog.getById(parentA.definitionId).class
				local classB = deps.catalog.getById(parentB.definitionId).class
				local offspringClass
				if classA == classB then
					offspringClass = classA
				else
					local roll
					rngState, roll = deps.rng.nextInteger(rngState, 1, 2)
					offspringClass = if roll == 1 then classA else classB
				end

				local parentAData = {
					class = classA,
					appearanceGenome = clone(parentA.appearanceGenome),
					abilityGenome = clone(parentA.abilityGenome),
				}
				local parentBData = {
					class = classB,
					appearanceGenome = clone(parentB.appearanceGenome),
					abilityGenome = clone(parentB.abilityGenome),
				}
				local inherited = deps.inheritanceEngine.inherit(
					parentAData,
					parentBData,
					offspringClass,
					rngState
				)
				if not inherited.ok then
					return inherited
				end
				rngState = inherited.value.rng

				local generation = math.max(
					parentA.breeding.generation,
					parentB.breeding.generation
				) + 1
				local eggId = `egg:{deps.generateId()}`
				local now = deps.now()
				local egg = {
					schemaVersion = 1,
					eggId = eggId,
					ownerUserId = userId,
					parentAId = parentAId,
					parentBId = parentBId,
					offspringClass = offspringClass,
					offspringAppearanceGenome = clone(inherited.value.appearanceGenome),
					offspringAbilityGenome = clone(inherited.value.abilityGenome),
					generation = generation,
					createdAt = now,
					hatchAt = now + deps.incubationSeconds,
					status = "INCUBATING",
					breedingCommandId = commandId,
				}

				if candidate.eggs[eggId] ~= nil then
					return failure("DUPLICATE_EGG_ID", "Generated egg ID already exists")
				end
				candidate.eggs[eggId] = egg
				candidate.ownedCritters[parentAId].breeding.successfulBreedCount += 1
				candidate.ownedCritters[parentBId].breeding.successfulBreedCount += 1

				local operation = {
					schemaVersion = 1,
					commandId = commandId,
					parentAId = parentAId,
					parentBId = parentBId,
					eggId = eggId,
					createdAt = now,
				}
				candidate.breedingOperationsById[commandId] = operation
				table.insert(candidate.breedingOperationOrder, commandId)
				while #candidate.breedingOperationOrder > MAX_OPERATION_RECORDS do
					local oldCommandId = table.remove(candidate.breedingOperationOrder, 1)
					candidate.breedingOperationsById[oldCommandId] = nil
				end

				return success({ egg = clone(egg) })
			end)

			if not mutationResult.ok then
				return mutationResult
			end
			local updatedProfile = deps.profileService.ReadProfile(userId)
			if not updatedProfile.ok then
				return updatedProfile
			end
			return success({
				revision = updatedProfile.value.revision,
				egg = clone(mutationResult.value.egg),
				duplicate = false,
			})
		end)
		activeMutation[userId] = nil
		deps.profileService.ReleaseOwnershipLocks(userId, lockToken)
		if not ok then
			return failure("INTERNAL_ERROR", "Breeding mutation failed")
		end
		return result
	end

	local function handleRequest(userId, request)
		if type(request) ~= "table" or request.protocolVersion ~= deps.protocolVersion then
			return failure("INVALID_REQUEST", "Breeding request is malformed")
		end
		if request.kind == "CHECK_BREEDING" then
			return checkEligibility(
				userId,
				request.payload and request.payload.parentAId,
				request.payload and request.payload.parentBId
			)
		elseif request.kind == "PREVIEW_BREEDING" then
			return previewCompatibility(
				userId,
				request.payload and request.payload.parentAId,
				request.payload and request.payload.parentBId
			)
		elseif request.kind == "BREED_CRITTERS" then
			local payload = request.payload or {}
			return breed(
				userId,
				payload.parentAId,
				payload.parentBId,
				request.commandId,
				request.expectedRevision
			)
		end
		return failure("INVALID_REQUEST_KIND", "Unknown breeding request")
	end

	function service.removePlayer(userId)
		local lockToken = activeMutation[userId]
		activeMutation[userId] = nil
		if lockToken ~= nil then
			deps.profileService.ReleaseOwnershipLocks(userId, lockToken)
		end
	end

	service.handleRequest = handleRequest
	service.checkEligibility = checkEligibility
	service.previewCompatibility = previewCompatibility
	service.breed = breed
	service.CheckEligibility = checkEligibility
	service.PreviewCompatibility = previewCompatibility
	service.Breed = breed
	return table.freeze(service)
end

BreedingService.new = new
return table.freeze(BreedingService)
