--!strict

local NavigationController = {}

function NavigationController.new(initialRoute: string, onChanged: (string) -> ())
	local route = initialRoute
	local destroyed = false
	local service = {}

	function service.navigate(nextRoute: string)
		if destroyed or nextRoute == route then
			return
		end
		route = nextRoute
		onChanged(route)
	end

	function service.current(): string
		return route
	end

	function service.destroy()
		destroyed = true
	end

	return table.freeze(service)
end

return table.freeze(NavigationController)
