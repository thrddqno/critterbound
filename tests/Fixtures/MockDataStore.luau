--!strict

local function clone<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, child in value :: any do
		result[clone(key)] = clone(child)
	end
	return result :: any
end

local function new()
	local values = {}
	local failures = 0
	local replayCallbacks = false
	local calls = 0
	local yieldUpdates = false
	local yieldFunction = nil
	local store = {}

	function store:UpdateAsync(key: string, callback)
		calls += 1
		if yieldUpdates then
			yieldFunction()
		end
		if failures > 0 then
			failures -= 1
			error("mock transient DataStore failure")
		end
		local nextValue = callback(clone(values[key]))
		if replayCallbacks and nextValue ~= nil then
			nextValue = callback(clone(nextValue))
		end
		if nextValue ~= nil then
			values[key] = clone(nextValue)
		end
		return clone(nextValue)
	end

	function store.set(key: string, value)
		values[key] = clone(value)
	end

	function store.get(key: string)
		return clone(values[key])
	end

	function store.failNext(count: number)
		failures = count
	end

	function store.replay(value: boolean)
		replayCallbacks = value
	end

	function store.yieldOnUpdate(value: boolean, callback)
		yieldUpdates = value
		yieldFunction = callback
	end

	function store.callCount(): number
		return calls
	end

	return store
end

return table.freeze({ new = new })
