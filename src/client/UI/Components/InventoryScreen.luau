--!strict

local Theme = require(script.Parent.Parent.Theme)
local UIFactory = require(script.Parent.UIFactory)
local EquipmentPanel = require(script.Parent.EquipmentPanel)
local InventoryScreen = {}

function InventoryScreen.mount(parent: Instance, props)
	local screen, root = UIFactory.screen(parent, "CritterboundInventory")
	local title = UIFactory.label(root, "Inventory", 28)
	title.Position = UDim2.fromOffset(18, 12)
	title.Size = UDim2.new(1, -180, 0, 42)
	local back = UIFactory.button(root, "Main Menu")
	back.Position = UDim2.new(1, -154, 0, 10)
	back.Size = UDim2.fromOffset(136, 44)
	local list = Instance.new("ScrollingFrame")
	list.BackgroundColor3 = Theme.Panel
	list.Position = UDim2.fromOffset(18, 66)
	list.Size = UDim2.new(0.42, -24, 1, -108)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ScrollBarThickness = 6
	list.Parent = root
	UIFactory.list(list, 6)
	local panelHost = Instance.new("Frame")
	panelHost.BackgroundTransparency = 1
	panelHost.Position = UDim2.new(0.42, 6, 0, 66)
	panelHost.Size = UDim2.new(0.58, -24, 1, -108)
	panelHost.Parent = root
	local status = UIFactory.label(root, props.message or "", 14)
	status.Position = UDim2.fromOffset(18, 1)
	status.AnchorPoint = Vector2.new(0, 1)
	status.Position = UDim2.new(0, 18, 1, -8)
	status.Size = UDim2.new(1, -36, 0, 28)
	status.TextColor3 = if props.message == nil then Theme.MutedText else Theme.Error
	local connections = { back.Activated:Connect(props.onBack) }
	local selected = nil
	local panel = EquipmentPanel.mount(panelHost, {
		item = nil,
		collection = props.collection,
		pending = props.pending,
		onEquip = props.onEquip,
		onUnequip = props.onUnequip,
	})
	local items = {}
	for _, stack in props.inventory.stacks do
		local item = table.clone(stack)
		item.quantity = stack.quantity
		table.insert(items, item)
	end
	for _, item in props.inventory.uniqueItems do
		table.insert(items, item)
	end
	if #items == 0 then
		local empty = UIFactory.label(list, "Inventory is empty.", 18)
		empty.Size = UDim2.new(1, -8, 0, 60)
	end
	for index, item in items do
		local suffix = if item.quantity ~= nil
			then ` x{item.quantity}`
			elseif item.equippedCritterId ~= nil then " [EQUIPPED]"
			else " [AVAILABLE]"
		local button =
			UIFactory.button(list, `{item.displayName}{suffix}\n{item.rarity} {item.category}`)
		button.LayoutOrder = index
		button.BackgroundColor3 = Theme.PanelAlt
		button.Size = UDim2.new(1, -8, 0, 62)
		table.insert(
			connections,
			button.Activated:Connect(function()
				selected = item
				panel.update({
					item = selected,
					collection = props.collection,
					pending = props.pending,
					onEquip = props.onEquip,
					onUnequip = props.onUnequip,
				})
			end)
		)
	end
	return table.freeze({
		update = function() end,
		destroy = function()
			for _, connection in connections do
				connection:Disconnect()
			end
			panel.destroy()
			screen:Destroy()
		end,
	})
end

return table.freeze(InventoryScreen)
