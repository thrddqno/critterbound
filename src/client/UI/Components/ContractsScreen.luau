--!strict

local Theme = require(script.Parent.Parent.Theme)
local UIFactory = require(script.Parent.UIFactory)
local AssetCatalog = require(script.Parent.Parent.Parent.Assets.AssetCatalog)
local CritterSpriteRig = require(script.Parent.Parent.Parent.Rendering.CritterSpriteRig)

local ContractsScreen = {}

local function card(parent: Instance, height: number, order: number)
	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = Theme.Panel
	frame.BorderColor3 = Theme.Border
	frame.Size = UDim2.new(1, -16, 0, height)
	frame.LayoutOrder = order
	frame.Parent = parent
	return frame
end

local function actionButton(parent: Instance, text: string, position: UDim2)
	local button = UIFactory.button(parent, text)
	button.AnchorPoint = Vector2.new(1, 0)
	button.Position = position
	button.Size = UDim2.fromOffset(168, 40)
	return button
end

function ContractsScreen.mount(parent: Instance, props)
	local screen, root = UIFactory.screen(parent, "CritterboundContracts")
	local title = UIFactory.label(root, "Contracts", 28)
	title.Position = UDim2.fromOffset(18, 12)
	title.Size = UDim2.new(1, -180, 0, 42)
	local back = UIFactory.button(root, "Main Menu")
	back.Position = UDim2.new(1, -154, 0, 10)
	back.Size = UDim2.fromOffset(136, 44)

	local panel = Instance.new("ScrollingFrame")
	panel.BackgroundColor3 = Theme.PanelAlt
	panel.BorderColor3 = Theme.Border
	panel.Position = UDim2.fromOffset(18, 66)
	panel.Size = UDim2.new(1, -36, 1, -84)
	panel.AutomaticCanvasSize = Enum.AutomaticSize.Y
	panel.CanvasSize = UDim2.new()
	panel.ScrollBarThickness = 6
	panel.Parent = root
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.Parent = panel
	local layout = UIFactory.list(panel, 10)

	local connections = {
		back.Activated:Connect(props.onBack),
	}
	local sprites = {}
	local destroyed = false
	local localPending = false
	local render: () -> ()

	local function setPending(pending: boolean)
		localPending = pending
		for _, connection in connections do
			connection:Disconnect()
		end
		table.clear(connections)
		table.insert(connections, back.Activated:Connect(props.onBack))
		render()
	end

	local order = 0

	local function addReward()
		if props.reward == nil then
			return
		end
		order += 1
		local frame = card(panel, 210, order)
		frame.BackgroundColor3 = Theme.Panel
		local heading = UIFactory.label(frame, "Reward claimed", 20)
		heading.Position = UDim2.fromOffset(12, 8)
		heading.Size = UDim2.new(1, -24, 0, 26)
		local artHost = Instance.new("Frame")
		artHost.BackgroundColor3 = Theme.PanelAlt
		artHost.BorderColor3 = Theme.Border
		artHost.Position = UDim2.fromOffset(12, 40)
		artHost.Size = UDim2.fromOffset(150, 150)
		artHost.Parent = frame
		table.insert(
			sprites,
			CritterSpriteRig.mount(artHost, {
				className = props.reward.critter.class,
				appearanceGenome = props.reward.critter.appearanceGenome,
				facing = "RIGHT",
				resolveAsset = function(id)
					return AssetCatalog:resolve(id)
				end,
				size = UDim2.fromOffset(140, 140),
			})
		)
		local detail = UIFactory.label(frame, "", 15)
		detail.RichText = true
		detail.Position = UDim2.fromOffset(174, 40)
		detail.Size = UDim2.new(1, -186, 0, 120)
		detail.Text = table.concat({
			`<b>{props.reward.critter.displayName} - {props.reward.critter.class}</b>`,
			props.reward.critter.statsText,
			props.reward.critter.acquisitionText,
			if props.reward.duplicate
				then "This reward was already claimed; showing the original Critter."
				else "This Critter is now in your Collection.",
		}, "\n")
		local view = UIFactory.button(frame, "View in Collection")
		view.Position = UDim2.fromOffset(174, 162)
		view.Size = UDim2.fromOffset(190, 34)
		table.insert(
			connections,
			view.Activated:Connect(function()
				if not localPending then
					props.onViewCollection(props.reward.critter.id)
				end
			end)
		)
	end

	local function addAvailable(definition)
		order += 1
		local frame = card(panel, 116, order)
		local name = UIFactory.label(frame, definition.displayName, 18)
		name.Position = UDim2.fromOffset(12, 8)
		name.Size = UDim2.new(1, -196, 0, 24)
		local description = UIFactory.label(frame, definition.description, 14)
		description.TextColor3 = Theme.MutedText
		description.Position = UDim2.fromOffset(12, 34)
		description.Size = UDim2.new(1, -196, 0, 36)
		local progress =
			UIFactory.label(frame, `{definition.progressText}  |  {definition.rewardText}`, 13)
		progress.TextColor3 = Theme.MutedText
		progress.Position = UDim2.fromOffset(12, 72)
		progress.Size = UDim2.new(1, -196, 0, 30)
		local accept = actionButton(frame, "Accept", UDim2.new(1, -12, 0, 10))
		accept.Active = not props.pending and not localPending
		accept.AutoButtonColor = accept.Active
		accept.BackgroundColor3 = if accept.Active then Theme.Action else Theme.Disabled
		table.insert(
			connections,
			accept.Activated:Connect(function()
				if props.pending or localPending then
					return
				end
				setPending(true)
				props.onAccept(definition.definitionId, definition.definitionVersion)
			end)
		)
	end

	local function addContract(contract)
		order += 1
		local frame = card(panel, 116, order)
		local name = UIFactory.label(frame, contract.displayName, 18)
		name.Position = UDim2.fromOffset(12, 8)
		name.Size = UDim2.new(1, -196, 0, 24)
		local status =
			UIFactory.label(frame, `{contract.statusText}  |  {contract.progressText}`, 14)
		status.TextColor3 = if contract.status == "COMPLETED"
			then Theme.Health
			elseif contract.status == "CLAIMED" then Theme.MutedText
			else Theme.Text
		status.Position = UDim2.fromOffset(12, 36)
		status.Size = UDim2.new(1, -196, 0, 24)
		local reward = UIFactory.label(frame, contract.rewardText, 13)
		reward.TextColor3 = Theme.MutedText
		reward.Position = UDim2.fromOffset(12, 64)
		reward.Size = UDim2.new(1, -196, 0, 24)
		local detail = UIFactory.label(frame, contract.id, 12)
		detail.TextColor3 = Theme.MutedText
		detail.Position = UDim2.fromOffset(12, 88)
		detail.Size = UDim2.new(1, -196, 0, 20)
		if contract.canClaim then
			local claim = actionButton(frame, "Claim Reward", UDim2.new(1, -12, 0, 10))
			claim.Active = not props.pending and not localPending
			claim.AutoButtonColor = claim.Active
			claim.BackgroundColor3 = if claim.Active then Theme.Action else Theme.Disabled
			table.insert(
				connections,
				claim.Activated:Connect(function()
					if props.pending or localPending then
						return
					end
					setPending(true)
					props.onClaim(contract.id)
				end)
			)
		end
	end

	local statusLabel = nil

	render = function()
		if destroyed then
			return
		end
		for _, sprite in sprites do
			sprite.destroy()
		end
		table.clear(sprites)
		for _, child in panel:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		order = 0
		addReward()
		for _, definition in props.availableDefinitions or {} do
			addAvailable(definition)
		end
		for _, contract in props.contracts or {} do
			addContract(contract)
		end
		if statusLabel == nil or statusLabel.Parent == nil then
			order += 1
			statusLabel = UIFactory.label(panel, "", 15)
			statusLabel.AutomaticSize = Enum.AutomaticSize.Y
			statusLabel.Size = UDim2.new(1, -16, 0, 0)
			statusLabel.LayoutOrder = order
			if props.message ~= nil and props.message ~= "" then
				statusLabel.TextColor3 = Theme.Error
			else
				statusLabel.TextColor3 = Theme.MutedText
			end
		end
		order += 1
		statusLabel.LayoutOrder = order
		statusLabel.Text = props.message
			or if #(props.contracts or {}) == 0
					and #(props.availableDefinitions or {}) == 0
				then "No contracts are available."
				else "Win a Training Grounds battle, then claim your reward."
	end

	table.insert(
		connections,
		layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
			panel.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y)
		end)
	)

	render()

	return table.freeze({
		update = function() end,
		destroy = function()
			destroyed = true
			for _, connection in connections do
				connection:Disconnect()
			end
			for _, sprite in sprites do
				sprite.destroy()
			end
			screen:Destroy()
		end,
	})
end

return table.freeze(ContractsScreen)
