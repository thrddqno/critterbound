--!strict

local Theme = require(script.Parent.Parent.Theme)
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local BattleHudPresentation =
	require(script.Parent.Parent.Parent.Presentation.BattleHudPresentation)
local BattlePhaseIndicator = {}

export type Props = {
	phase: string,
	roundNumber: number,
	planningDeadline: number?,
	committed: boolean,
	bloodMoon: any?,
}

function BattlePhaseIndicator.mount(parent: Instance, props: Props)
	local label = Instance.new("TextLabel")
	label.Name = "BattlePhaseIndicator"
	label.BackgroundColor3 = Theme.Panel
	label.TextColor3 = Theme.Text
	label.TextSize = 14
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = parent
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 12)
	padding.Parent = label
	local currentProps = props
	local function render()
		label.Text = BattleHudPresentation.state(currentProps, Workspace:GetServerTimeNow()).text
	end
	local function update(nextProps: Props)
		currentProps = nextProps
		render()
	end
	update(props)
	local renderConnection = RunService.RenderStepped:Connect(render)
	return table.freeze({
		instance = label,
		update = update,
		destroy = function()
			renderConnection:Disconnect()
			label:Destroy()
		end,
	})
end

return table.freeze(BattlePhaseIndicator)
