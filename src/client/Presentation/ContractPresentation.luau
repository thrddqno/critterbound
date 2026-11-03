--!strict

local function requireSibling(name: string)
	if script ~= nil then
		return require(script.Parent[name])
	end
	return require(`./{name}`)
end

local CollectionPresentation = requireSibling("CollectionPresentation")

local ContractPresentation = {}

local function statusLabel(status: string): string
	if status == "COMPLETED" then
		return "Completed - reward ready"
	elseif status == "CLAIMED" then
		return "Reward claimed"
	end
	return "Active"
end

local function rewardText(contract): string
	local pool = contract.rewardPoolId or "Unknown reward pool"
	return `Reward: 1 Critter ({pool})`
end

local function mapContract(contract)
	local current = contract.progressCurrent or 0
	local required = contract.progressRequired or 1
	local status = contract.status or "ACTIVE"
	return {
		id = contract.id,
		definitionId = contract.definitionId,
		definitionVersion = contract.definitionVersion,
		displayName = contract.displayName or contract.definitionId or "Unknown Contract",
		description = contract.description or "",
		status = status,
		statusText = statusLabel(status),
		progressCurrent = current,
		progressRequired = required,
		progressText = `Progress: {current}/{required}`,
		rewardText = rewardText(contract),
		acceptedAt = contract.acceptedAt,
		completedAt = contract.completedAt,
		claimedAt = contract.claimedAt,
		canClaim = contract.canClaim == true and status == "COMPLETED",
		canAccept = false,
	}
end

local function mapAvailable(definition)
	local required = definition.requirementCount or 1
	return {
		id = definition.id,
		version = definition.version,
		definitionId = definition.id,
		definitionVersion = definition.version,
		displayName = definition.displayName or definition.id or "Unknown Contract",
		description = definition.description or "",
		status = "AVAILABLE",
		statusText = "Available",
		progressCurrent = 0,
		progressRequired = required,
		progressText = `Progress: 0/{required}`,
		rewardText = `Reward: {definition.rewardCount or 1} Critter ({definition.rewardPoolId or "Unknown"})`,
		canClaim = false,
		canAccept = true,
	}
end

function ContractPresentation.map(response)
	local contracts = {}
	for _, contract in response.contracts or {} do
		table.insert(contracts, mapContract(contract))
	end
	local available = {}
	for _, definition in response.availableDefinitions or {} do
		table.insert(available, mapAvailable(definition))
	end
	return {
		revision = response.revision,
		contracts = contracts,
		availableDefinitions = available,
		capacityAvailable = response.capacityAvailable ~= false,
		maxRedemptions = response.maxRedemptions,
	}
end

function ContractPresentation.mapReward(response)
	if type(response) ~= "table" or type(response.critter) ~= "table" then
		return nil
	end
	return {
		critter = CollectionPresentation.mapCritter(response.critter),
		redemption = response.redemption,
		duplicate = response.duplicate == true,
	}
end

ContractPresentation.mapContract = mapContract
ContractPresentation.mapAvailable = mapAvailable
ContractPresentation.statusLabel = statusLabel
return table.freeze(ContractPresentation)
