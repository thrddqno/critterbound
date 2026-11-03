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
	animationCommandsByCritterId: { [string]: any }?,
	onCritterSelected: ((string) -> ())?,
}

function BattlefieldView.mount(parent: Instance, props: Props)
	local root = Instance.new("Frame")
	root.Name = "BattlefieldView"
	root.BackgroundColor3 = Theme.Background
	root.BorderSizePixel = 0
	root.Parent = parent

	local handles = {}
	local handleTeamIds = {}
	local rows = {}

	local function clear()
		for _, handle in handles do
			handle.destroy()
		end
		table.clear(handles)
		table.clear(handleTeamIds)
		for _, row in rows do
			row.frame:Destroy()
		end
		table.clear(rows)
	end

	local function update(nextProps: Props)
		local selectable = {}
		for _, id in nextProps.selectableTargetIds or {} do
			selectable[id] = true
		end
		local active = {}
		for _, id in nextProps.activeCombatantIds or {} do
			active[id] = true
		end
		local usedTeams = {}
		local usedCritters = {}
		for teamIndex, team in nextProps.teams do
			usedTeams[team.id] = true
			local labelWidth = if nextProps.compact then 84 else 108
			local row = rows[team.id]
			if row == nil then
				local frame = Instance.new("Frame")
				frame.BorderSizePixel = 1
				frame.Parent = root
				local label = Instance.new("TextLabel")
				label.Name = "TeamLabel"
				label.BorderSizePixel = 0
				label.TextColor3 = Theme.Text
				label.TextWrapped = true
				label.Parent = frame
				local host = Instance.new("Frame")
				host.Name = "Critters"
				host.BackgroundTransparency = 1
				host.Parent = frame
				local layout = Instance.new("UIListLayout")
				layout.FillDirection = Enum.FillDirection.Horizontal
				layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
				layout.Padding = UDim.new(0.01, 0)
				layout.SortOrder = Enum.SortOrder.LayoutOrder
				layout.Parent = host
				row = { frame = frame, label = label, host = host }
				rows[team.id] = row
			end
			row.frame.Name = if team.side == "ALLY" then "PlayerTeam" else "EnemyTeam"
			row.frame.BackgroundColor3 = Theme.Panel
			row.frame.BorderColor3 = if team.side == "ALLY" then Theme.Ally else Theme.Enemy
			row.frame.Size = UDim2.new(1, 0, 0.5, -3)
			row.frame.Position =
				UDim2.new(0, 0, (teamIndex - 1) * 0.5, if teamIndex == 1 then 0 else 3)
			row.label.BackgroundColor3 = if team.side == "ALLY" then Theme.Ally else Theme.Enemy
			row.label.Size = UDim2.new(0, labelWidth, 1, 0)
			row.label.Text = `{if team.side == "ALLY" then "PLAYER" else "ENEMY"}\nTEAM\n{team.id}`
			row.label.TextSize = if nextProps.compact then 11 else 13
			row.host.Position = UDim2.fromOffset(labelWidth + 4, 3)
			row.host.Size = UDim2.new(1, -labelWidth - 7, 1, -6)

			for _, critter in team.critters do
				usedCritters[critter.id] = true
				local critterProps = {
					critter = critter,
					resolveAsset = nextProps.resolveAsset,
					side = team.side,
					compact = nextProps.compact,
					selectable = selectable[critter.id] == true,
					highlighted = active[critter.id] == true,
					onActivated = nextProps.onCritterSelected,
					animationCommand = (nextProps.animationCommandsByCritterId or {})[critter.id],
				}
				local handle = handles[critter.id]
				if handle == nil or handleTeamIds[critter.id] ~= team.id then
					if handle ~= nil then
						handle.destroy()
					end
					handle = CritterView.mount(row.host, critterProps)
					handles[critter.id] = handle
					handleTeamIds[critter.id] = team.id
				else
					handle.update(critterProps)
				end
				handle.instance.LayoutOrder = critter.slot
			end
		end
		for id, handle in handles do
			if not usedCritters[id] then
				handle.destroy()
				handles[id] = nil
				handleTeamIds[id] = nil
			end
		end
		for id, row in rows do
			if not usedTeams[id] then
				row.frame:Destroy()
				rows[id] = nil
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
