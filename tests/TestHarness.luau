--!strict

export type Harness = {
	test: (name: string, callback: () -> ()) -> (),
	expect: (condition: boolean, message: string?) -> (),
	equal: (actual: any, expected: any, message: string?) -> (),
	deepEqual: (actual: any, expected: any, message: string?) -> (),
	hasError: (result: any, code: string) -> boolean,
	clone: <T>(value: T) -> T,
}

type TestCase = {
	name: string,
	callback: () -> (),
}

local tests: { TestCase } = {}

local function test(name: string, callback: () -> ())
	table.insert(tests, { name = name, callback = callback })
end

local function expect(condition: boolean, message: string?)
	if not condition then
		error(message or "Expectation failed", 2)
	end
end

local function equal(actual: any, expected: any, message: string?)
	if actual ~= expected then
		error(message or `Expected {tostring(expected)}, received {tostring(actual)}`, 2)
	end
end

local function valuesDeepEqual(a: any, b: any, visited: { [any]: any }): boolean
	if type(a) ~= type(b) then
		return false
	end
	if type(a) ~= "table" then
		return a == b
	end
	if visited[a] == b then
		return true
	end
	visited[a] = b

	for key, value in a do
		if not valuesDeepEqual(value, b[key], visited) then
			return false
		end
	end
	for key in b do
		if a[key] == nil then
			return false
		end
	end

	return true
end

local function deepEqual(actual: any, expected: any, message: string?)
	if not valuesDeepEqual(actual, expected, {}) then
		error(message or "Expected tables to be deeply equal", 2)
	end
end

local function hasError(result: any, code: string): boolean
	if type(result) ~= "table" or result.ok ~= false or type(result.errors) ~= "table" then
		return false
	end
	for _, domainError in result.errors do
		if domainError.code == code then
			return true
		end
	end
	return false
end

local function clone<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end

	local copy = {}
	for key, child in value :: any do
		copy[clone(key)] = clone(child)
	end
	return copy :: any
end

local function run()
	local passed = 0
	local failures: { string } = {}

	for _, case in tests do
		local ok, failure = pcall(case.callback)
		if ok then
			passed += 1
			print(`PASS {case.name}`)
		else
			table.insert(failures, `FAIL {case.name}: {tostring(failure)}`)
		end
	end

	for _, failure in failures do
		warn(failure)
	end

	print(`{passed}/{#tests} tests passed`)
	if #failures > 0 then
		error(`{#failures} test(s) failed`)
	end
end

return table.freeze({
	test = test,
	expect = expect,
	equal = equal,
	deepEqual = deepEqual,
	hasError = hasError,
	clone = clone,
	run = run,
})
