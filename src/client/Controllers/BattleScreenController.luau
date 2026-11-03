--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BattlePresentationMapper = require(script.Parent.Parent.Presentation.BattlePresentationMapper)
local BattlePlayback = require(script.Parent.Parent.Presentation.BattlePlayback)
local TargetSelection = require(script.Parent.Parent.Presentation.TargetSelection)
local AssetCatalog = require(script.Parent.Parent.Assets.AssetCatalog)
local BattleScreen = require(script.Parent.Parent.UI.Components.BattleScreen)
local Protocol = require(ReplicatedStorage.Shared.Network.Protocol)

local BattleScreenController = {}
local activeControllerHandle: any = nil

local function errorMessage(response): string
	if
		type(response) == "table"
		and type(response.errors) == "table"
		and response.errors[1] ~= nil
	then
		return `{response.errors[1].code}: {response.errors[1].message}`
	end
	return "NETWORK_ERROR: Battle request failed"
end

function BattleScreenController.start(playerGui: PlayerGui, battleRequest: RemoteFunction)
	if activeControllerHandle ~= nil then
		activeControllerHandle.destroy()
		activeControllerHandle = nil
	end

	local loading = Instance.new("ScreenGui")
	loading.Name = "CritterboundLoadingScreen"
	loading.ResetOnSpawn = false
	loading.Parent = playerGui
	local loadingLabel = Instance.new("TextLabel")
	loadingLabel.BackgroundColor3 = Color3.fromRGB(20, 24, 30)
	loadingLabel.Size = UDim2.fromScale(1, 1)
	loadingLabel.Text = "Entering Training Grounds..."
	loadingLabel.TextColor3 = Color3.new(1, 1, 1)
	loadingLabel.TextScaled = true
	loadingLabel.Parent = loading

	local destroyed = false
	local snapshot: any = nil
	local model: any = nil
	local screenHandle: any = nil
	local pendingCard: any = nil
	local selectableTargetIds = {}
	local activeCombatantIds = {}
	local message: string? = nil
	local networkPending = false
	local playbackActive = false
	local commandCounter = 0
	local playbackEpoch = 0

	local function resolveAsset(id: string)
		return AssetCatalog:resolve(id)
	end

	local function planningState()
		return {
			selectedCardInstanceId = if pendingCard ~= nil then pendingCard.id else nil,
			queuedCards = if model ~= nil then model.visibleQueue else {},
			committed = if model ~= nil then not model.canPlan else true,
			error = nil,
		}
	end

	local updateScreen: () -> ()
	local sendCommand: (string, any) -> ()

	local function buildProps()
		return {
			model = model,
			planningState = planningState(),
			energy = model.energy,
			resolveAsset = resolveAsset,
			onCardSelected = function(card)
				if networkPending or not model.canPlan then
					return
				end
				if TargetSelection.needsSelection(card) then
					pendingCard = card
					selectableTargetIds = TargetSelection.legalTargetIds(card, model)
					message = if #selectableTargetIds > 0
						then `Select target for {card.displayName}`
						else "No legal target"
					updateScreen()
					return
				end
				local targets = if card.targetingRule == "SELF"
					then { card.sourceCombatantId }
					else {}
				sendCommand("QUEUE_CARD", {
					cardInstanceId = card.id,
					sourceCombatantId = card.sourceCombatantId,
					targetCombatantIds = targets,
				})
			end,
			onRemoveCard = function(cardInstanceId)
				sendCommand("REMOVE_QUEUED_CARD", { cardInstanceId = cardInstanceId })
			end,
			onReorderCard = function(cardInstanceId, newIndex)
				sendCommand("REORDER_QUEUED_CARD", {
					cardInstanceId = cardInstanceId,
					newIndex = newIndex,
				})
			end,
			onCritterSelected = function(combatantId)
				if pendingCard == nil then
					return
				end
				if table.find(selectableTargetIds, combatantId) == nil then
					message = "Invalid target"
					updateScreen()
					return
				end
				local card = pendingCard
				pendingCard = nil
				selectableTargetIds = {}
				sendCommand("QUEUE_CARD", {
					cardInstanceId = card.id,
					sourceCombatantId = card.sourceCombatantId,
					targetCombatantIds = { combatantId },
				})
			end,
			onCommit = function()
				sendCommand("COMMIT_PLAN", {})
			end,
			onReset = function()
				pendingCard = nil
				selectableTargetIds = {}
				sendCommand("CLEAR_PLAN", {})
			end,
			onRestart = function()
				playbackEpoch += 1
				playbackActive = false
				task.spawn(function()
					if networkPending or destroyed then
						return
					end
					networkPending = true
					message = "Restarting Training Grounds..."
					updateScreen()
					commandCounter += 1
					local ok, response = pcall(function()
						return battleRequest:InvokeServer({
							kind = Protocol.RequestKinds.RESTART_BATTLE,
							requestId = `restart:{commandCounter}`,
						})
					end)
					networkPending = false
					if not ok or not response.ok then
						message = errorMessage(response)
						updateScreen()
						return
					end
					snapshot = response.value.snapshot
					local mapped = BattlePresentationMapper.map(snapshot)
					if not mapped.ok then
						message = errorMessage(mapped)
						updateScreen()
						return
					end
					model = mapped.value
					pendingCard = nil
					selectableTargetIds = {}
					activeCombatantIds = {}
					message = nil
					updateScreen()
				end)
			end,
			selectableTargetIds = selectableTargetIds,
			activeCombatantIds = activeCombatantIds,
			requestPending = networkPending or playbackActive,
			message = message,
		}
	end

	updateScreen = function()
		if screenHandle ~= nil and model ~= nil and not destroyed then
			screenHandle.update(buildProps())
		end
	end

	local function mapSnapshot(nextSnapshot): boolean
		local mapped = BattlePresentationMapper.map(nextSnapshot)
		if not mapped.ok then
			message = errorMessage(mapped)
			return false
		end
		snapshot = nextSnapshot
		model = mapped.value
		return true
	end

	local function playResolution(resolution)
		playbackEpoch += 1
		local epoch = playbackEpoch
		playbackActive = true
		local playback = BattlePlayback.new(resolution.preSnapshot)
		if not mapSnapshot(playback.snapshot) then
			playbackActive = false
			updateScreen()
			return
		end
		for _, event in resolution.events do
			if destroyed or epoch ~= playbackEpoch then
				return
			end
			playback = BattlePlayback.apply(playback, event)
			if not mapSnapshot(playback.snapshot) then
				playbackActive = false
				updateScreen()
				return
			end
			activeCombatantIds = {}
			if playback.activeSourceCombatantId ~= nil then
				table.insert(activeCombatantIds, playback.activeSourceCombatantId)
			end
			for _, id in playback.activeTargetCombatantIds do
				table.insert(activeCombatantIds, id)
			end
			message = playback.message
			updateScreen()
			task.wait(0.18)
		end
		if destroyed or epoch ~= playbackEpoch then
			return
		end
		mapSnapshot(resolution.finalSnapshot)
		playbackActive = false
		activeCombatantIds = {}
		pendingCard = nil
		selectableTargetIds = {}
		message = if model.matchOutcome ~= nil then "Battle complete" else "Plan next round"
		updateScreen()
	end

	local function requestSnapshot()
		local ok, response = pcall(function()
			return battleRequest:InvokeServer({ kind = Protocol.RequestKinds.REQUEST_SNAPSHOT })
		end)
		if ok and response.ok then
			mapSnapshot(response.value.snapshot)
		end
	end

	sendCommand = function(commandType: string, payload)
		if networkPending or playbackActive or destroyed or snapshot == nil then
			return
		end
		task.spawn(function()
			networkPending = true
			message = "Sending command..."
			updateScreen()
			commandCounter += 1
			local envelope = {
				protocolVersion = Protocol.Version,
				matchId = model.battleId,
				teamId = model.viewerTeamId,
				commandId = `client:{model.battleId}:{commandCounter}`,
				expectedStateVersion = model.revision,
				expectedPlanVersion = model.planVersion,
				commandType = commandType,
				payload = payload,
			}
			local ok, response = pcall(function()
				return battleRequest:InvokeServer({
					kind = Protocol.RequestKinds.COMMAND,
					envelope = envelope,
				})
			end)
			networkPending = false
			if not ok or not response.ok then
				message = errorMessage(response)
				if type(response) == "table" and type(response.errors) == "table" then
					local code = response.errors[1] and response.errors[1].code
					if code == "STALE_STATE_VERSION" or code == "STALE_PLAN_VERSION" then
						requestSnapshot()
					end
				end
				updateScreen()
				return
			end
			pendingCard = nil
			selectableTargetIds = {}
			if response.value.resolution ~= nil then
				playResolution(response.value.resolution)
			else
				mapSnapshot(response.value.snapshot)
				message = if response.value.duplicate then "Command already accepted" else nil
				updateScreen()
			end
		end)
	end

	task.spawn(function()
		local ok, response = pcall(function()
			return battleRequest:InvokeServer({ kind = Protocol.RequestKinds.START_BATTLE })
		end)
		if destroyed then
			return
		end
		if not ok or not response.ok or not mapSnapshot(response.value.snapshot) then
			loadingLabel.Text = errorMessage(response)
			return
		end
		loading:Destroy()
		screenHandle = BattleScreen.mount(playerGui, buildProps())
	end)

	local controllerHandle: any = nil
	controllerHandle = table.freeze({
		destroy = function()
			destroyed = true
			playbackEpoch += 1
			if loading.Parent ~= nil then
				loading:Destroy()
			end
			if screenHandle ~= nil then
				screenHandle.destroy()
				screenHandle = nil
			end
			if activeControllerHandle == controllerHandle then
				activeControllerHandle = nil
			end
		end,
	})
	activeControllerHandle = controllerHandle
	return controllerHandle
end

return table.freeze(BattleScreenController)
