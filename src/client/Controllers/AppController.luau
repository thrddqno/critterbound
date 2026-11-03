--!strict

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataProtocol = require(ReplicatedStorage.Shared.Network.PlayerDataProtocol)
local CollectionPresentation = require(script.Parent.Parent.Presentation.CollectionPresentation)
local NavigationController = require(script.Parent.NavigationController)
local BattleScreenController = require(script.Parent.BattleScreenController)
local ProfileStatus = require(script.Parent.Parent.UI.Components.ProfileStatus)
local MainMenuScreen = require(script.Parent.Parent.UI.Components.MainMenuScreen)
local CollectionScreen = require(script.Parent.Parent.UI.Components.CollectionScreen)
local TeamBuilderScreen = require(script.Parent.Parent.UI.Components.TeamBuilderScreen)
local InventoryScreen = require(script.Parent.Parent.UI.Components.InventoryScreen)

local AppController = {}
local activeHandle: any = nil

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
	battleRequest: RemoteFunction
)
	if activeHandle ~= nil then
		activeHandle.destroy()
	end
	local destroyed = false
	local activeScreen: any = nil
	local navigation: any = nil
	local collection: any = nil
	local inventory: any = nil
	local pending = false
	local message: string? = nil
	local retryMutation: any = nil
	local mountRoute: () -> ()

	local function destroyScreen()
		if activeScreen ~= nil then
			activeScreen.destroy()
			activeScreen = nil
		end
	end

	local function invoke(request)
		local ok, response = pcall(function()
			return playerDataRequest:InvokeServer(request)
		end)
		if not ok then
			return {
				ok = false,
				errors = { { code = "NETWORK_ERROR", message = "Request failed" } },
			}
		end
		return response
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
		local collectionResult = getCollection()
		if not collectionResult.ok then
			message = errorMessage(collectionResult)
			return false
		end
		collection = CollectionPresentation.map(collectionResult.value)
		if includeInventory then
			local inventoryResult = getInventory()
			if not inventoryResult.ok then
				message = errorMessage(inventoryResult)
				return false
			end
			inventory = inventoryResult.value
		end
		return true
	end

	local function mutate(kind: string, payload)
		if pending or collection == nil then
			return
		end
		pending = true
		message = "Saving..."
		mountRoute()
		local fingerprint = mutationFingerprint(kind, payload)
		local commandId = if retryMutation ~= nil
				and retryMutation.fingerprint == fingerprint
			then retryMutation.commandId
			else `player:{HttpService:GenerateGUID(false)}`
		local response = invoke({
			protocolVersion = PlayerDataProtocol.Version,
			kind = kind,
			commandId = commandId,
			expectedRevision = collection.revision,
			payload = payload,
		})
		pending = false
		if destroyed then
			return
		end
		if not response.ok then
			local code = errorCode(response)
			if code == "NETWORK_ERROR" then
				retryMutation = { fingerprint = fingerprint, commandId = commandId }
			else
				retryMutation = nil
			end
			message = errorMessage(response)
			if code == "STALE_PROFILE" then
				refresh(true)
				message = "STALE_PROFILE: Data refreshed. Review selection and retry."
			end
			mountRoute()
			return
		end
		retryMutation = nil
		collection = CollectionPresentation.map(response.value.collection)
		inventory = response.value.inventory
		message = if response.value.duplicate
			then "Command already accepted; current data restored."
			else "Saved successfully."
		mountRoute()
	end

	local function navigate(route: string)
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
					navigate("COLLECTION")
				end,
				onTeamBuilder = function()
					navigate("TEAM_BUILDER")
				end,
				onInventory = function()
					navigate("INVENTORY")
				end,
				onBattle = function()
					navigate("BATTLE")
				end,
			})
		elseif route == "COLLECTION" then
			activeScreen = CollectionScreen.mount(playerGui, {
				collection = collection,
				onBack = function()
					navigate("MAIN_MENU")
				end,
			})
		elseif route == "TEAM_BUILDER" then
			activeScreen = TeamBuilderScreen.mount(playerGui, {
				collection = collection,
				pending = pending,
				message = message,
				onBack = function()
					navigate("MAIN_MENU")
				end,
				onSave = function(ids)
					task.spawn(
						mutate,
						PlayerDataProtocol.RequestKinds.SET_TEAM,
						{ critterIds = ids }
					)
				end,
			})
		elseif route == "INVENTORY" then
			if inventory == nil and not refresh(true) then
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
				pending = pending,
				message = message,
				onBack = function()
					navigate("MAIN_MENU")
				end,
				onEquip = function(critterId, instanceId)
					task.spawn(mutate, PlayerDataProtocol.RequestKinds.EQUIP_ITEM, {
						critterId = critterId,
						instanceId = instanceId,
					})
				end,
				onUnequip = function(critterId)
					task.spawn(mutate, PlayerDataProtocol.RequestKinds.UNEQUIP_ITEM, {
						critterId = critterId,
					})
				end,
			})
		elseif route == "BATTLE" then
			activeScreen = BattleScreenController.start(playerGui, battleRequest, {
				onExitToMenu = function()
					refresh(false)
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
			local response = getCollection()
			if response.ok then
				collection = CollectionPresentation.map(response.value)
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
