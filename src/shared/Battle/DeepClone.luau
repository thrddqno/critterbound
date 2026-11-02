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

return table.freeze({
	clone = clone,
})
