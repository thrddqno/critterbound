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

local BattleScreen = {}

export type Props = {
	model: any,
	planningState: any,
	energy: any,
	resolveAsset: (string) -> any,
	onCardSelected: (any) -> (),
	onRemoveCard: (string) -> (),
	onCommit: () -> (),
	onReset: () -> (),
	message: string?,
}

function BattleScreen.mount(parent: Instance, props: Props)
	local screen = Instance.new("ScreenGui")
	screen.Name = "CritterboundBattleScreen"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = false
	screen.Parent = parent

	local root = Instance.new("ScrollingFrame")
	root.Name = "Root"
	root.BackgroundColor3 = Theme.Background
	root.BorderSizePixel = 0
	root.CanvasSize = UDim2.fromOffset(0, 0)
	root.ScrollBarThickness = 6
	root.ScrollingDirection = Enum.ScrollingDirection.Y
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = screen

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Position = UDim2.fromOffset(8, 8)
	content.Parent = root

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundTransparency = 1
	header.Parent = content

	local phaseHost = Instance.new("Frame")
	phaseHost.BackgroundTransparency = 1
	phaseHost.Size = UDim2.fromScale(0.5, 1)
	phaseHost.Parent = header
	local energyHost = Instance.new("Frame")
	energyHost.BackgroundTransparency = 1
	energyHost.Position = UDim2.fromScale(0.5, 0)
	energyHost.Size = UDim2.fromScale(0.5, 1)
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
	controls.BackgroundTransparency = 1
	controls.Parent = content

	local phaseHandle = BattlePhaseIndicator.mount(
		phaseHost,
		{ phase = props.model.phase, roundNumber = props.model.roundNumber }
	)
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
		critters = props.model.critters,
		locked = props.planningState.committed,
		compact = false,
		onRemove = props.onRemoveCard,
	})
	queueHandle.instance.Size = UDim2.fromScale(1, 1)
	local handHandle = CardHand.mount(handHost, {
		cards = props.model.hand,
		planningState = props.planningState,
		resolveAsset = props.resolveAsset,
		onCardSelected = props.onCardSelected,
		compact = false,
	})
	handHandle.instance.Size = UDim2.fromScale(1, 1)
	local commitHandle = CommitButton.mount(controls, {
		committed = props.planningState.committed,
		disabled = not props.model.canRequestCommit or props.planningState.committed,
		onActivated = props.onCommit,
	})
	local resetHandle = ResetButton.mount(controls, { onActivated = props.onReset })

	local messageLabel = Instance.new("TextLabel")
	messageLabel.Name = "LocalPlanningMessage"
	messageLabel.BackgroundColor3 = Theme.Panel
	messageLabel.BorderSizePixel = 0
	messageLabel.TextColor3 = Theme.Error
	messageLabel.TextSize = 11
	messageLabel.TextTruncate = Enum.TextTruncate.AtEnd
	messageLabel.TextWrapped = true
	messageLabel.Parent = controls

	local currentProps = props
	local compact = false
	local childrenReady = true
	local renderChildren: () -> ()

	renderChildren = function()
		phaseHandle.update({
			phase = currentProps.model.phase,
			roundNumber = currentProps.model.roundNumber,
		})
		energyHandle.update(currentProps.energy)
		initiativeHandle.update({ entries = currentProps.model.initiative, compact = compact })
		battlefieldHandle.update({
			teams = currentProps.model.teams,
			resolveAsset = currentProps.resolveAsset,
			compact = compact,
		})
		queueHandle.update({
			entries = currentProps.planningState.queuedCards,
			critters = currentProps.model.critters,
			locked = currentProps.planningState.committed,
			compact = compact,
			onRemove = currentProps.onRemoveCard,
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
			disabled = not currentProps.model.canRequestCommit
				or currentProps.planningState.committed,
			onActivated = currentProps.onCommit,
		})
		resetHandle.update({ onActivated = currentProps.onReset })
		messageLabel.Text = currentProps.message or ""
	end

	local function applyLayout()
		local viewport = root.AbsoluteSize
		local nextCompact = viewport.X < 1000 or viewport.Y < 650
		local contentHeight = math.max(viewport.Y - 16, 620)
		local contentWidth = math.max(viewport.X - 22, 600)
		local headerHeight = if nextCompact then 44 else 52
		local initiativeHeight = if nextCompact then 64 else 72
		local handHeight = if nextCompact then 162 else 190
		local queueHeight = if #currentProps.planningState.queuedCards == 0
			then 36
			elseif nextCompact then 94
			else 108
		local gap = 6
		local initiativeY = headerHeight + gap
		local battlefieldY = initiativeY + initiativeHeight + gap
		local handY = contentHeight - handHeight
		local queueY = handY - gap - queueHeight
		local battlefieldHeight = math.max(190, queueY - gap - battlefieldY)
		local controlsWidth =
			math.min(if nextCompact then 172 else 250, math.floor(contentWidth * 0.3))

		content.Size = UDim2.new(1, -16, 0, contentHeight)
		root.CanvasSize = UDim2.fromOffset(0, contentHeight + 16)
		header.Position = UDim2.fromOffset(0, 0)
		header.Size = UDim2.new(1, 0, 0, headerHeight)
		initiativeHost.Position = UDim2.fromOffset(0, initiativeY)
		initiativeHost.Size = UDim2.new(1, 0, 0, initiativeHeight)
		battlefieldHost.Position = UDim2.fromOffset(0, battlefieldY)
		battlefieldHost.Size = UDim2.new(1, 0, 0, battlefieldHeight)
		queueHost.Position = UDim2.fromOffset(0, queueY)
		queueHost.Size = UDim2.new(1, 0, 0, queueHeight)
		handHost.Position = UDim2.fromOffset(0, handY)
		handHost.Size = UDim2.new(1, -controlsWidth - gap, 0, handHeight)
		controls.Position = UDim2.new(1, -controlsWidth, 0, handY)
		controls.Size = UDim2.fromOffset(controlsWidth, handHeight)
		messageLabel.Size = UDim2.new(1, 0, 0, 30)
		commitHandle.instance.Position = UDim2.fromOffset(0, 34)
		commitHandle.instance.Size = UDim2.new(1, 0, 0.5, -20)
		resetHandle.instance.Position = UDim2.new(0, 0, 0.5, 18)
		resetHandle.instance.Size = UDim2.new(1, 0, 0.5, -18)

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
			handHandle.destroy()
			commitHandle.destroy()
			resetHandle.destroy()
			screen:Destroy()
		end,
	})
end

return table.freeze(BattleScreen)
