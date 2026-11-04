--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local BattlePresentationMapper = require(script.Parent.Parent.Presentation.BattlePresentationMapper)
local BattlePlayback = require(script.Parent.Parent.Presentation.BattlePlayback)
local BattleSnapshotOrder = require(script.Parent.Parent.Presentation.BattleSnapshotOrder)
local PlanningState = require(script.Parent.Parent.Presentation.PlanningState)
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

function BattleScreenController.start(playerGui: PlayerGui, battleRequest: RemoteFunction, options)
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
	local animationCommandsByCritterId = {}
	local animationSequence = 0
	local message: string? = nil
	local networkPending = false
	local playbackActive = false
	local commandCounter = 0
	local playbackEpoch = 0
	local playbackFastForward = false
	local playedEventIds = {}
	local playbackPresentation = {
		active = false,
		currentActionName = nil,
		logEntries = {},
		roundTransition = false,
		fastForward = false,
		actingCombatantId = nil,
		targetCombatantIds = {},
		feedbackByCombatantId = {},
	}
	local deadlineEpoch = 0
	local snapshotVersion: any = nil

	local function resolveAsset(id: string)
		return AssetCatalog:resolve(id)
	end

	local function planningState()
		local queuedCards = if model ~= nil then model.visibleQueue else {}
		local state = {
			selectedCardInstanceId = if pendingCard ~= nil then pendingCard.id else nil,
			queuedCards = queuedCards,
			committed = if model ~= nil then model.committed else true,
			error = nil,
		}
		local disabledReasons = {}
		local targetDescriptions = {}
		if model ~= nil then
			for _, card in model.hand do
				local reason = PlanningState.cardDisabledReason(state, card, model)
				if reason == nil and TargetSelection.needsSelection(card) then
					if #TargetSelection.legalTargetIds(card, model) == 0 then
						reason = "No valid targets"
					end
				end
				if (networkPending or playbackActive) and reason == nil then
					reason = "Battle update in progress"
				end
				disabledReasons[card.id] = reason
				targetDescriptions[card.id] = TargetSelection.ruleDescription(card)
			end
		end
		return {
			selectedCardInstanceId = state.selectedCardInstanceId,
			queuedCards = queuedCards,
			committed = state.committed,
			planningLocked = if model ~= nil then not model.canPlan else true,
			error = nil,
			disabledReasons = disabledReasons,
			targetDescriptions = targetDescriptions,
			maxQueuedCardsPerCritter = PlanningState.MaxQueuedCardsPerCritter,
		}
	end

	local updateScreen: () -> ()
	local sendCommand: (string, any) -> ()
	local mapSnapshot: (any) -> boolean

	local function buildProps()
		return {
			model = model,
			planningState = planningState(),
			energy = model.energy,
			resolveAsset = resolveAsset,
			onCardSelected = function(card)
				if networkPending then
					return
				end
				if not model.canPlan then
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
				sendCommand("QUEUE_CARD", {
					cardInstanceId = card.id,
					sourceCombatantId = card.sourceCombatantId,
					targetCombatantIds = {},
				})
			end,
			onRemoveCard = function(cardInstanceId)
				if networkPending or not model.canPlan then
					return
				end
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
				if networkPending or not model.canRequestCommit then
					return
				end
				sendCommand("COMMIT_PLAN", {})
			end,
			onReset = function()
				if networkPending or not model.canPlan then
					return
				end
				pendingCard = nil
				selectableTargetIds = {}
				sendCommand("CLEAR_PLAN", {})
			end,
			onUndo = function()
				if networkPending or not model.canPlan then
					return
				end
				local last = model.visibleQueue[#model.visibleQueue]
				if last ~= nil then
					sendCommand("REMOVE_QUEUED_CARD", { cardInstanceId = last.card.id })
				end
			end,
			onRestart = function()
				playbackEpoch += 1
				playbackActive = false
				playbackFastForward = false
				playedEventIds = {}
				playbackPresentation = {
					active = false,
					currentActionName = nil,
					logEntries = {},
					roundTransition = false,
					fastForward = false,
					actingCombatantId = nil,
					targetCombatantIds = {},
					feedbackByCombatantId = {},
				}
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
					snapshotVersion = nil
					if not mapSnapshot(snapshot) then
						message = "INVALID_SNAPSHOT: Restart snapshot could not be mapped"
						updateScreen()
						return
					end
					pendingCard = nil
					selectableTargetIds = {}
					activeCombatantIds = {}
					animationCommandsByCritterId = {}
					message = nil
					updateScreen()
				end)
			end,
			onExitToMenu = function()
				if options ~= nil and options.onExitToMenu ~= nil then
					options.onExitToMenu()
				end
			end,
			onSkipPlayback = function()
				if playbackActive then
					playbackFastForward = true
					playbackPresentation.fastForward = true
					message = "Fast-forwarding presentation..."
					updateScreen()
				end
			end,
			selectableTargetIds = selectableTargetIds,
			activeCombatantIds = activeCombatantIds,
			animationCommandsByCritterId = animationCommandsByCritterId,
			requestPending = networkPending or playbackActive,
			message = message,
			playbackState = playbackPresentation,
		}
	end

	updateScreen = function()
		if screenHandle ~= nil and model ~= nil and not destroyed then
			screenHandle.update(buildProps())
		end
	end

	local requestSnapshot: () -> ()
	local function scheduleDeadlineRefresh()
		deadlineEpoch += 1
		local epoch = deadlineEpoch
		if model == nil or model.phase ~= "PLANNING" or model.planningDeadline == nil then
			return
		end
		local delaySeconds = math.max(0, model.planningDeadline - Workspace:GetServerTimeNow())
		task.delay(delaySeconds + 0.05, function()
			if destroyed or epoch ~= deadlineEpoch then
				return
			end
			requestSnapshot()
			updateScreen()
		end)
	end

	mapSnapshot = function(nextSnapshot): boolean
		if not BattleSnapshotOrder.shouldApply(snapshotVersion, nextSnapshot) then
			return true
		end
		local mapped = BattlePresentationMapper.map(nextSnapshot)
		if not mapped.ok then
			message = errorMessage(mapped)
			return false
		end
		snapshot = nextSnapshot
		model = mapped.value
		snapshotVersion = BattleSnapshotOrder.version(nextSnapshot)
		scheduleDeadlineRefresh()
		return true
	end

	local function playResolution(resolution)
		playbackEpoch += 1
		local epoch = playbackEpoch
		playbackActive = true
		playbackFastForward = false
		local playback = BattlePlayback.new(resolution.preSnapshot)
		playbackPresentation = {
			active = true,
			currentActionName = playback.currentActionName,
			logEntries = playback.logEntries,
			roundTransition = false,
			fastForward = false,
			actingCombatantId = nil,
			targetCombatantIds = {},
			feedbackByCombatantId = {},
		}
		if not mapSnapshot(playback.snapshot) then
			playbackActive = false
			updateScreen()
			return
		end
		for _, event in resolution.events do
			if destroyed or epoch ~= playbackEpoch then
				return
			end
			if event.id ~= nil and playedEventIds[event.id] then
				continue
			end
			local nextPlayback = BattlePlayback.apply(playback, event)
			if nextPlayback == playback then
				continue
			end
			playback = nextPlayback
			if event.id ~= nil then
				playedEventIds[event.id] = true
			end
			if not mapSnapshot(playback.snapshot) then
				playbackActive = false
				updateScreen()
				return
			end
			activeCombatantIds = {}
			animationCommandsByCritterId = {}
			if playback.activeSourceCombatantId ~= nil then
				table.insert(activeCombatantIds, playback.activeSourceCombatantId)
			end
			for _, id in playback.activeTargetCombatantIds do
				table.insert(activeCombatantIds, id)
			end
			message = playback.message
			playbackPresentation = {
				active = true,
				currentActionName = playback.currentActionName,
				logEntries = playback.logEntries,
				roundTransition = playback.roundTransition,
				fastForward = playbackFastForward,
				actingCombatantId = playback.activeSourceCombatantId,
				targetCombatantIds = playback.activeTargetCombatantIds,
				feedbackByCombatantId = playback.feedbackByCombatantId,
			}
			if not playbackFastForward then
				local animationId = nil
				local animationCritterId = nil
				local payload = event.payload or {}
				if event.kind == "CARD_PLAYED" then
					animationId = "ATTACK"
					animationCritterId = event.sourceCombatantId
				elseif event.kind == "DAMAGE_APPLIED" or event.kind == "STATUS_TICKED" then
					animationId = "HIT"
					animationCritterId = payload.targetCombatantId
				elseif event.kind == "CRITTER_DEFEATED" then
					animationId = "DEFEAT"
					animationCritterId = payload.combatantId
				end
				if animationId ~= nil and animationCritterId ~= nil then
					animationSequence += 1
					animationCommandsByCritterId[animationCritterId] = {
						id = animationId,
						sequence = animationSequence,
					}
				end
				updateScreen()
			end
			if not playbackFastForward then
				task.wait(if event.kind == "ROUND_COMPLETED" then 0.8 else 0.2)
			end
		end
		if destroyed or epoch ~= playbackEpoch then
			return
		end
		mapSnapshot(resolution.finalSnapshot)
		playbackActive = false
		playbackFastForward = false
		playbackPresentation.active = false
		playbackPresentation.fastForward = false
		activeCombatantIds = {}
		pendingCard = nil
		selectableTargetIds = {}
		message = if model.matchOutcome ~= nil then "Battle complete" else "Plan next round"
		updateScreen()
	end

	requestSnapshot = function()
		local ok, response = pcall(function()
			return battleRequest:InvokeServer({ kind = Protocol.RequestKinds.REQUEST_SNAPSHOT })
		end)
		if ok and response.ok then
			if playbackActive then
				playbackEpoch += 1
				playbackActive = false
				playbackFastForward = false
				playbackPresentation.active = false
				activeCombatantIds = {}
				animationCommandsByCritterId = {}
			end
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
			deadlineEpoch += 1
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
