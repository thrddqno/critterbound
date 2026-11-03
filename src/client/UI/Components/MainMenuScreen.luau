--!strict

local UIFactory = require(script.Parent.UIFactory)
local MainMenuScreen = {}

function MainMenuScreen.mount(parent: Instance, props)
	local screen, root = UIFactory.screen(parent, "CritterboundMainMenu")
	local title = UIFactory.label(root, "CRITTERBOUND", 34)
	title.Position = UDim2.fromScale(0.1, 0.08)
	title.Size = UDim2.fromScale(0.8, 0.1)
	title.TextXAlignment = Enum.TextXAlignment.Center
	local host = Instance.new("Frame")
	host.BackgroundTransparency = 1
	host.AnchorPoint = Vector2.new(0.5, 0)
	host.Position = UDim2.fromScale(0.5, 0.23)
	host.Size = UDim2.fromScale(0.7, 0.65)
	host.Parent = root
	UIFactory.list(host, 10)
	local connections = {}
	for _, entry in
		{
			{ "Collection", props.onCollection },
			{ "Team Builder", props.onTeamBuilder },
			{ "Inventory", props.onInventory },
			{ "Breeding", props.onBreeding },
			{ "Eggs", props.onEggs },
			{ "Contracts", props.onContracts },
			{ "Training Grounds", props.onBattle },
			{ "Sprite Preview", props.onSpritePreview },
		}
	do
		if entry[2] ~= nil then
			local button = UIFactory.button(host, entry[1])
			button.Size = UDim2.new(1, 0, 0, 56)
			table.insert(connections, button.Activated:Connect(entry[2]))
		end
	end
	return table.freeze({
		update = function() end,
		destroy = function()
			for _, connection in connections do
				connection:Disconnect()
			end
			screen:Destroy()
		end,
	})
end

return table.freeze(MainMenuScreen)
