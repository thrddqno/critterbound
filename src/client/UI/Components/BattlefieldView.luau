--!strict

local Theme = require(script.Parent.Parent.Theme)
local CritterView = require(script.Parent.CritterView)

local BattlefieldView = {}

export type Props = {
	teams: { any },
	resolveAsset: (string) -> any,
	compact: boolean?,
	selectableTargetIds: { string }?,
	activeCombatantIds: { string }?,
	onCritterSelected: ((string) -> ())?,
}

function BattlefieldView.mount(parent: Instance, props: Props)
	local root = Instance.new("Frame")
	root.Name = "BattlefieldView"
	root.BackgroundColor3 = Theme.Background
	root.BorderSizePixel = 0
	root.Parent = parent

	local handles = {}
	local rows = {}

	local function clear()
		for _, handle in handles do
			handle.destroy()
		end
		table.clear(handles)
		for _, row in rows do
			row:Destroy()
		end
		table.clear(rows)
	end

	local function update(nextProps: Props)
		clear()
		local selectable = {}
		for _, id in nextProps.selectableTargetIds or {} do
			selectable[id] = true
		end
		local active = {}
		for _, id in nextProps.activeCombatantIds or {} do
			active[id] = true
		end
		for teamIndex, team in nextProps.teams do
			local row = Instance.new("Frame")
			row.Name = if team.side == "ALLY" then "PlayerTeam" else "EnemyTeam"
			row.BackgroundColor3 = Theme.Panel
			row.BorderColor3 = if team.side == "ALLY" then Theme.Ally else Theme.Enemy
			row.BorderSizePixel = 1
			row.Size = UDim2.new(1, 0, 0.5, -3)
			row.Position = UDim2.new(0, 0, (teamIndex - 1) * 0.5, if teamIndex == 1 then 0 else 3)
			row.Parent = root
			table.insert(rows, row)

			local labelWidth = if nextProps.compact then 84 else 108
			local teamLabel = Instance.new("TextLabel")
			teamLabel.Name = "TeamLabel"
			teamLabel.BackgroundColor3 = if team.side == "ALLY" then Theme.Ally else Theme.Enemy
			teamLabel.BorderSizePixel = 0
			teamLabel.Size = UDim2.new(0, labelWidth, 1, 0)
			teamLabel.Text = `{if team.side == "ALLY" then "PLAYER" else "ENEMY"}\nTEAM\n{team.id}`
			teamLabel.TextColor3 = Theme.Text
			teamLabel.TextSize = if nextProps.compact then 11 else 13
			teamLabel.TextWrapped = true
			teamLabel.Parent = row

			local critterHost = Instance.new("Frame")
			critterHost.Name = "Critters"
			critterHost.BackgroundTransparency = 1
			critterHost.Position = UDim2.fromOffset(labelWidth + 4, 3)
			critterHost.Size = UDim2.new(1, -labelWidth - 7, 1, -6)
			critterHost.Parent = row
			local layout = Instance.new("UIListLayout")
			layout.FillDirection = Enum.FillDirection.Horizontal
			layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
			layout.Padding = UDim.new(0.01, 0)
			layout.SortOrder = Enum.SortOrder.LayoutOrder
			layout.Parent = critterHost

			for _, critter in team.critters do
				local handle = CritterView.mount(critterHost, {
					critter = critter,
					asset = nextProps.resolveAsset(critter.assetId),
					side = team.side,
					compact = nextProps.compact,
					selectable = selectable[critter.id] == true,
					highlighted = active[critter.id] == true,
					onActivated = nextProps.onCritterSelected,
				})
				handle.instance.LayoutOrder = critter.slot
				table.insert(handles, handle)
			end
		end
	end

	update(props)
	return table.freeze({
		instance = root,
		update = update,
		destroy = function()
			clear()
			root:Destroy()
		end,
	})
end

return table.freeze(BattlefieldView)
