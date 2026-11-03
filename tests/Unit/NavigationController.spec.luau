--!strict

return function(Harness)
	local NavigationController = require("../../src/client/Controllers/NavigationController")

	Harness.test("navigation ignores duplicate route and callbacks after destroy", function()
		local changes = {}
		local navigation = NavigationController.new("MAIN_MENU", function(route)
			table.insert(changes, route)
		end)
		navigation.navigate("MAIN_MENU")
		navigation.navigate("COLLECTION")
		navigation.navigate("COLLECTION")
		Harness.deepEqual(changes, { "COLLECTION" })
		navigation.destroy()
		navigation.navigate("INVENTORY")
		Harness.deepEqual(changes, { "COLLECTION" })
	end)
end
