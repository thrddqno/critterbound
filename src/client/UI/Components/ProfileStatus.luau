--!strict

local UIFactory = require(script.Parent.UIFactory)
local ProfileStatus = {}

function ProfileStatus.mount(parent: Instance, props)
	local screen, root = UIFactory.screen(parent, "CritterboundProfileStatus")
	local label = UIFactory.label(root, props.message or "Loading profile...", 24)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.45)
	label.Size = UDim2.fromScale(0.8, 0.2)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	local retry = UIFactory.button(root, "Retry")
	retry.AnchorPoint = Vector2.new(0.5, 0)
	retry.Position = UDim2.fromScale(0.5, 0.58)
	retry.Size = UDim2.fromOffset(180, 48)
	local current = props
	local connection = retry.Activated:Connect(function()
		if current.onRetry ~= nil then
			current.onRetry()
		end
	end)
	local function update(nextProps)
		current = nextProps
		label.Text = nextProps.message or "Loading profile..."
		retry.Visible = nextProps.canRetry == true
	end
	update(props)
	return table.freeze({
		update = update,
		destroy = function()
			connection:Disconnect()
			screen:Destroy()
		end,
	})
end

return table.freeze(ProfileStatus)
