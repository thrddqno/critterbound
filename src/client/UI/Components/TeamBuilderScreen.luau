--!strict

local Theme = require(script.Parent.Parent.Theme)
local UIFactory = require(script.Parent.UIFactory)
local TeamBuilderScreen = {}

function TeamBuilderScreen.mount(parent: Instance, props)
	local screen, root = UIFactory.screen(parent, "CritterboundTeamBuilder")
	local title = UIFactory.label(root, "Team Builder", 28)
	title.Position = UDim2.fromOffset(18, 12)
	title.Size = UDim2.new(1, -180, 0, 42)
	local back = UIFactory.button(root, "Main Menu")
	back.Position = UDim2.new(1, -154, 0, 10)
	back.Size = UDim2.fromOffset(136, 44)
	local slots = Instance.new("Frame")
	slots.BackgroundColor3 = Theme.Panel
	slots.Position = UDim2.fromOffset(18, 66)
	slots.Size = UDim2.new(1, -36, 0, 72)
	slots.Parent = root
	local slotLayout = Instance.new("UIListLayout")
	slotLayout.FillDirection = Enum.FillDirection.Horizontal
	slotLayout.Padding = UDim.new(0, 8)
	slotLayout.Parent = slots
	local slotLabels = {}
	for index = 1, 3 do
		local label = UIFactory.label(slots, `Slot {index}: Empty`, 16)
		label.BackgroundColor3 = Theme.PanelAlt
		label.BackgroundTransparency = 0
		label.Size = UDim2.new(1 / 3, -6, 1, 0)
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.TextYAlignment = Enum.TextYAlignment.Center
		slotLabels[index] = label
	end
	local list = Instance.new("ScrollingFrame")
	list.BackgroundColor3 = Theme.Panel
	list.Position = UDim2.fromOffset(18, 150)
	list.Size = UDim2.new(1, -36, 1, -232)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ScrollBarThickness = 6
	list.Parent = root
	UIFactory.list(list, 6)
	local save = UIFactory.button(root, "Save Team")
	save.Position = UDim2.new(1, -198, 1, -68)
	save.Size = UDim2.fromOffset(180, 50)
	local status =
		UIFactory.label(root, props.message or "Select exactly three distinct Critters.", 15)
	status.Position = UDim2.new(0, 18, 1, -65)
	status.Size = UDim2.new(1, -226, 0, 48)
	local byId = {}
	for _, critter in props.collection.critters do
		byId[critter.id] = critter
	end
	local draft = table.clone(props.collection.selectedTeam)
	local connections = { back.Activated:Connect(props.onBack) }
	local buttons = {}

	local function render()
		for index = 1, 3 do
			local critter = byId[draft[index]]
			slotLabels[index].Text = if critter == nil
				then `Slot {index}: Empty`
				else `Slot {index}: {critter.displayName}`
		end
		for critterId, button in buttons do
			local selected = table.find(draft, critterId) ~= nil
			button.BackgroundColor3 = if selected then Theme.Ally else Theme.PanelAlt
		end
		save.Active = #draft == 3 and not props.pending
		save.AutoButtonColor = save.Active
	end

	for index, critter in props.collection.critters do
		local button =
			UIFactory.button(list, `{critter.displayName} — {critter.class}\n{critter.statsText}`)
		button.LayoutOrder = index
		button.Size = UDim2.new(1, -8, 0, 60)
		buttons[critter.id] = button
		table.insert(
			connections,
			button.Activated:Connect(function()
				if props.pending then
					return
				end
				local existing = table.find(draft, critter.id)
				if existing ~= nil then
					table.remove(draft, existing)
				elseif #draft < 3 then
					table.insert(draft, critter.id)
				else
					status.Text = "Team already has three Critters. Remove one first."
				end
				render()
			end)
		)
	end
	table.insert(
		connections,
		save.Activated:Connect(function()
			if #draft == 3 and not props.pending then
				props.onSave(table.clone(draft))
			end
		end)
	)
	render()
	return table.freeze({
		update = function() end,
		destroy = function()
			for _, connection in connections do
				connection:Disconnect()
			end
			screen:Destroy()
		end,
	})
end

return table.freeze(TeamBuilderScreen)
