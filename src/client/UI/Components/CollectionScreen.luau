--!strict

local Theme = require(script.Parent.Parent.Theme)
local UIFactory = require(script.Parent.UIFactory)
local CritterDetail = require(script.Parent.CritterDetail)
local CollectionScreen = {}

function CollectionScreen.mount(parent: Instance, props)
	local screen, root = UIFactory.screen(parent, "CritterboundCollection")
	local title = UIFactory.label(root, "Collection", 28)
	title.Position = UDim2.fromOffset(18, 12)
	title.Size = UDim2.new(1, -180, 0, 42)
	local back = UIFactory.button(root, "Main Menu")
	back.Position = UDim2.new(1, -154, 0, 10)
	back.Size = UDim2.fromOffset(136, 44)
	local list = Instance.new("ScrollingFrame")
	list.BackgroundColor3 = Theme.Panel
	list.BorderColor3 = Theme.Border
	list.Position = UDim2.fromOffset(18, 66)
	list.Size = UDim2.new(0.38, -24, 1, -84)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ScrollBarThickness = 6
	list.Parent = root
	local layout = UIFactory.list(list, 6)
	local detailHost = Instance.new("ScrollingFrame")
	detailHost.BackgroundColor3 = Theme.Panel
	detailHost.BorderColor3 = Theme.Border
	detailHost.AutomaticCanvasSize = Enum.AutomaticSize.Y
	detailHost.CanvasSize = UDim2.new()
	detailHost.ScrollBarThickness = 6
	detailHost.Position = UDim2.new(0.38, 6, 0, 66)
	detailHost.Size = UDim2.new(0.62, -24, 1, -84)
	detailHost.Parent = root
	local detailPadding = Instance.new("UIPadding")
	detailPadding.PaddingTop = UDim.new(0, 12)
	detailPadding.PaddingLeft = UDim.new(0, 12)
	detailPadding.PaddingRight = UDim.new(0, 12)
	detailPadding.PaddingBottom = UDim.new(0, 12)
	detailPadding.Parent = detailHost
	local connections = { back.Activated:Connect(props.onBack) }
	local selected = props.collection.critters[1]
	local detail = nil
	local empty = UIFactory.label(detailHost, "Collection is empty.", 18)
	empty.Size = UDim2.fromScale(1, 1)
	empty.Visible = selected == nil
	local function selectCritter(critter)
		selected = critter
		empty.Visible = false
		if detail == nil then
			detail = CritterDetail.mount(detailHost, { critter = critter })
		else
			detail.update({ critter = critter })
		end
	end
	for index, critter in props.collection.critters do
		local marker = if critter.selectedTeamSlot == nil
			then ""
			else ` [TEAM {critter.selectedTeamSlot}]`
		local button = UIFactory.button(list, `{critter.displayName} — {critter.class}{marker}`)
		button.LayoutOrder = index
		button.Size = UDim2.new(1, -8, 0, 52)
		button.BackgroundColor3 = Theme.PanelAlt
		table.insert(
			connections,
			button.Activated:Connect(function()
				selectCritter(critter)
			end)
		)
	end
	table.insert(
		connections,
		layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
			list.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y)
		end)
	)
	if selected ~= nil then
		selectCritter(selected)
	end
	return table.freeze({
		update = function() end,
		destroy = function()
			for _, connection in connections do
				connection:Disconnect()
			end
			if detail ~= nil then
				detail.destroy()
			end
			screen:Destroy()
		end,
	})
end

return table.freeze(CollectionScreen)
