--!strict

local Theme = require(script.Parent.Parent.Theme)

local UIFactory = {}

function UIFactory.screen(parent: Instance, name: string)
	local screen = Instance.new("ScreenGui")
	screen.Name = name
	screen.ResetOnSpawn = false
	screen.Parent = parent
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundColor3 = Theme.Background
	root.BorderSizePixel = 0
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = screen
	return screen, root
end

function UIFactory.label(parent: Instance, text: string, size: number?)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = Theme.Text
	label.TextSize = size or 16
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.Parent = parent
	return label
end

function UIFactory.button(parent: Instance, text: string)
	local button = Instance.new("TextButton")
	button.BackgroundColor3 = Theme.Action
	button.BorderColor3 = Theme.Border
	button.Text = text
	button.TextColor3 = Theme.Text
	button.TextSize = 16
	button.TextWrapped = true
	button.Parent = parent
	return button
end

function UIFactory.list(parent: Instance, padding: number?)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, padding or 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = parent
	return layout
end

return table.freeze(UIFactory)
