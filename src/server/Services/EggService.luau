--!strict

local EggService = {}

local MAX_OWNED_CRITTERS = 500

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

local function failure(code: string, message: string)
	return { ok = false, errors = { { code = code, message = message } } }
end

local function success(value)
	return { ok = true, value = value }
end

local function isIdentifier(value: any): boolean
	return type(value) == "string"
		and #value >= 1
		and #value <= 96
		and string.match(value, "^[%w][%w_.:%-]*$") ~= nil
end

local function integer(value: any): boolean
	return type(value) == "number"
		and value == value
		and value >= 0
		and value < math.huge
		and value % 1 == 0
end

local function mapCount(value): number
	local count = 0
	for _ in value do
		count += 1
	end
	return count
end

local function derivedStatus(egg: any, now: number): string
	if egg.status == "HATCHED" then
		return "HATCHED"
	end
	if now >= egg.hatchAt then
		return "READY"
	end
	return "INCUBATING"
end

local function parentSummary(profile: any, parentId: string, catalog: any)
	local parent = if type(profile.ownedCritters) == "table"
		then profile.ownedCritters[parentId]
		else nil
	local definition = if parent == nil then nil else catalog.getById(parent.definitionId)
	return {
		id = parentId,
		displayName = if definition == nil then "Unknown Critter" else definition.displayName,
		class = if definition == nil then "Unknown" else definition.class,
	}
end

local function projectOffspring(offspring: any, catalog: any, projector: any)
	if offspring == nil then
		return nil
	end
	local projected = if projector == nil
		then clone(offspring)
		else projector.projectCritter(offspring, catalog)
	projected.ownerUserId = nil
	projected.equipmentIds = nil
	return projected
end

local function sanitizeEgg(egg: any, now: number, profile: any, catalog: any, projector: any)
	local status = derivedStatus(egg, now)
	local offspring = if status == "HATCHED" and type(profile.ownedCritters) == "table"
		then profile.ownedCritters[egg.offspringId]
		else nil
	return {
		eggId = egg.eggId,
		status = status,
		createdAt = egg.createdAt,
		hatchAt = egg.hatchAt,
		hatchedAt = if status == "HATCHED" then egg.hatchedAt else nil,
		generation = egg.generation,
		parentA = parentSummary(profile, egg.parentAId, catalog),
		parentB = parentSummary(profile, egg.parentBId, catalog),
		offspringClass = egg.offspringClass,
		possibleOffspringClasses = { egg.offspringClass },
		offspringId = if status == "HATCHED" then egg.offspringId else nil,
		offspring = projectOffspring(offspring, catalog, projector),
	}
end

local function new(dependencies)
	local deps = dependencies
	local activeMutation = {}
	local service = {}

	local function readProfile(userId: number)
		return deps.profileService.ReadProfile(userId)
	end

	local function findEgg(profile: any, eggId: string)
		if type(profile) ~= "table" or type(profile.eggs) ~= "table" then
			return nil
		end
		return profile.eggs[eggId]
	end

	local function findHatchedByCommand(profile: any, commandId: string)
		if type(profile) ~= "table" or type(profile.eggs) ~= "table" then
			return nil
		end
		for _, egg in profile.eggs do
			if egg.hatchedCommandId == commandId then
				return egg
			end
		end
		return nil
	end

	local function buildOffspring(userId: number, egg: any, now: number)
		local definition = deps.catalog.getByClass(egg.offspringClass)
		if definition == nil then
			return nil, failure("UNKNOWN_CRITTER_DEFINITION", "Offspring definition is unknown")
		end
		local geneContentVersion = if egg.schemaVersion == 2 then egg.geneContentVersion else nil
		if egg.schemaVersion == 2 then
			if
				egg.geneticsMode ~= "CLASSIC_INHERITANCE_V1"
				or egg.classInheritancePolicyVersion ~= 1
				or egg.inheritancePolicyVersion ~= 1
				or egg.mutationPolicyVersion ~= 1
				or egg.geneContentVersion ~= 1
				or egg.expressionVersion ~= deps.genotypeExpressor.Version
				or not deps.conceptionRng.validSeed(egg.conceptionSeed)
			then
				return nil,
					failure(
						"UNSUPPORTED_EGG_GENETICS_VERSION",
						"Egg genetics metadata is unsupported"
					)
			end
			local expectedDigest = deps.conceptionRng.outcomeDigest(
				egg.offspringClass,
				egg.offspringAppearanceGenome,
				egg.offspringAbilityGenome,
				egg
			)
			if egg.outcomeDigest ~= expectedDigest then
				return nil, failure("GENETICS_DIGEST_MISMATCH", "Egg genetics digest is invalid")
			end
		end
		local genomeValidation = deps.genomeValidator.validate(
			egg.offspringAppearanceGenome,
			egg.offspringAbilityGenome,
			egg.offspringClass,
			geneContentVersion
		)
		if not genomeValidation.ok then
			local genomeError = genomeValidation.errors[1]
			return nil, failure(genomeError.code, genomeError.message)
		end
		if egg.schemaVersion == 2 then
			local expression = deps.genotypeExpressor.express(
				egg.offspringAppearanceGenome,
				egg.offspringAbilityGenome,
				egg.offspringClass,
				egg.geneContentVersion
			)
			if not expression.ok then
				return nil, expression
			end
		end

		local offspringId = `critter:{deps.generateId()}`
		local parentIds = { egg.parentAId, egg.parentBId }
		local offspring = {
			schemaVersion = 3,
			id = offspringId,
			definitionId = definition.id,
			ownerUserId = userId,
			appearanceGenome = clone(egg.offspringAppearanceGenome),
			abilityGenome = clone(egg.offspringAbilityGenome),
			baseStats = clone(definition.baseStats),
			acquisition = {
				source = "BREEDING",
				acquiredAt = now,
				sourceVersion = 1,
			},
			breeding = {
				breedable = true,
				generation = egg.generation,
				parentIds = parentIds,
				successfulBreedCount = 0,
			},
			tradable = false,
			equipmentIds = {},
		}
		if egg.schemaVersion == 2 then
			offspring.genetics = {
				schemaVersion = 1,
				geneticsMode = egg.geneticsMode,
				classInheritancePolicyVersion = egg.classInheritancePolicyVersion,
				inheritancePolicyVersion = egg.inheritancePolicyVersion,
				mutationPolicyVersion = egg.mutationPolicyVersion,
				mutationEnabled = egg.mutationEnabled,
				geneContentVersion = egg.geneContentVersion,
				expressionVersion = egg.expressionVersion,
				conceptionSeed = egg.conceptionSeed,
				outcomeDigest = egg.outcomeDigest,
				canonicalParentIds = clone(egg.canonicalParentIds),
				mutationTrace = clone(egg.mutationTrace),
			}
		end
		return offspring, nil
	end

	local function getEggs(userId: number)
		local profileResult = readProfile(userId)
		if not profileResult.ok then
			return profileResult
		end
		local profile = profileResult.value
		local now = deps.now()
		local eggs = {}
		if type(profile.eggs) == "table" then
			for _, egg in profile.eggs do
				table.insert(eggs, sanitizeEgg(egg, now, profile, deps.catalog, deps.projector))
			end
		end
		table.sort(eggs, function(a, b)
			return a.eggId < b.eggId
		end)
		return success({
			revision = profile.revision,
			eggs = eggs,
		})
	end

	local function getEggStatus(userId: number, eggId: string)
		if not isIdentifier(eggId) then
			return failure("INVALID_EGG_ID", "Egg ID is malformed")
		end
		local profileResult = readProfile(userId)
		if not profileResult.ok then
			return profileResult
		end
		local egg = findEgg(profileResult.value, eggId)
		if egg == nil then
			return failure("EGG_NOT_FOUND", "Egg does not exist")
		end
		return success(
			sanitizeEgg(egg, deps.now(), profileResult.value, deps.catalog, deps.projector)
		)
	end

	local function hatchEgg(
		userId: number,
		eggId: string,
		commandId: string,
		expectedRevision: number
	)
		if not isIdentifier(eggId) then
			return failure("INVALID_EGG_ID", "Egg ID is malformed")
		end
		if not isIdentifier(commandId) then
			return failure("INVALID_COMMAND", "Command ID is required")
		end
		if not integer(expectedRevision) then
			return failure("INVALID_COMMAND", "Expected revision is required")
		end

		local profileResult = readProfile(userId)
		if not profileResult.ok then
			return profileResult
		end
		local profile = profileResult.value
		local egg = findEgg(profile, eggId)
		if egg == nil then
			return failure("EGG_NOT_FOUND", "Egg does not exist")
		end

		local hatchedBySameCommand = egg.hatchedCommandId == commandId
		local hatchedByOtherCommand = egg.status == "HATCHED" and not hatchedBySameCommand

		local operationEgg = findHatchedByCommand(profile, commandId)
		if operationEgg ~= nil and operationEgg.eggId ~= eggId then
			return failure("COMMAND_ID_CONFLICT", "Command ID was used for another hatch operation")
		end

		if hatchedByOtherCommand then
			return failure("ALREADY_HATCHED", "Egg has already hatched")
		end

		if egg.status == "HATCHED" and hatchedBySameCommand then
			local offspring = profile.ownedCritters[egg.offspringId]
			if offspring == nil then
				return failure("HATCH_OPERATION_CORRUPT", "Recorded hatch result is missing")
			end
			return success({
				revision = profile.revision,
				egg = sanitizeEgg(egg, deps.now(), profile, deps.catalog, deps.projector),
				offspring = projectOffspring(offspring, deps.catalog, deps.projector),
				critter = projectOffspring(offspring, deps.catalog, deps.projector),
				offspringId = egg.offspringId,
				duplicate = true,
			})
		end

		local now = deps.now()
		if now < egg.hatchAt then
			return failure("EGG_NOT_READY", "Egg incubation is not complete")
		end

		if activeMutation[userId] then
			return failure("COMMAND_IN_PROGRESS", "Another hatch command is running")
		end
		activeMutation[userId] = true

		local ok, result = pcall(function()
			local mutationResult = deps.profileService.UpdateProfile(userId, function(candidate)
				if candidate.revision ~= expectedRevision then
					return failure("STALE_REVISION", "Profile revision is stale")
				end

				local candidateEgg = findEgg(candidate, eggId)
				if candidateEgg == nil then
					return failure("EGG_NOT_FOUND", "Egg does not exist")
				end
				if candidateEgg.ownerUserId ~= userId then
					return failure("EGG_NOT_OWNED", "Egg is not owned by this player")
				end
				if candidateEgg.status == "HATCHED" then
					if candidateEgg.hatchedCommandId == commandId then
						return success({ duplicate = true, egg = clone(candidateEgg) })
					end
					return failure("ALREADY_HATCHED", "Egg has already hatched")
				end
				if deps.now() < candidateEgg.hatchAt then
					return failure("EGG_NOT_READY", "Egg incubation is not complete")
				end

				local offspring, buildFailure = buildOffspring(userId, candidateEgg, deps.now())
				if offspring == nil then
					return buildFailure
				end
				if candidate.ownedCritters[offspring.id] ~= nil then
					return failure("DUPLICATE_CRITTER_ID", "Generated Critter ID already exists")
				end
				if mapCount(candidate.ownedCritters) >= MAX_OWNED_CRITTERS then
					return failure("CRITTER_LIMIT_EXCEEDED", "Owned Critter limit exceeded")
				end

				candidate.ownedCritters[offspring.id] = offspring
				candidateEgg.status = "HATCHED"
				candidateEgg.hatchedAt = deps.now()
				candidateEgg.hatchOperationId = commandId
				candidateEgg.hatchedCommandId = commandId
				candidateEgg.offspringId = offspring.id

				return success({
					duplicate = false,
					egg = clone(candidateEgg),
					offspring = clone(offspring),
				})
			end)

			if not mutationResult.ok then
				return mutationResult
			end

			if mutationResult.value.duplicate == true then
				local refreshed = readProfile(userId)
				if not refreshed.ok then
					return refreshed
				end
				local refreshedEgg = findEgg(refreshed.value, eggId)
				local offspring = refreshed.value.ownedCritters[refreshedEgg.offspringId]
				if offspring == nil then
					return failure("HATCH_OPERATION_CORRUPT", "Recorded hatch result is missing")
				end
				return success({
					revision = refreshed.value.revision,
					egg = sanitizeEgg(
						refreshedEgg,
						deps.now(),
						refreshed.value,
						deps.catalog,
						deps.projector
					),
					offspring = projectOffspring(offspring, deps.catalog, deps.projector),
					critter = projectOffspring(offspring, deps.catalog, deps.projector),
					offspringId = refreshedEgg.offspringId,
					duplicate = true,
				})
			end

			local updatedProfile = readProfile(userId)
			if not updatedProfile.ok then
				return updatedProfile
			end
			return success({
				revision = updatedProfile.value.revision,
				egg = sanitizeEgg(
					mutationResult.value.egg,
					deps.now(),
					updatedProfile.value,
					deps.catalog,
					deps.projector
				),
				offspring = projectOffspring(
					mutationResult.value.offspring,
					deps.catalog,
					deps.projector
				),
				critter = projectOffspring(
					mutationResult.value.offspring,
					deps.catalog,
					deps.projector
				),
				offspringId = mutationResult.value.offspring.id,
				duplicate = false,
			})
		end)

		activeMutation[userId] = nil
		if not ok then
			return failure("INTERNAL_ERROR", "Hatch mutation failed")
		end
		return result
	end

	local function handleRequest(userId: number, request: any)
		if type(request) ~= "table" or request.protocolVersion ~= deps.protocolVersion then
			return failure("INVALID_REQUEST", "Egg request is malformed")
		end
		if request.kind == "GET_EGGS" then
			return getEggs(userId)
		elseif request.kind == "GET_EGG_STATUS" then
			return getEggStatus(userId, request.payload and request.payload.eggId)
		elseif request.kind == "HATCH_EGG" then
			local payload = request.payload or {}
			return hatchEgg(
				userId,
				payload.eggId,
				request.commandId or payload.commandId,
				request.expectedRevision or payload.expectedRevision
			)
		end
		return failure("INVALID_REQUEST_KIND", "Unknown egg request")
	end

	function service.removePlayer(userId: number)
		activeMutation[userId] = nil
	end

	service.handleRequest = handleRequest
	service.getEggs = getEggs
	service.getEggStatus = getEggStatus
	service.hatchEgg = hatchEgg
	service.GetEggs = getEggs
	service.GetEggStatus = getEggStatus
	service.HatchEgg = hatchEgg
	return table.freeze(service)
end

EggService.new = new
return table.freeze(EggService)
