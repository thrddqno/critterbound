--!strict

local Theme = require(script.Parent.Parent.Theme)
local UIFactory = require(script.Parent.UIFactory)
local EquipmentPanel = {}

function EquipmentPanel.mount(parent: Instance, props)
	local root = Instance.new("Frame")
	root.BackgroundColor3 = Theme.Panel
	root.BorderColor3 = Theme.Border
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = parent
	local title = UIFactory.label(root, "Select an item", 22)
	title.Position = UDim2.fromOffset(12, 10)
	title.Size = UDim2.new(1, -24, 0, 34)
	local detail = UIFactory.label(root, "", 15)
	detail.Position = UDim2.fromOffset(12, 50)
	detail.Size = UDim2.new(1, -24, 0, 118)
	local actionHost = Instance.new("ScrollingFrame")
	actionHost.BackgroundTransparency = 1
	actionHost.Position = UDim2.fromOffset(12, 172)
	actionHost.Size = UDim2.new(1, -24, 1, -184)
	actionHost.AutomaticCanvasSize = Enum.AutomaticSize.Y
	actionHost.CanvasSize = UDim2.new()
	actionHost.ScrollBarThickness = 5
	actionHost.Parent = root
	UIFactory.list(actionHost, 6)
	local connections = {}
	local current = props
	local function clearActions()
		for _, connection in connections do
			connection:Disconnect()
		end
		table.clear(connections)
		for _, child in actionHost:GetChildren() do
			if child:IsA("GuiButton") then
				child:Destroy()
			end
		end
	end
	local function update(nextProps)
		current = nextProps
		clearActions()
		local item = current.item
		if item == nil then
			title.Text = "Select an item"
			detail.Text = "Choose stackable material or unique equipment from inventory."
			return
		end
		title.Text = `{item.displayName} — {item.rarity}`
		detail.Text = table.concat({
			item.description,
			`Category: {item.category}`,
			if item.quantity ~= nil
				then `Quantity: {item.quantity}`
				else `Instance: {item.instanceId}`,
			if item.equippedCritterId ~= nil then "Status: Equipped" else "Status: Available",
		}, "\n")
		if item.category ~= "EQUIPMENT" then
			return
		end
		if item.equippedCritterId ~= nil then
			local button = UIFactory.button(actionHost, "Unequip")
			button.Size = UDim2.new(1, -6, 0, 48)
			button.Active = not current.pending
			table.insert(
				connections,
				button.Activated:Connect(function()
					if not current.pending then
						current.onUnequip(item.equippedCritterId)
					end
				end)
			)
			return
		end
		for _, critter in current.collection.critters do
			local button = UIFactory.button(actionHost, `Equip to {critter.displayName}`)
			button.Size = UDim2.new(1, -6, 0, 48)
			button.Active = not current.pending
			table.insert(
				connections,
				button.Activated:Connect(function()
					if not current.pending then
						current.onEquip(critter.id, item.instanceId)
					end
				end)
			)
		end
	end
	update(props)
	return table.freeze({
		update = update,
		destroy = function()
			clearActions()
			root:Destroy()
		end,
	})
end

return table.freeze(EquipmentPanel)
