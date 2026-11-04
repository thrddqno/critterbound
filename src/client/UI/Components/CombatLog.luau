--!strict

local Theme = require(script.Parent.Parent.Theme)

local CombatLog = {}

export type Props = {
	active: boolean,
	currentActionName: string?,
	logEntries: { any },
	roundTransition: boolean?,
	fastForward: boolean?,
	onSkip: () -> (),
}

function CombatLog.mount(parent: Instance, props: Props)
	local root = Instance.new("Frame")
	root.Name = "CombatLog"
	root.BackgroundColor3 = Theme.Panel
	root.BorderColor3 = Theme.Action
	root.BorderSizePixel = 2
	root.Parent = parent

	local action = Instance.new("TextLabel")
	action.Name = "CurrentAction"
	action.BackgroundColor3 = Theme.PanelAlt
	action.Position = UDim2.fromOffset(4, 4)
	action.Size = UDim2.new(1, -132, 0, 24)
	action.TextColor3 = Theme.Text
	action.TextSize = 14
	action.TextTruncate = Enum.TextTruncate.AtEnd
	action.TextXAlignment = Enum.TextXAlignment.Left
	action.Parent = root

	local entries = Instance.new("TextLabel")
	entries.Name = "ChronologicalEntries"
	entries.BackgroundTransparency = 1
	entries.Position = UDim2.fromOffset(6, 31)
	entries.Size = UDim2.new(1, -136, 1, -35)
	entries.TextColor3 = Theme.MutedText
	entries.TextSize = 10
	entries.TextWrapped = true
	entries.TextXAlignment = Enum.TextXAlignment.Left
	entries.TextYAlignment = Enum.TextYAlignment.Top
	entries.Parent = root

	local skip = Instance.new("TextButton")
	skip.Name = "SkipPresentation"
	skip.BackgroundColor3 = Theme.Action
	skip.Position = UDim2.new(1, -124, 0, 4)
	skip.Size = UDim2.new(0, 120, 1, -8)
	skip.TextColor3 = Theme.Text
	skip.TextSize = 13
	skip.TextWrapped = true
	skip.Parent = root

	local currentProps = props
	local connection = skip.Activated:Connect(function()
		if currentProps.active and not currentProps.fastForward then
			currentProps.onSkip()
		end
	end)

	local function update(nextProps: Props)
		currentProps = nextProps
		root.Visible = nextProps.active
		root.BorderColor3 = if nextProps.roundTransition then Theme.Health else Theme.Action
		action.Text = if nextProps.roundTransition
			then `  {nextProps.currentActionName or "Round complete"}`
			else `  Resolving: {nextProps.currentActionName or "..."}`
		local lines = {}
		local first = math.max(1, #nextProps.logEntries - 3)
		for index = first, #nextProps.logEntries do
			local entry = nextProps.logEntries[index]
			table.insert(lines, `#{entry.sequence} {entry.text}`)
		end
		entries.Text = table.concat(lines, "\n")
		skip.Text = if nextProps.fastForward then "Fast-forwarding..." else "Skip Presentation"
		skip.Active = nextProps.active and not nextProps.fastForward
		skip.AutoButtonColor = skip.Active
		skip.BackgroundColor3 = if skip.Active then Theme.Action else Theme.Disabled
	end

	update(props)
	return table.freeze({
		instance = root,
		update = update,
		destroy = function()
			connection:Disconnect()
			root:Destroy()
		end,
	})
end

return table.freeze(CombatLog)
