--!strict

local BattleHudPresentation = {}

local function bloodMoonDamage(config, roundNumber: number): number?
	if
		config == nil
		or config.Enabled ~= true
		or type(config.StartingRound) ~= "number"
		or roundNumber < config.StartingRound
	then
		return nil
	end
	return (config.InitialDamage or 0)
		+ (config.DamageIncrement or 0) * (roundNumber - config.StartingRound)
end

local function state(props, serverNow: number)
	local timer = "--:--"
	if props.phase == "PLANNING" and props.planningDeadline ~= nil then
		local remaining = math.max(0, math.ceil(props.planningDeadline - serverNow))
		timer = string.format("%02d:%02d", math.floor(remaining / 60), remaining % 60)
	end
	local commitment = if props.committed then "COMMITTED" else "READY"
	local bloodMoonText = nil
	local config = props.bloodMoon
	if config ~= nil and config.Enabled == true then
		if props.roundNumber == config.StartingRound - 1 then
			bloodMoonText = `WARNING: BLOOD MOON NEXT — {config.InitialDamage or 0} HP`
		elseif props.roundNumber >= config.StartingRound then
			bloodMoonText = `BLOOD MOON — {bloodMoonDamage(config, props.roundNumber) or 0} HP`
		else
			bloodMoonText = `BLOOD MOON R{config.StartingRound} — {config.InitialDamage or 0} HP`
		end
	end
	local base = `ROUND {props.roundNumber}   {props.phase}   {timer}   {commitment}`
	return {
		round = props.roundNumber,
		phase = props.phase,
		timer = timer,
		commitment = commitment,
		bloodMoonDamage = bloodMoonDamage(config, props.roundNumber),
		bloodMoonWarning = props.roundNumber
			== (if config ~= nil then config.StartingRound else -1) - 1,
		text = if bloodMoonText ~= nil then `{base}   |   {bloodMoonText}` else base,
	}
end

local function orderChips(entries)
	local indexed = {}
	for inputIndex, entry in entries do
		table.insert(indexed, { inputIndex = inputIndex, entry = entry })
	end
	table.sort(indexed, function(a, b)
		if a.entry.position ~= b.entry.position then
			return a.entry.position < b.entry.position
		end
		return a.inputIndex < b.inputIndex
	end)
	local result = {}
	for _, value in indexed do
		local entry = value.entry
		table.insert(result, {
			position = entry.position,
			combatantId = entry.combatantId,
			displayName = entry.displayName,
			class = entry.class,
			side = entry.side,
			speed = entry.speed,
			label = `#{entry.position}  {entry.displayName}`,
		})
	end
	return result
end

BattleHudPresentation.state = state
BattleHudPresentation.orderChips = orderChips
return table.freeze(BattleHudPresentation)
