--!strict

local Theme = require(script.Parent.Parent.Theme)
local ResetButton = {}

export type Props = { onActivated: () -> (), label: string?, disabled: boolean? }

function ResetButton.mount(parent: Instance, props: Props)
	local button = Instance.new("TextButton")
	button.Name = "ResetButton"
	button.BackgroundColor3 = Theme.PanelAlt
	button.TextColor3 = Theme.Text
	button.Text = props.label or "Clear plan"
	button.TextSize = 14
	button.Parent = parent
	local current = props
	local connection = button.Activated:Connect(function()
		if not current.disabled then
			current.onActivated()
		end
	end)
	local function update(nextProps: Props)
		current = nextProps
		button.Text = nextProps.label or "Clear plan"
		button.Active = not nextProps.disabled
		button.AutoButtonColor = not nextProps.disabled
		button.BackgroundColor3 = if nextProps.disabled then Theme.Disabled else Theme.PanelAlt
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

return table.freeze(ResetButton)
