--!strict

local Theme = require(script.Parent.Parent.Theme)
local BattlePhaseIndicator = {}

export type Props = { phase: string, roundNumber: number }

function BattlePhaseIndicator.mount(parent: Instance, props: Props)
	local label = Instance.new("TextLabel")
	label.Name = "BattlePhaseIndicator"
	label.BackgroundColor3 = Theme.Panel
	label.TextColor3 = Theme.Text
	label.TextSize = 18
	label.Parent = parent
	local function update(nextProps: Props)
		label.Text = `Round {nextProps.roundNumber} | {nextProps.phase}`
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

return table.freeze(BattlePhaseIndicator)
