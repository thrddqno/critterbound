--!strict

local Theme = require(script.Parent.Parent.Theme)
local CommitButton = {}

export type Props = {
	committed: boolean,
	disabled: boolean,
	status: string?,
	onActivated: () -> (),
}

function CommitButton.mount(parent: Instance, props: Props)
	local button = Instance.new("TextButton")
	button.Name = "CommitButton"
	button.TextColor3 = Theme.Text
	button.TextSize = 16
	button.Parent = parent
	local currentProps = props
	local connection = button.Activated:Connect(function()
		if not currentProps.disabled then
			currentProps.onActivated()
		end
	end)
	local function update(nextProps: Props)
		currentProps = nextProps
		button.Text = nextProps.status
			or if nextProps.committed then "Plan Committed" else "Commit Plan"
		button.BackgroundColor3 = if nextProps.disabled then Theme.Disabled else Theme.Action
		button.Active = not nextProps.disabled
	end
	update(props)
	return table.freeze({
		instance = button,
		update = update,
		destroy = function()
			connection:Disconnect()
			button:Destroy()
		end,
	})
end

return table.freeze(CommitButton)
