--!strict

local Theme = require(script.Parent.Parent.Theme)
local EnergyCounter = {}

export type Props = { available: number, allocated: number, remaining: number }

function EnergyCounter.mount(parent: Instance, props: Props)
	local label = Instance.new("TextLabel")
	label.Name = "EnergyCounter"
	label.BackgroundColor3 = Theme.Panel
	label.TextColor3 = Theme.Text
	label.TextSize = 16
	label.Parent = parent
	local function update(nextProps: Props)
		label.Text =
			`Energy {nextProps.remaining}/{nextProps.available} | Allocated {nextProps.allocated}`
		label.TextColor3 = if nextProps.remaining < 0 then Theme.Error else Theme.Text
	end
	update(props)
	return table.freeze({
		instance = label,
		update = update,
		destroy = function()
			label:Destroy()
		end,
	})
end

return table.freeze(EnergyCounter)
