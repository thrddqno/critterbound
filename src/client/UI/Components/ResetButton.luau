--!strict

local Theme = require(script.Parent.Parent.Theme)
local ResetButton = {}

export type Props = { onActivated: () -> () }

function ResetButton.mount(parent: Instance, props: Props)
	local button = Instance.new("TextButton")
	button.Name = "ResetButton"
	button.BackgroundColor3 = Theme.PanelAlt
	button.TextColor3 = Theme.Text
	button.Text = "Reset mock plan"
	button.TextSize = 14
	button.Parent = parent
	local current = props
	local connection = button.Activated:Connect(function()
		current.onActivated()
	end)
	local function update(nextProps: Props)
		current = nextProps
	end
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
