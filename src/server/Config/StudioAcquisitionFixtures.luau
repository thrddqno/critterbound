--!strict

-- Studio-only Run 7E.2 inspection fixtures. Deterministic, idempotent, and never
-- invoked outside RunService:IsStudio().

local function requireShared(folder: string, name: string)
	if script ~= nil then
		return require(game:GetService("ReplicatedStorage").Shared[folder][name])
	end
	return require(`../../shared/{folder}/{name}`)
end

local AppearanceResolver = requireShared("Genetics", "AppearanceResolver")
local AbilityResolver = requireShared("Genetics", "AbilityResolver")
local GeneRegistry = requireShared("Genetics", "GeneRegistry")

local StudioAcquisitionFixtures = {}

local FIXTURES = {
	{
		poolId = "COMMON_FOUNDERS",
		salt = 101,
		class = nil,
	},
	{
		poolId = "CLASS_SPECIFIC_FOUNDERS",
		salt = 211,
		class = "Stone",
	},
	{
		poolId = "CROSS_CLASS_CARRIERS",
		salt = 307,
		class = "Tide",
	},
}

local function seedFor(userId: number, salt: number): number
	return ((userId * 7919 + salt * 104729) % 2147483645) + 1
end

local function carriersFor(genome, slots)
	local carriers = {}
	for _, slot in slots do
		local triplet = genome.slots[slot]
		for _, position in GeneRegistry.Positions do
			if position ~= "D" and triplet[position] ~= triplet.D then
				table.insert(carriers, `{slot}:{position}={triplet[position]}`)
			end
		end
	end
	return carriers
end

local function describe(result)
	local appearance = AppearanceResolver.resolve(result.appearanceGenome, result.class)
	local ability = if appearance.ok
		then AbilityResolver.resolve(result.abilityGenome, result.class, appearance.value.speciesId)
		else nil
	local visible = {}
	if appearance.ok then
		table.insert(visible, appearance.value.bodyGeneId)
		for _, layer in appearance.value.layers do
			table.insert(visible, layer.geneId)
		end
	end
	local abilityIds = if ability ~= nil and ability.ok then ability.value.abilityIds else {}
	local carriers = {}
	for _, carrier in carriersFor(result.appearanceGenome, GeneRegistry.AppearanceSlots) do
		table.insert(carriers, carrier)
	end
	for _, carrier in carriersFor(result.abilityGenome, GeneRegistry.AbilitySlots) do
		table.insert(carriers, carrier)
	end
	return {
		class = result.class,
		visible = table.concat(visible, ","),
		abilities = table.concat(abilityIds, ","),
		carriers = if #carriers == 0 then "none" else table.concat(carriers, ","),
		traceSteps = if result.trace ~= nil and result.trace.steps ~= nil
			then #result.trace.steps
			else 0,
		forced = if result.trace ~= nil and result.trace.forcedVariant ~= nil
			then result.trace.forcedVariant
			else "none",
	}
end

function StudioAcquisitionFixtures.run(player: Player, service)
	for _, fixture in FIXTURES do
		local seed = seedFor(player.UserId, fixture.salt)
		local commandId = `studio.7e2.{fixture.poolId}.{player.UserId}`
		local request = {
			commandId = commandId,
			grantId = `grant.{commandId}`,
			poolId = fixture.poolId,
			seed = seed,
			class = fixture.class,
			context = { kind = "SERVER", source = "STUDIO_FIXTURE" },
		}
		local candidate = service.GenerateCandidate(request)
		if not candidate.ok then
			print(
				`[Critterbound] Acquisition fixture {fixture.poolId} generation failed: {candidate.errors[1].code}`
			)
			continue
		end
		local granted = service.GrantCritter(player.UserId, request)
		if not granted.ok then
			print(
				`[Critterbound] Acquisition fixture {fixture.poolId} grant failed: {granted.errors[1].code}`
			)
			continue
		end
		local info = describe(candidate.value)
		print(
			`[Critterbound] ACQUISITION FIXTURE pool={fixture.poolId} v={candidate.value.poolVersion} seed={seed} class={info.class} duplicate={granted.value.duplicate}`
		)
		print(`[Critterbound]   visible={info.visible}`)
		print(`[Critterbound]   abilities={info.abilities}`)
		print(`[Critterbound]   carriers={info.carriers}`)
		print(
			`[Critterbound]   traceSteps={info.traceSteps} forcedVariant={info.forced} source={candidate.value.source}`
		)
	end
end

return table.freeze(StudioAcquisitionFixtures)
