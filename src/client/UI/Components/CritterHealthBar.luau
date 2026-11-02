--!strict

local Theme = require(script.Parent.Parent.Theme)

local CritterHealthBar = {}

export type Props = { health: number, maxHealth: number, shield: number }

function CritterHealthBar.mount(parent: Instance, props: Props)
	local root = Instance.new("Frame")
	root.Name = "CritterHealthBar"
	root.BackgroundColor3 = Theme.Background
	root.BorderSizePixel = 0
	root.Size = UDim2.new(1, 0, 0, 20)
	root.Parent = parent

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = Theme.Health
	fill.BorderSizePixel = 0
	fill.Parent = root

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.TextColor3 = Theme.Text
	label.TextSize = 12
	label.ZIndex = 2
	label.Parent = root

	local function update(nextProps: Props)
		local maximum = math.max(nextProps.maxHealth, 1)
		local ratio = math.clamp(nextProps.health / maximum, 0, 1)
		fill.Size = UDim2.fromScale(ratio, 1)
		label.Text = `HP {nextProps.health}/{nextProps.maxHealth}  Shield {nextProps.shield}`
	end

	update(props)
	return table.freeze({
		instance = root,
		update = update,
		destroy = function()
			root:Destroy()
		end,
	})
end

return table.freeze(CritterHealthBar)
