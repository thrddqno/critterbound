--!strict

local function requireShared(folder: string, name: string)
	if script ~= nil then
		return require(game:GetService("ReplicatedStorage").Shared[folder][name])
	end
	return require(`../../shared/{folder}/{name}`)
end

local GeneRegistry = requireShared("Genetics", "GeneRegistry")
local UnbiasedRandom = requireShared("Genetics", "UnbiasedRandom")

local ClassInheritancePolicy = {}
local POLICY = "CLASS_INHERITANCE_V1"

local function failure(code: string, message: string)
	return { ok = false, errors = { { code = code, message = message } } }
end

local function validClass(className): boolean
	return type(className) == "string" and GeneRegistry.defaultGenomes(className) ~= nil
end

local function resolve(classA: string, classB: string, seedOrState)
	if not validClass(classA) or not validClass(classB) then
		return failure("INVALID_PARENT_CLASS", "Both parental classes must be registered")
	end
	local normalized = if type(seedOrState) == "number"
		then UnbiasedRandom.new(seedOrState)
		else { ok = true, value = seedOrState }
	if
		not normalized.ok
		or type(normalized.value) ~= "table"
		or normalized.value.algorithm ~= UnbiasedRandom.Algorithm
		or type(normalized.value.state) ~= "number"
		or normalized.value.state % 1 ~= 0
		or normalized.value.state < 1
		or normalized.value.state >= UnbiasedRandom.Modulus
		or type(normalized.value.drawCount) ~= "number"
		or normalized.value.drawCount % 1 ~= 0
		or normalized.value.drawCount < 0
	then
		return failure("INVALID_RNG_STATE", "Explicit deterministic RNG seed or state is required")
	end

	local rng = normalized.value
	if classA == classB then
		return {
			ok = true,
			value = { class = classA, rng = rng, policy = POLICY, parent = "SHARED" },
		}
	end
	local roll
	rng, roll = UnbiasedRandom.nextInteger(rng, 1, 2)
	return {
		ok = true,
		value = {
			class = if roll == 1 then classA else classB,
			rng = rng,
			policy = POLICY,
			parent = if roll == 1 then "A" else "B",
		},
	}
end

ClassInheritancePolicy.Policy = POLICY
ClassInheritancePolicy.resolve = resolve

return table.freeze(ClassInheritancePolicy)
