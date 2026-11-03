--!strict

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Protocol = require(ReplicatedStorage.Shared.Network.Protocol)
local PlayerDataProtocol = require(ReplicatedStorage.Shared.Network.PlayerDataProtocol)
local BreedingProtocol = require(ReplicatedStorage.Shared.Network.BreedingProtocol)
local EggProtocol = require(ReplicatedStorage.Shared.Network.EggProtocol)
local ContractProtocol = require(ReplicatedStorage.Shared.Network.ContractProtocol)
local CollectionPresentation = require(script.Parent.Parent.Presentation.CollectionPresentation)
local ContractPresentation = require(script.Parent.Parent.Presentation.ContractPresentation)
local NavigationController = require(script.Parent.NavigationController)
local ProfileStateCoordinator = require(script.Parent.ProfileStateCoordinator)
local BattleScreenController = require(script.Parent.BattleScreenController)
local ProfileStatus = require(script.Parent.Parent.UI.Components.ProfileStatus)
local MainMenuScreen = require(script.Parent.Parent.UI.Components.MainMenuScreen)
local CollectionScreen = require(script.Parent.Parent.UI.Components.CollectionScreen)
local TeamBuilderScreen = require(script.Parent.Parent.UI.Components.TeamBuilderScreen)
local InventoryScreen = require(script.Parent.Parent.UI.Components.InventoryScreen)
local BreedingScreen = require(script.Parent.Parent.UI.Components.BreedingScreen)
local EggCollectionScreen = require(script.Parent.Parent.UI.Components.EggCollectionScreen)
local EggOffspringScreen = require(script.Parent.Parent.UI.Components.EggOffspringScreen)
local ContractsScreen = require(script.Parent.Parent.UI.Components.ContractsScreen)
local SpritePreviewScreen = require(script.Parent.Parent.UI.Components.SpritePreviewScreen)

local AppController = {}
local activeHandle: any = nil
local REQUEST_TIMEOUT_SECONDS = 15
local REQUEST_POLL_SECONDS = 0.1

local function errorCode(response): string?
	if type(response) == "table" and type(response.errors) == "table" and response.errors[1] then
		return response.errors[1].code
	end
	return nil
end

local function errorMessage(response): string
	if type(response) == "table" and type(response.errors) == "table" and response.errors[1] then
		return `{response.errors[1].code}: {response.errors[1].message}`
	end
	return "NETWORK_ERROR: Server request failed. Check connection and retry."
end

local function mutationFingerprint(kind: string, payload): string
	if kind == PlayerDataProtocol.RequestKinds.SET_TEAM then
		return `{kind}|{table.concat(payload.critterIds, "|")}`
	elseif kind == PlayerDataProtocol.RequestKinds.EQUIP_ITEM then
		return `{kind}|{payload.critterId}|{payload.instanceId}`
	end
	return `{kind}|{payload.critterId}`
end

function AppController.start(
	playerGui: PlayerGui,
	playerDataRequest: RemoteFunction,
	battleRequest: RemoteFunction,
	breedingRequest: RemoteFunction?,
	eggRequest: RemoteFunction?,
	contractRequest: RemoteFunction?
)
	if activeHandle ~= nil then
		activeHandle.destroy()
	end
	local destroyed = false
	local profileState = ProfileStateCoordinator.new()
	local requestSequence = 0
	local traceSequence = 0
	local activeScreen: any = nil
	local navigation: any = nil
	local collection: any = nil
	local selectedCollectionCritterId: string? = nil
	local inventory: any = nil
	local pending = false
	local message: string? = nil
	local breedingPending = false
	local breedingRemote = breedingRequest
	if breedingRemote == nil then
		local remotes = ReplicatedStorage:FindFirstChild(Protocol.RemoteFolderName)
		if remotes ~= nil then
			breedingRemote = remotes:FindFirstChild(BreedingProtocol.RemoteName) :: RemoteFunction?
		end
	end
	local breedingMessage: string? = nil
	local eggRemote = eggRequest
	if eggRemote == nil then
		local remotes = ReplicatedStorage:FindFirstChild(Protocol.RemoteFolderName)
		if remotes ~= nil then
			eggRemote = remotes:FindFirstChild(EggProtocol.RemoteName) :: RemoteFunction?
		end
	end
	local eggs: any = nil
	local eggsMessage: string? = nil
	local selectedEggTab = "ACTIVE"
	local selectedEggIds: { [string]: string? } = {}
	local hatchPending = false
	local hatchMessage: string? = nil
	local hatchResult: any = nil
	local contractRemote = contractRequest
	if contractRemote == nil then
		local remotes = ReplicatedStorage:FindFirstChild(Protocol.RemoteFolderName)
		if remotes ~= nil then
			contractRemote = remotes:FindFirstChild(ContractProtocol.RemoteName) :: RemoteFunction?
		end
	end
	local contracts: any = nil
	local contractsMessage: string? = nil
	local contractsLoadError: string? = nil
	local contractPending = false
	local contractReward: any = nil
	local mountRoute: () -> ()
	local navigate: (string) -> ()

	local function nextRequestId(prefix: string): string
		requestSequence += 1
		return `{prefix}:{requestSequence}`
	end

	local function trace(
		requestId: string,
		operation: string,
		clientRevision: number?,
		responseRevision: number?,
		result: string,
		reason: string?
	)
		if not RunService:IsStudio() then
			return
		end
		traceSequence += 1
		print(
			`[Critterbound] UI order={traceSequence} request={requestId} operation={operation} clientRevision={tostring(
				clientRevision
			)} serverRevision={tostring(responseRevision)} responseRevision={tostring(
				responseRevision
			)} result={result} reason={reason or "NONE"}`
		)
	end

	local function currentRevision(): number?
		return profileState.revision()
	end

	local function destroyScreen()
		if activeScreen ~= nil then
			activeScreen.destroy()
			activeScreen = nil
		end
	end

	local function invokeRemote(remote: RemoteFunction?, request, unavailableMessage: string)
		if remote == nil then
			return {
				ok = false,
				errors = { { code = "NETWORK_ERROR", message = unavailableMessage } },
			}
		end
		local completed = false
		local response: any = nil
		task.spawn(function()
			local ok, result = pcall(function()
				return remote:InvokeServer(request)
			end)
			response = if ok
				then result
				else {
					ok = false,
					errors = { { code = "NETWORK_ERROR", message = "Request failed" } },
				}
			completed = true
		end)
		local waited = 0
		while not completed and not destroyed and waited < REQUEST_TIMEOUT_SECONDS do
			waited += task.wait(REQUEST_POLL_SECONDS)
		end
		if completed then
			return response
		end
		return {
			ok = false,
			errors = {
				{
					code = "NETWORK_ERROR",
					message = if destroyed then "Request cancelled" else "Request timed out",
				},
			},
		}
	end

	local function invoke(request)
		return invokeRemote(playerDataRequest, request, "Player data remote unavailable")
	end

	local function invokeBreeding(request)
		return invokeRemote(breedingRemote, request, "Breeding remote unavailable")
	end

	local function invokeEgg(request)
		return invokeRemote(eggRemote, request, "Egg remote unavailable")
	end

	local function invokeContract(request)
		return invokeRemote(contractRemote, request, "Contract remote unavailable")
	end

	local function getCollection()
		return invoke({
			protocolVersion = PlayerDataProtocol.Version,
			kind = PlayerDataProtocol.RequestKinds.GET_COLLECTION,
		})
	end
	local function getInventory()
		return invoke({
			protocolVersion = PlayerDataProtocol.Version,
			kind = PlayerDataProtocol.RequestKinds.GET_INVENTORY,
		})
	end

	local function refresh(includeInventory: boolean): boolean
		local requestId = nextRequestId("collection.read")
		local token = profileState.beginRead("collection", requestId)
		local startedRevision = currentRevision()
		local collectionResult = getCollection()
		if not collectionResult.ok then
			trace(
				requestId,
				"GET_COLLECTION",
				startedRevision,
				nil,
				"FAILED",
				errorCode(collectionResult)
			)
			message = errorMessage(collectionResult)
			return false
		end
		local mappedCollection = CollectionPresentation.map(collectionResult.value)
		local applied =
			profileState.applyRead(token, collectionResult.value.revision, mappedCollection)
		trace(
			requestId,
			"GET_COLLECTION",
			startedRevision,
			collectionResult.value.revision,
			if applied.applied then "APPLIED" else "IGNORED",
			applied.reason
		)
		collection = profileState.get("collection")
		local collectionReady = applied.applied or profileState.isFresh("collection")
		if not collectionReady then
			message = "STALE_RESPONSE: Collection refresh was superseded. Retry refresh."
			return false
		end
		if includeInventory then
			local inventoryRequestId = nextRequestId("inventory.read")
			local inventoryToken = profileState.beginRead("inventory", inventoryRequestId)
			local inventoryStartedRevision = currentRevision()
			local inventoryResult = getInventory()
			if not inventoryResult.ok then
				trace(
					inventoryRequestId,
					"GET_INVENTORY",
					inventoryStartedRevision,
					nil,
					"FAILED",
					errorCode(inventoryResult)
				)
				message = errorMessage(inventoryResult)
				return false
			end
			local inventoryApplied = profileState.applyRead(
				inventoryToken,
				inventoryResult.value.revision,
				inventoryResult.value
			)
			trace(
				inventoryRequestId,
				"GET_INVENTORY",
				inventoryStartedRevision,
				inventoryResult.value.revision,
				if inventoryApplied.applied then "APPLIED" else "IGNORED",
				inventoryApplied.reason
			)
			inventory = profileState.get("inventory")
			if not inventoryApplied.applied and not profileState.isFresh("inventory") then
				message = "STALE_RESPONSE: Inventory refresh was superseded. Retry refresh."
				return false
			end
		end
		return true
	end

	local function mutate(kind: string, payload)
		if pending or collection == nil or currentRevision() == nil then
			return
		end
		local fingerprint = mutationFingerprint(kind, payload)
		local request = profileState.uncertainRequest(fingerprint)
			or {
				protocolVersion = PlayerDataProtocol.Version,
				kind = kind,
				commandId = `player:{HttpService:GenerateGUID(false)}`,
				expectedRevision = currentRevision(),
				payload = payload,
			}
		local mutationToken = profileState.beginMutation(kind, request)
		if mutationToken == nil then
			message = "COMMAND_IN_PROGRESS: Another profile change is saving."
			mountRoute()
			return
		end
		pending = true
		message = "Saving..."
		mountRoute()
		local requestId = request.commandId
		trace(requestId, kind, request.expectedRevision, nil, "STARTED", nil)
		local response = invoke(request)
		pending = false
		if destroyed then
			profileState.finishMutation(mutationToken)
			return
		end
		if not response.ok then
			local code = errorCode(response)
			if code == "NETWORK_ERROR" then
				profileState.rememberUncertain(fingerprint, request)
			else
				profileState.clearUncertain(fingerprint)
			end
			trace(requestId, kind, request.expectedRevision, nil, "FAILED", code)
			message = errorMessage(response)
			if code == "STALE_PROFILE" then
				profileState.invalidate("collection")
				profileState.invalidate("inventory")
				refresh(true)
				message = "STALE_PROFILE: Data refreshed. Review selection and retry."
			end
			profileState.finishMutation(mutationToken)
			mountRoute()
			return
		end
		profileState.clearUncertain(fingerprint)
		profileState.applyMutationRevision(response.value.revision, { "collection", "inventory" })
		profileState.applyMutationResource(
			"collection",
			response.value.revision,
			CollectionPresentation.map(response.value.collection)
		)
		profileState.applyMutationResource(
			"inventory",
			response.value.revision,
			response.value.inventory
		)
		collection = profileState.get("collection")
		inventory = profileState.get("inventory")
		trace(requestId, kind, request.expectedRevision, response.value.revision, "APPLIED", nil)
		message = if response.value.duplicate
			then "Command already accepted; current data restored."
			else "Saved successfully."
		profileState.finishMutation(mutationToken)
		mountRoute()
	end

	local function refreshEggs(): boolean
		local requestId = nextRequestId("eggs.read")
		local token = profileState.beginRead("eggs", requestId)
		local startedRevision = currentRevision()
		local response = invokeEgg({
			protocolVersion = EggProtocol.Version,
			kind = EggProtocol.RequestKinds.GET_EGGS,
		})
		if not response.ok then
			trace(requestId, "GET_EGGS", startedRevision, nil, "FAILED", errorCode(response))
			eggsMessage = errorMessage(response)
			return false
		end
		local applied = profileState.applyRead(token, response.value.revision, response.value.eggs)
		trace(
			requestId,
			"GET_EGGS",
			startedRevision,
			response.value.revision,
			if applied.applied then "APPLIED" else "IGNORED",
			applied.reason
		)
		eggs = profileState.get("eggs")
		if not applied.applied and not profileState.isFresh("eggs") then
			eggsMessage = "STALE_RESPONSE: Egg refresh was superseded. Retry refresh."
			return false
		end
		eggsMessage = nil
		return true
	end

	local function refreshContracts(): boolean
		local requestId = nextRequestId("contracts.read")
		local token = profileState.beginRead("contracts", requestId)
		local startedRevision = currentRevision()
		local response = invokeContract({
			protocolVersion = ContractProtocol.Version,
			kind = ContractProtocol.RequestKinds.GET_CONTRACTS,
		})
		if not response.ok then
			trace(requestId, "GET_CONTRACTS", startedRevision, nil, "FAILED", errorCode(response))
			contractsLoadError = errorMessage(response)
			return false
		end
		local mappedContracts = ContractPresentation.map(response.value)
		local applied = profileState.applyRead(token, response.value.revision, mappedContracts)
		trace(
			requestId,
			"GET_CONTRACTS",
			startedRevision,
			response.value.revision,
			if applied.applied then "APPLIED" else "IGNORED",
			applied.reason
		)
		contracts = profileState.get("contracts")
		if not applied.applied and not profileState.isFresh("contracts") then
			contractsLoadError = "STALE_RESPONSE: Contract refresh was superseded. Retry refresh."
			return false
		end
		contractsLoadError = nil
		return true
	end

	local function acceptContract(definitionId: string, definitionVersion: number)
		if contractPending or contracts == nil or currentRevision() == nil then
			return
		end
		local fingerprint = `ACCEPT_CONTRACT|{definitionId}|{definitionVersion}`
		local request = profileState.uncertainRequest(fingerprint)
			or {
				protocolVersion = ContractProtocol.Version,
				kind = ContractProtocol.RequestKinds.ACCEPT_CONTRACT,
				commandId = `contract:{HttpService:GenerateGUID(false)}`,
				expectedRevision = currentRevision(),
				definitionId = definitionId,
				definitionVersion = definitionVersion,
			}
		local mutationToken = profileState.beginMutation("ACCEPT_CONTRACT", request)
		if mutationToken == nil then
			contractsMessage = "COMMAND_IN_PROGRESS: Another profile change is saving."
			mountRoute()
			return
		end
		contractPending = true
		contractsMessage = "Accepting contract..."
		mountRoute()
		trace(request.commandId, "ACCEPT_CONTRACT", request.expectedRevision, nil, "STARTED", nil)
		local response = invokeContract(request)
		contractPending = false
		if destroyed then
			profileState.finishMutation(mutationToken)
			return response
		end
		if not response.ok then
			local code = errorCode(response)
			if code == "NETWORK_ERROR" then
				profileState.rememberUncertain(fingerprint, request)
			else
				profileState.clearUncertain(fingerprint)
			end
			trace(
				request.commandId,
				"ACCEPT_CONTRACT",
				request.expectedRevision,
				nil,
				"FAILED",
				code
			)
			contractsMessage = errorMessage(response)
			if code == "STALE_REVISION" then
				profileState.invalidate("collection")
				profileState.invalidate("contracts")
				refresh(false)
				refreshContracts()
				contractsMessage = "STALE_REVISION: Data refreshed. Review contracts and retry."
			end
			profileState.finishMutation(mutationToken)
			mountRoute()
			return response
		end
		profileState.clearUncertain(fingerprint)
		profileState.applyMutationRevision(response.value.revision, { "contracts" })
		local refreshed = refreshContracts()
		trace(
			request.commandId,
			"ACCEPT_CONTRACT",
			request.expectedRevision,
			response.value.revision,
			"APPLIED",
			nil
		)
		contractsMessage = if response.value.duplicate
			then "Contract already accepted; current contract restored."
			elseif
				not refreshed
			then "Contract accepted, but contract refresh failed. Retry refresh."
			else "Contract accepted. Win a Training Grounds battle to complete it."
		profileState.finishMutation(mutationToken)
		mountRoute()
		return response
	end

	local function claimContract(contractId: string)
		if contractPending or contracts == nil or currentRevision() == nil then
			return
		end
		local fingerprint = `CLAIM_CONTRACT_REWARD|{contractId}`
		local request = profileState.uncertainRequest(fingerprint)
			or {
				protocolVersion = ContractProtocol.Version,
				kind = ContractProtocol.RequestKinds.CLAIM_CONTRACT_REWARD,
				commandId = `claim:{HttpService:GenerateGUID(false)}`,
				expectedRevision = currentRevision(),
				contractId = contractId,
			}
		local mutationToken = profileState.beginMutation("CLAIM_CONTRACT_REWARD", request)
		if mutationToken == nil then
			contractsMessage = "COMMAND_IN_PROGRESS: Another profile change is saving."
			mountRoute()
			return
		end
		contractPending = true
		contractsMessage = "Claiming reward..."
		mountRoute()
		trace(
			request.commandId,
			"CLAIM_CONTRACT_REWARD",
			request.expectedRevision,
			nil,
			"STARTED",
			nil
		)
		local response = invokeContract(request)
		contractPending = false
		if destroyed then
			profileState.finishMutation(mutationToken)
			return response
		end
		if not response.ok then
			local code = errorCode(response)
			if code == "NETWORK_ERROR" then
				profileState.rememberUncertain(fingerprint, request)
			else
				profileState.clearUncertain(fingerprint)
			end
			trace(
				request.commandId,
				"CLAIM_CONTRACT_REWARD",
				request.expectedRevision,
				nil,
				"FAILED",
				code
			)
			contractsMessage = errorMessage(response)
			if code == "STALE_REVISION" then
				profileState.invalidate("collection")
				profileState.invalidate("contracts")
				refresh(false)
				refreshContracts()
				contractsMessage = "STALE_REVISION: Data refreshed. Review contract and retry."
			end
			profileState.finishMutation(mutationToken)
			mountRoute()
			return response
		end
		profileState.clearUncertain(fingerprint)
		profileState.applyMutationRevision(response.value.revision, { "contracts", "collection" })
		local collectionRefreshed = refresh(false)
		local contractsRefreshed = refreshContracts()
		contractReward = ContractPresentation.mapReward(response.value)
		trace(
			request.commandId,
			"CLAIM_CONTRACT_REWARD",
			request.expectedRevision,
			response.value.revision,
			"APPLIED",
			nil
		)
		contractsMessage = if response.value.duplicate
			then "Reward already claimed; showing the original Critter."
			elseif
				not collectionRefreshed or not contractsRefreshed
			then "Reward claimed, but UI refresh failed. Reward remains safely saved."
			else "Reward claimed and added to your Collection."
		profileState.finishMutation(mutationToken)
		mountRoute()
		return response
	end

	local function viewContractReward(critterId: string)
		refresh(false)
		local found = false
		for _, critter in if collection == nil then {} else collection.critters do
			if critter.id == critterId then
				found = true
				break
			end
		end
		if not found then
			contractsMessage = "REWARD_NOT_FOUND: Refresh the collection and try again."
			mountRoute()
			return
		end
		selectedCollectionCritterId = critterId
		contractReward = nil
		navigate("COLLECTION")
	end

	local function breedCritters(parentAId: string, parentBId: string)
		if breedingPending or collection == nil or currentRevision() == nil then
			return {
				ok = false,
				errors = { { code = "BREEDING_BLOCKED", message = "Breeding is not available." } },
			}
		end
		local fingerprint = `BREED_CRITTERS|{parentAId}|{parentBId}`
		local request = profileState.uncertainRequest(fingerprint)
			or {
				protocolVersion = BreedingProtocol.Version,
				kind = BreedingProtocol.RequestKinds.BREED_CRITTERS,
				commandId = `breed:{HttpService:GenerateGUID(false)}`,
				expectedRevision = currentRevision(),
				payload = {
					parentAId = parentAId,
					parentBId = parentBId,
				},
			}
		local mutationToken = profileState.beginMutation("BREED_CRITTERS", request)
		if mutationToken == nil then
			breedingMessage = "COMMAND_IN_PROGRESS: Another profile change is saving."
			mountRoute()
			return {
				ok = false,
				errors = { { code = "COMMAND_IN_PROGRESS", message = breedingMessage } },
			}
		end
		breedingPending = true
		breedingMessage = "Breeding..."
		mountRoute()
		trace(request.commandId, "BREED_CRITTERS", request.expectedRevision, nil, "STARTED", nil)
		local response = invokeBreeding(request)
		breedingPending = false
		if destroyed then
			profileState.finishMutation(mutationToken)
			return response
		end
		if not response.ok then
			local code = errorCode(response)
			if code == "NETWORK_ERROR" then
				profileState.rememberUncertain(fingerprint, request)
			else
				profileState.clearUncertain(fingerprint)
			end
			trace(
				request.commandId,
				"BREED_CRITTERS",
				request.expectedRevision,
				nil,
				"FAILED",
				code
			)
			breedingMessage = errorMessage(response)
			if code == "STALE_REVISION" then
				profileState.invalidate("collection")
				profileState.invalidate("eggs")
				refresh(false)
				refreshEggs()
				breedingMessage = "STALE_REVISION: Data refreshed. Review selection and retry."
			end
			profileState.finishMutation(mutationToken)
			mountRoute()
			return response
		end
		profileState.clearUncertain(fingerprint)
		profileState.applyMutationRevision(response.value.revision, { "collection", "eggs" })
		local collectionRefreshed = refresh(false)
		local eggsRefreshed = refreshEggs()
		trace(
			request.commandId,
			"BREED_CRITTERS",
			request.expectedRevision,
			response.value.revision,
			"APPLIED",
			nil
		)
		breedingMessage = if not collectionRefreshed or not eggsRefreshed
			then `Created egg {response.value.egg.eggId}, but UI refresh failed.`
			else `Created egg {response.value.egg.eggId} ({response.value.egg.status}).`
		profileState.finishMutation(mutationToken)
		mountRoute()
		return response
	end

	local function hatchEgg(eggId: string)
		if hatchPending or collection == nil or currentRevision() == nil then
			return {
				ok = false,
				errors = { { code = "HATCH_BLOCKED", message = "Hatching is not available." } },
			}
		end
		local fingerprint = `HATCH_EGG|{eggId}`
		local request = profileState.uncertainRequest(fingerprint)
			or {
				protocolVersion = EggProtocol.Version,
				kind = EggProtocol.RequestKinds.HATCH_EGG,
				commandId = `hatch:{HttpService:GenerateGUID(false)}`,
				expectedRevision = currentRevision(),
				payload = { eggId = eggId },
			}
		local mutationToken = profileState.beginMutation("HATCH_EGG", request)
		if mutationToken == nil then
			hatchMessage = "COMMAND_IN_PROGRESS: Another profile change is saving."
			mountRoute()
			return {
				ok = false,
				errors = { { code = "COMMAND_IN_PROGRESS", message = hatchMessage } },
			}
		end
		hatchPending = true
		hatchMessage = "Hatching..."
		mountRoute()
		trace(request.commandId, "HATCH_EGG", request.expectedRevision, nil, "STARTED", nil)
		local response = invokeEgg(request)
		hatchPending = false
		if destroyed then
			profileState.finishMutation(mutationToken)
			return response
		end
		if not response.ok then
			local code = errorCode(response)
			if code == "NETWORK_ERROR" then
				profileState.rememberUncertain(fingerprint, request)
			else
				profileState.clearUncertain(fingerprint)
			end
			trace(request.commandId, "HATCH_EGG", request.expectedRevision, nil, "FAILED", code)
			hatchMessage = errorMessage(response)
			if code == "STALE_REVISION" then
				profileState.invalidate("collection")
				profileState.invalidate("eggs")
				refresh(false)
				refreshEggs()
				hatchMessage = "STALE_REVISION: Data refreshed. Review the egg and retry."
			end
			profileState.finishMutation(mutationToken)
			mountRoute()
			return response
		end
		profileState.clearUncertain(fingerprint)
		profileState.applyMutationRevision(response.value.revision, { "collection", "eggs" })
		local collectionRefreshed = refresh(false)
		local eggsRefreshed = refreshEggs()
		hatchResult = CollectionPresentation.mapCritter(response.value.offspring)
		selectedEggTab = "HISTORY"
		selectedEggIds.HISTORY = eggId
		selectedEggIds.ACTIVE = nil
		trace(
			request.commandId,
			"HATCH_EGG",
			request.expectedRevision,
			response.value.revision,
			"APPLIED",
			nil
		)
		hatchMessage = if response.value.duplicate
			then "This egg was already hatched; showing the existing offspring."
			elseif
				not collectionRefreshed or not eggsRefreshed
			then `Hatched {hatchResult.displayName}, but UI refresh failed.`
			else `Hatched {hatchResult.displayName}.`
		profileState.finishMutation(mutationToken)
		mountRoute()
		return response
	end

	local function findCollectionCritter(critterId: string)
		if collection == nil then
			return nil
		end
		for _, critter in collection.critters do
			if critter.id == critterId then
				return critter
			end
		end
		return nil
	end

	local function viewOffspringInCollection(offspringId: string)
		local offspring = findCollectionCritter(offspringId)
		if offspring == nil then
			refresh(false)
			offspring = findCollectionCritter(offspringId)
		end
		if offspring == nil then
			hatchMessage = "OFFSPRING_NOT_FOUND: Refresh the collection and try again."
			mountRoute()
			return
		end
		hatchMessage = nil
		selectedCollectionCritterId = offspring.id
		navigation.navigate("COLLECTION")
	end

	navigate = function(route: string)
		message = nil
		navigation.navigate(route)
	end

	mountRoute = function()
		if destroyed or navigation == nil then
			return
		end
		destroyScreen()
		local route = navigation.current()
		if route == "MAIN_MENU" then
			activeScreen = MainMenuScreen.mount(playerGui, {
				onCollection = function()
					selectedCollectionCritterId = nil
					navigate("COLLECTION")
				end,
				onTeamBuilder = function()
					navigate("TEAM_BUILDER")
				end,
				onInventory = function()
					navigate("INVENTORY")
				end,
				onBreeding = function()
					navigate("BREEDING")
				end,
				onEggs = function()
					navigate("EGGS")
				end,
				onContracts = function()
					contractsMessage = nil
					contractReward = nil
					profileState.invalidate("contracts")
					navigate("CONTRACTS")
				end,
				onBattle = function()
					navigate("BATTLE")
				end,
				onSpritePreview = if RunService:IsStudio()
					then function()
						navigate("SPRITE_PREVIEW")
					end
					else nil,
			})
		elseif route == "COLLECTION" then
			if not profileState.isFresh("collection") and not refresh(false) then
				activeScreen = ProfileStatus.mount(playerGui, {
					message = message or "Loading collection...",
					canRetry = true,
					onRetry = mountRoute,
				})
				return
			end
			activeScreen = CollectionScreen.mount(playerGui, {
				collection = collection,
				selectedCritterId = selectedCollectionCritterId,
				onBack = function()
					navigate("MAIN_MENU")
				end,
			})
		elseif route == "TEAM_BUILDER" then
			if not profileState.isFresh("collection") and not refresh(false) then
				activeScreen = ProfileStatus.mount(playerGui, {
					message = message or "Loading team data...",
					canRetry = true,
					onRetry = mountRoute,
				})
				return
			end
			activeScreen = TeamBuilderScreen.mount(playerGui, {
				collection = collection,
				pending = profileState.mutationPending(),
				message = message,
				onBack = function()
					navigate("MAIN_MENU")
				end,
				onSave = function(ids)
					mutate(PlayerDataProtocol.RequestKinds.SET_TEAM, { critterIds = ids })
				end,
			})
		elseif route == "INVENTORY" then
			if
				(not profileState.isFresh("collection") or not profileState.isFresh("inventory"))
				and not refresh(true)
			then
				activeScreen = ProfileStatus.mount(playerGui, {
					message = message,
					canRetry = true,
					onRetry = mountRoute,
				})
				return
			end
			activeScreen = InventoryScreen.mount(playerGui, {
				collection = collection,
				inventory = inventory,
				pending = profileState.mutationPending(),
				message = message,
				onBack = function()
					navigate("MAIN_MENU")
				end,
				onEquip = function(critterId, instanceId)
					mutate(PlayerDataProtocol.RequestKinds.EQUIP_ITEM, {
						critterId = critterId,
						instanceId = instanceId,
					})
				end,
				onUnequip = function(critterId)
					mutate(PlayerDataProtocol.RequestKinds.UNEQUIP_ITEM, {
						critterId = critterId,
					})
				end,
			})
		elseif route == "BREEDING" then
			if not profileState.isFresh("collection") and not refresh(false) then
				activeScreen = ProfileStatus.mount(playerGui, {
					message = breedingMessage or "Loading breeding data...",
					canRetry = true,
					onRetry = mountRoute,
				})
				return
			end
			activeScreen = BreedingScreen.mount(playerGui, {
				collection = collection,
				pending = profileState.mutationPending(),
				message = breedingMessage,
				onBack = function()
					navigate("MAIN_MENU")
				end,
				onEggs = function()
					navigate("EGGS")
				end,
				onCheck = function(parentAId, parentBId)
					return invokeBreeding({
						protocolVersion = BreedingProtocol.Version,
						kind = BreedingProtocol.RequestKinds.CHECK_BREEDING,
						payload = {
							parentAId = parentAId,
							parentBId = parentBId,
						},
					})
				end,
				onPreviewCompatibility = function(parentAId, parentBId)
					return invokeBreeding({
						protocolVersion = BreedingProtocol.Version,
						kind = BreedingProtocol.RequestKinds.PREVIEW_BREEDING,
						payload = {
							parentAId = parentAId,
							parentBId = parentBId,
						},
					})
				end,
				onBreed = function(parentAId, parentBId)
					task.spawn(breedCritters, parentAId, parentBId)
				end,
			})
		elseif route == "EGGS" then
			if not profileState.isFresh("eggs") and not refreshEggs() then
				activeScreen = ProfileStatus.mount(playerGui, {
					message = eggsMessage or "Loading eggs...",
					canRetry = true,
					onRetry = mountRoute,
				})
				return
			end
			activeScreen = EggCollectionScreen.mount(playerGui, {
				eggs = eggs,
				selectedTab = selectedEggTab,
				selectedEggIds = selectedEggIds,
				pending = profileState.mutationPending(),
				message = hatchMessage,
				onTabChange = function(tab)
					selectedEggTab = tab
				end,
				onSelect = function(tab, eggId)
					selectedEggIds[tab] = eggId
				end,
				onBack = function()
					navigate("MAIN_MENU")
				end,
				onRefresh = function()
					profileState.invalidate("eggs")
					mountRoute()
				end,
				onHatch = function(eggId)
					hatchEgg(eggId)
				end,
				onViewOffspring = function(offspringId)
					viewOffspringInCollection(offspringId)
				end,
			})
		elseif route == "EGG_OFFSPRING" then
			if hatchResult == nil then
				navigate("EGGS")
				return
			end
			activeScreen = EggOffspringScreen.mount(playerGui, {
				critter = hatchResult,
				onBack = function()
					navigate("EGGS")
				end,
				onEggs = function()
					navigate("EGGS")
				end,
				onViewCollection = function()
					navigate("COLLECTION")
				end,
			})
		elseif route == "CONTRACTS" then
			if not profileState.isFresh("contracts") and not refreshContracts() then
				activeScreen = ProfileStatus.mount(playerGui, {
					message = contractsLoadError or "Loading contracts...",
					canRetry = true,
					onRetry = mountRoute,
				})
				return
			end
			activeScreen = ContractsScreen.mount(playerGui, {
				contracts = contracts.contracts,
				availableDefinitions = contracts.availableDefinitions,
				reward = contractReward,
				pending = profileState.mutationPending(),
				message = contractsMessage,
				onBack = function()
					navigate("MAIN_MENU")
				end,
				onAccept = function(definitionId, definitionVersion)
					acceptContract(definitionId, definitionVersion)
				end,
				onClaim = function(contractId)
					claimContract(contractId)
				end,
				onViewCollection = function(critterId)
					viewContractReward(critterId)
				end,
			})
		elseif route == "BATTLE" then
			activeScreen = BattleScreenController.start(playerGui, battleRequest, {
				onExitToMenu = function()
					profileState.invalidate("contracts")
					navigate("MAIN_MENU")
				end,
			})
		elseif route == "SPRITE_PREVIEW" and RunService:IsStudio() then
			activeScreen = SpritePreviewScreen.mount(playerGui, {
				onBack = function()
					navigate("MAIN_MENU")
				end,
			})
		end
	end

	navigation = NavigationController.new("MAIN_MENU", mountRoute)
	activeScreen = ProfileStatus.mount(playerGui, { message = "Loading profile..." })

	local function initialize()
		pending = true
		for _ = 1, 80 do
			if destroyed then
				return
			end
			local requestId = nextRequestId("collection.initialize")
			local token = profileState.beginRead("collection", requestId)
			local response = getCollection()
			if response.ok then
				local applied = profileState.applyRead(
					token,
					response.value.revision,
					CollectionPresentation.map(response.value)
				)
				trace(
					requestId,
					"GET_COLLECTION",
					nil,
					response.value.revision,
					if applied.applied then "APPLIED" else "IGNORED",
					applied.reason
				)
				collection = profileState.get("collection")
				pending = false
				message = nil
				mountRoute()
				return
			end
			if errorCode(response) ~= "PROFILE_NOT_READY" then
				pending = false
				message = errorMessage(response)
				destroyScreen()
				activeScreen = ProfileStatus.mount(playerGui, {
					message = message,
					canRetry = true,
					onRetry = function()
						task.spawn(initialize)
					end,
				})
				return
			end
			task.wait(0.25)
		end
		pending = false
		message = "PROFILE_LOAD_TIMEOUT: Profile did not become ready. Retry."
		destroyScreen()
		activeScreen = ProfileStatus.mount(playerGui, {
			message = message,
			canRetry = true,
			onRetry = function()
				task.spawn(initialize)
			end,
		})
	end
	task.spawn(initialize)

	local handle: any = nil
	handle = table.freeze({
		destroy = function()
			destroyed = true
			profileState.destroy()
			destroyScreen()
			navigation.destroy()
			if activeHandle == handle then
				activeHandle = nil
			end
		end,
	})
	activeHandle = handle
	return handle
end

return table.freeze(AppController)
