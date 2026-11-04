--!strict

local Theme = require(script.Parent.Parent.Theme)
local TweenService = game:GetService("TweenService")

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

	local shieldFill = Instance.new("Frame")
	shieldFill.Name = "ShieldFill"
	shieldFill.BackgroundColor3 = Theme.Shield
	shieldFill.BackgroundTransparency = 0.25
	shieldFill.BorderSizePixel = 0
	shieldFill.ZIndex = 1
	shieldFill.Parent = root

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.TextColor3 = Theme.Text
	label.TextSize = 12
	label.ZIndex = 2
	label.Parent = root

	local healthTween: Tween? = nil
	local shieldTween: Tween? = nil
	local initialized = false
	local function update(nextProps: Props)
		local maximum = math.max(nextProps.maxHealth, 1)
		local ratio = math.clamp(nextProps.health / maximum, 0, 1)
		local shieldRatio = math.clamp(nextProps.shield / maximum, 0, 1)
		if initialized then
			if healthTween ~= nil then
				healthTween:Cancel()
			end
			if shieldTween ~= nil then
				shieldTween:Cancel()
			end
			healthTween = TweenService:Create(
				fill,
				TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Size = UDim2.fromScale(ratio, 1) }
			)
			shieldTween = TweenService:Create(
				shieldFill,
				TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Size = UDim2.fromScale(shieldRatio, 1) }
			)
			healthTween:Play()
			shieldTween:Play()
		else
			fill.Size = UDim2.fromScale(ratio, 1)
			shieldFill.Size = UDim2.fromScale(shieldRatio, 1)
			initialized = true
		end
		label.Text = `HP {nextProps.health}/{nextProps.maxHealth}  Shield {nextProps.shield}`
	end

	update(props)
	return table.freeze({
		instance = root,
		update = update,
		destroy = function()
			if healthTween ~= nil then
				healthTween:Cancel()
			end
			if shieldTween ~= nil then
				shieldTween:Cancel()
			end
			root:Destroy()
		end,
	})
end

return table.freeze(CritterHealthBar)
