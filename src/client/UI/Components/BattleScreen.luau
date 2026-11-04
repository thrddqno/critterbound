--!strict

local Theme = require(script.Parent.Parent.Theme)
local BattlefieldView = require(script.Parent.BattlefieldView)
local InitiativeTimeline = require(script.Parent.InitiativeTimeline)
local CardHand = require(script.Parent.CardHand)
local CardQueue = require(script.Parent.CardQueue)
local EnergyCounter = require(script.Parent.EnergyCounter)
local BattlePhaseIndicator = require(script.Parent.BattlePhaseIndicator)
local CommitButton = require(script.Parent.CommitButton)
local ResetButton = require(script.Parent.ResetButton)
local CombatLog = require(script.Parent.CombatLog)
local BattleHudLayout = require(script.Parent.Parent.Parent.Presentation.BattleHudLayout)
local BattleHandLayout = require(script.Parent.Parent.Parent.Presentation.BattleHandLayout)

local BattleScreen = {}

local function applyRect(instance: GuiObject, value)
	instance.Position = UDim2.fromOffset(value.x, value.y)
	instance.Size = UDim2.fromOffset(value.width, value.height)
end

local function livingViewerCritters(model)
	local result = {}
	for _, critter in model.critters do
		if critter.teamId == model.viewerTeamId and not critter.defeated then
			table.insert(result, critter)
		end
	end
	return result
end

export type Props = {
	model: any,
	planningState: any,
	energy: any,
	resolveAsset: (string) -> any,
	onCardSelected: (any) -> (),
	onRemoveCard: (string) -> (),
	onReorderCard: (string, number) -> (),
	onCritterSelected: (string) -> (),
	onCommit: () -> (),
	onReset: () -> (),
	onUndo: () -> (),
	onSkipPlayback: () -> (),
	onRestart: () -> (),
	onExitToMenu: () -> (),
	selectableTargetIds: { string },
	activeCombatantIds: { string },
	animationCommandsByCritterId: { [string]: any }?,
	requestPending: boolean?,
	message: string?,
	playbackState: any,
}

function BattleScreen.mount(parent: Instance, props: Props)
	local screen = Instance.new("ScreenGui")
	screen.Name = "CritterboundBattleScreen"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.Parent = parent

	local root = Instance.new("ScrollingFrame")
	root.Name = "Root"
	root.BackgroundColor3 = Theme.Background
	root.BorderSizePixel = 0
	root.CanvasSize = UDim2.fromOffset(0, 0)
	root.ScrollBarThickness = 3
	root.ScrollingDirection = Enum.ScrollingDirection.Y
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = screen

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Parent = root

	local header = Instance.new("Frame")
	header.Name = "TopHud"
	header.BackgroundTransparency = 1
	header.Parent = content

	local phaseHost = Instance.new("Frame")
	phaseHost.BackgroundTransparency = 1
	phaseHost.Size = UDim2.fromScale(0.62, 1)
	phaseHost.Parent = header
	local energyHost = Instance.new("Frame")
	energyHost.BackgroundTransparency = 1
	energyHost.Position = UDim2.fromScale(0.62, 0)
	energyHost.Size = UDim2.fromScale(0.38, 1)
	energyHost.Parent = header

	local initiativeHost = Instance.new("Frame")
	initiativeHost.Name = "InitiativeHost"
	initiativeHost.BackgroundTransparency = 1
	initiativeHost.Parent = content

	local battlefieldHost = Instance.new("Frame")
	battlefieldHost.Name = "BattlefieldHost"
	battlefieldHost.BackgroundTransparency = 1
	battlefieldHost.Parent = content

	local queueHost = Instance.new("Frame")
	queueHost.Name = "QueueHost"
	queueHost.BackgroundTransparency = 1
	queueHost.Parent = content

	local handHost = Instance.new("Frame")
	handHost.Name = "HandHost"
	handHost.BackgroundTransparency = 1
	handHost.Parent = content

	local controls = Instance.new("Frame")
	controls.Name = "Controls"
	controls.BackgroundColor3 = Theme.Panel
	controls.BackgroundTransparency = 0.08
	controls.Parent = content
	local controlsCorner = Instance.new("UICorner")
	controlsCorner.CornerRadius = UDim.new(0, 7)
	controlsCorner.Parent = controls

	local phaseHandle = BattlePhaseIndicator.mount(phaseHost, {
		phase = props.model.phase,
		roundNumber = props.model.roundNumber,
		planningDeadline = props.model.planningDeadline,
		committed = props.model.committed,
		bloodMoon = props.model.bloodMoon,
	})
	phaseHandle.instance.Size = UDim2.fromScale(1, 1)
	local energyHandle = EnergyCounter.mount(energyHost, props.energy)
	energyHandle.instance.Size = UDim2.fromScale(1, 1)
	local initiativeHandle = InitiativeTimeline.mount(initiativeHost, {
		entries = props.model.initiative,
		compact = false,
	})
	initiativeHandle.instance.Size = UDim2.fromScale(1, 1)
	local battlefieldHandle = BattlefieldView.mount(battlefieldHost, {
		teams = props.model.teams,
		resolveAsset = props.resolveAsset,
		compact = false,
	})
	battlefieldHandle.instance.Size = UDim2.fromScale(1, 1)
	local queueHandle = CardQueue.mount(queueHost, {
		entries = props.planningState.queuedCards,
		critters = livingViewerCritters(props.model),
		capacity = props.planningState.maxQueuedCardsPerCritter,
		locked = props.planningState.planningLocked,
		compact = false,
		onRemove = props.onRemoveCard,
	})
	queueHandle.instance.Size = UDim2.fromScale(1, 1)
	local combatLogHandle = CombatLog.mount(queueHost, {
		active = props.playbackState.active,
		currentActionName = props.playbackState.currentActionName,
		logEntries = props.playbackState.logEntries,
		roundTransition = props.playbackState.roundTransition,
		fastForward = props.playbackState.fastForward,
		onSkip = props.onSkipPlayback,
	})
	combatLogHandle.instance.Size = UDim2.fromScale(1, 1)
	local handHandle = CardHand.mount(handHost, {
		cards = props.model.hand,
		planningState = props.planningState,
		resolveAsset = props.resolveAsset,
		onCardSelected = props.onCardSelected,
		compact = false,
	})
	handHandle.instance.Position = UDim2.fromOffset(0, BattleHandLayout.HEADER_HEIGHT)
	handHandle.instance.Size = UDim2.new(1, 0, 1, -BattleHandLayout.HEADER_HEIGHT)
	local handCountLabel = Instance.new("TextLabel")
	handCountLabel.Name = "CardZoneCounts"
	handCountLabel.BackgroundTransparency = 1
	handCountLabel.Size = UDim2.new(1, -12, 0, BattleHandLayout.HEADER_HEIGHT)
	handCountLabel.TextColor3 = Theme.MutedText
	handCountLabel.TextSize = 10
	handCountLabel.TextXAlignment = Enum.TextXAlignment.Left
	handCountLabel.Parent = handHost
	local commitHandle = CommitButton.mount(controls, {
		committed = props.planningState.committed,
		disabled = not props.model.canRequestCommit or props.planningState.committed,
		onActivated = props.onCommit,
	})
	local resetHandle = ResetButton.mount(controls, { onActivated = props.onReset })
	local undoHandle = ResetButton.mount(controls, {
		onActivated = props.onUndo,
		label = "Undo Last Action",
	})
	undoHandle.instance.Name = "UndoLastActionButton"

	local resultOverlay = Instance.new("Frame")
	resultOverlay.Name = "BattleResultOverlay"
	resultOverlay.BackgroundColor3 = Theme.Background
	resultOverlay.BackgroundTransparency = 0.08
	resultOverlay.BorderColor3 = Theme.Action
	resultOverlay.BorderSizePixel = 3
	resultOverlay.Position = UDim2.fromScale(0.25, 0.25)
	resultOverlay.Size = UDim2.fromScale(0.5, 0.5)
	resultOverlay.ZIndex = 20
	resultOverlay.Visible = false
	resultOverlay.Parent = screen
	local resultText = Instance.new("TextLabel")
	resultText.Name = "ResultTitle"
	resultText.BackgroundTransparency = 1
	resultText.Position = UDim2.fromScale(0.1, 0.08)
	resultText.Size = UDim2.fromScale(0.8, 0.22)
	resultText.TextColor3 = Theme.Text
	resultText.TextScaled = true
	resultText.ZIndex = 21
	resultText.Parent = resultOverlay
	local summaryText = Instance.new("TextLabel")
	summaryText.Name = "ResultSummary"
	summaryText.BackgroundTransparency = 1
	summaryText.Position = UDim2.fromScale(0.1, 0.33)
	summaryText.Size = UDim2.fromScale(0.8, 0.3)
	summaryText.TextColor3 = Theme.MutedText
	summaryText.TextScaled = true
	summaryText.TextWrapped = true
	summaryText.ZIndex = 21
	summaryText.Parent = resultOverlay
	local restartButton = Instance.new("TextButton")
	restartButton.Name = "RestartBattle"
	restartButton.BackgroundColor3 = Theme.Action
	restartButton.Position = UDim2.fromScale(0.08, 0.7)
	restartButton.Size = UDim2.fromScale(0.4, 0.18)
	restartButton.Text = "Restart Training Grounds"
	restartButton.TextColor3 = Theme.Text
	restartButton.TextScaled = true
	restartButton.ZIndex = 21
	restartButton.Parent = resultOverlay
	local currentProps = props
	local restartConnection = restartButton.Activated:Connect(function()
		currentProps.onRestart()
	end)
	local resultMenuButton = Instance.new("TextButton")
	resultMenuButton.Name = "ResultMainMenu"
	resultMenuButton.BackgroundColor3 = Theme.PanelAlt
	resultMenuButton.Position = UDim2.fromScale(0.52, 0.7)
	resultMenuButton.Size = UDim2.fromScale(0.4, 0.18)
	resultMenuButton.Text = "Back to Main Menu"
	resultMenuButton.TextColor3 = Theme.Text
	resultMenuButton.TextScaled = true
	resultMenuButton.ZIndex = 21
	resultMenuButton.Parent = resultOverlay
	local resultMenuConnection = resultMenuButton.Activated:Connect(function()
		currentProps.onExitToMenu()
	end)
	local exitButton = Instance.new("TextButton")
	exitButton.Name = "ExitToMenu"
	exitButton.BackgroundColor3 = Theme.PanelAlt
	exitButton.Position = UDim2.new(1, -142, 0, 6)
	exitButton.Size = UDim2.fromOffset(132, 44)
	exitButton.Text = "Main Menu"
	exitButton.TextColor3 = Theme.Text
	exitButton.TextSize = 15
	exitButton.ZIndex = 15
	exitButton.Parent = screen
	local exitConnection = exitButton.Activated:Connect(function()
		currentProps.onExitToMenu()
	end)

	local messageLabel = Instance.new("TextLabel")
	messageLabel.Name = "LocalPlanningMessage"
	messageLabel.BackgroundColor3 = Theme.Panel
	messageLabel.BorderSizePixel = 0
	messageLabel.TextColor3 = Theme.Error
	messageLabel.TextSize = 11
	messageLabel.TextTruncate = Enum.TextTruncate.AtEnd
	messageLabel.TextWrapped = true
	messageLabel.Parent = controls

	local compact = false
	local childrenReady = true
	local renderChildren: () -> ()

	renderChildren = function()
		local counts = currentProps.model.cardCounts
		handCountLabel.Text =
			`HAND {counts.hand}/{counts.maxHand or 9}  ·  DRAW {counts.draw}  ·  DISCARD {counts.discard}  ·  ACTIVE {counts.total}`
		phaseHandle.update({
			phase = currentProps.model.phase,
			roundNumber = currentProps.model.roundNumber,
			planningDeadline = currentProps.model.planningDeadline,
			committed = currentProps.model.committed,
			bloodMoon = currentProps.model.bloodMoon,
		})
		energyHandle.update(currentProps.energy)
		initiativeHandle.update({ entries = currentProps.model.initiative, compact = compact })
		battlefieldHandle.update({
			teams = currentProps.model.teams,
			resolveAsset = currentProps.resolveAsset,
			compact = compact,
			selectableTargetIds = currentProps.selectableTargetIds,
			activeCombatantIds = currentProps.activeCombatantIds,
			animationCommandsByCritterId = currentProps.animationCommandsByCritterId,
			onCritterSelected = currentProps.onCritterSelected,
			actingCombatantId = currentProps.playbackState.actingCombatantId,
			targetedCombatantIds = currentProps.playbackState.targetCombatantIds,
			feedbackByCombatantId = currentProps.playbackState.feedbackByCombatantId,
		})
		queueHandle.update({
			entries = currentProps.planningState.queuedCards,
			critters = livingViewerCritters(currentProps.model),
			capacity = currentProps.planningState.maxQueuedCardsPerCritter,
			locked = currentProps.planningState.planningLocked,
			compact = compact,
			onRemove = currentProps.onRemoveCard,
			onReorder = currentProps.onReorderCard,
		})
		queueHandle.instance.Visible = not currentProps.playbackState.active
		combatLogHandle.update({
			active = currentProps.playbackState.active,
			currentActionName = currentProps.playbackState.currentActionName,
			logEntries = currentProps.playbackState.logEntries,
			roundTransition = currentProps.playbackState.roundTransition,
			fastForward = currentProps.playbackState.fastForward,
			onSkip = currentProps.onSkipPlayback,
		})
		handHandle.update({
			cards = currentProps.model.hand,
			planningState = currentProps.planningState,
			resolveAsset = currentProps.resolveAsset,
			onCardSelected = currentProps.onCardSelected,
			compact = compact,
		})
		commitHandle.update({
			committed = currentProps.planningState.committed,
			disabled = currentProps.requestPending
				or not currentProps.model.canRequestCommit
				or currentProps.planningState.committed,
			onActivated = currentProps.onCommit,
			status = if currentProps.model.phase == "RESOLVING"
				then "Resolving — Locked"
				elseif currentProps.model.phase == "FINISHED" then "Battle Finished"
				elseif currentProps.planningState.committed then "Plan Committed — Locked"
				elseif currentProps.requestPending then "Committing..."
				else "Ready — Commit Plan",
		})
		resetHandle.update({
			onActivated = if currentProps.model.matchOutcome ~= nil
				then currentProps.onRestart
				else currentProps.onReset,
			label = if currentProps.model.matchOutcome ~= nil
				then "Restart battle"
				else "Clear Queue",
			disabled = currentProps.requestPending
				or (currentProps.model.matchOutcome == nil and not currentProps.model.canPlan),
		})
		undoHandle.update({
			onActivated = currentProps.onUndo,
			label = "Undo Last Action",
			disabled = currentProps.requestPending
				or not currentProps.model.canPlan
				or #currentProps.planningState.queuedCards == 0,
		})
		messageLabel.Text = currentProps.message or ""
		local outcome = currentProps.model.matchOutcome
		resultOverlay.Visible = outcome ~= nil
		if outcome ~= nil then
			local summary = currentProps.model.resultSummary
			resultText.Text = summary.result
			summaryText.Text =
				`Rounds fought: {summary.roundsFought}\nYour team standing: {summary.allyStanding}/{summary.allyTotal}\nOpponents standing: {summary.enemyStanding}/{summary.enemyTotal}`
		end
	end

	local function applyLayout()
		local viewport = root.AbsoluteSize
		local layout = BattleHudLayout.compute(viewport.X, viewport.Y)
		local nextCompact = layout.compact
		applyRect(content, layout.content)
		root.CanvasSize = UDim2.fromOffset(0, layout.canvasHeight)
		applyRect(header, layout.topHud)
		header.Size = UDim2.fromOffset(layout.topHud.width - 116, layout.topHud.height)
		applyRect(initiativeHost, layout.orderStrip)
		applyRect(battlefieldHost, layout.battlefield)
		applyRect(queueHost, layout.queue)
		applyRect(handHost, layout.hand)
		applyRect(controls, layout.controls)
		local controlsHeight = layout.controls.height
		local messageHeight = 28
		local buttonGap = 5
		local buttonSpace = controlsHeight - messageHeight - buttonGap * 3
		local commitHeight = math.floor(buttonSpace * 0.48)
		local secondaryHeight = math.floor((buttonSpace - commitHeight) / 2)
		messageLabel.Size = UDim2.new(1, 0, 0, messageHeight)
		commitHandle.instance.Position = UDim2.fromOffset(0, messageHeight + buttonGap)
		commitHandle.instance.Size = UDim2.new(1, 0, 0, commitHeight)
		undoHandle.instance.Position =
			UDim2.fromOffset(0, messageHeight + buttonGap * 2 + commitHeight)
		undoHandle.instance.Size = UDim2.new(1, 0, 0, secondaryHeight)
		resetHandle.instance.Position =
			UDim2.fromOffset(0, messageHeight + buttonGap * 3 + commitHeight + secondaryHeight)
		resetHandle.instance.Size = UDim2.new(1, 0, 0, secondaryHeight)
		exitButton.Position = UDim2.new(1, -112, 0, layout.content.y)
		exitButton.Size = UDim2.fromOffset(100, layout.topHud.height)

		if compact ~= nextCompact then
			compact = nextCompact
			if childrenReady then
				renderChildren()
			end
		end
	end

	local sizeConnection = root:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyLayout)

	local function update(nextProps: Props)
		currentProps = nextProps
		applyLayout()
		renderChildren()
	end

	applyLayout()
	update(props)
	return table.freeze({
		instance = screen,
		update = update,
		destroy = function()
			childrenReady = false
			sizeConnection:Disconnect()
			phaseHandle.destroy()
			energyHandle.destroy()
			initiativeHandle.destroy()
			battlefieldHandle.destroy()
			queueHandle.destroy()
			combatLogHandle.destroy()
			handHandle.destroy()
			commitHandle.destroy()
			undoHandle.destroy()
			resetHandle.destroy()
			restartConnection:Disconnect()
			resultMenuConnection:Disconnect()
			exitConnection:Disconnect()
			resultOverlay:Destroy()
			screen:Destroy()
		end,
	})
end

return table.freeze(BattleScreen)
