--!strict

local EggPresentation = {}

local Tabs = table.freeze({
	ACTIVE = "ACTIVE",
	HISTORY = "HISTORY",
})

local function parentLabel(parent): string
	if type(parent) ~= "table" then
		return "Unknown"
	end
	local name = parent.displayName or "Unknown Critter"
	local class = parent.class or "Unknown"
	return `{name} ({class})`
end

local function statusLabel(status: string): string
	if status == "READY" then
		return "Ready to hatch"
	elseif status == "HATCHED" then
		return "Hatched"
	end
	return "Incubating"
end

local function remainingSeconds(egg, now: number): number
	if egg.status == "READY" or egg.status == "HATCHED" then
		return 0
	end
	return math.max(0, math.floor((egg.hatchAt or now) - now))
end

local function formatRemaining(seconds: number): string
	local minutes = math.floor(seconds / 60)
	local remainder = seconds % 60
	return `{minutes}:{if remainder < 10 then "0" else ""}{remainder}`
end

local function tabForStatus(status: string): string?
	if status == "INCUBATING" or status == "READY" then
		return Tabs.ACTIVE
	elseif status == "HATCHED" then
		return Tabs.HISTORY
	end
	return nil
end

local function formatHatchDate(timestamp: number?): string
	if type(timestamp) ~= "number" then
		return "Unknown"
	end
	return os.date("!%Y-%m-%d %H:%M UTC", timestamp)
end

local function mapEgg(egg, now: number)
	local seconds = remainingSeconds(egg, now)
	local status = egg.status or "INCUBATING"
	return {
		id = egg.eggId,
		status = status,
		statusText = statusLabel(status),
		parentText = `{parentLabel(egg.parentA)} + {parentLabel(egg.parentB)}`,
		generationText = `Generation {egg.generation or 0}`,
		offspringText = `Offspring class: {egg.offspringClass or "Unknown"}`,
		remainingSeconds = seconds,
		remainingText = if status == "INCUBATING"
			then formatRemaining(seconds)
			else statusLabel(status),
		hatchDateText = formatHatchDate(egg.hatchedAt),
		canHatch = status == "READY",
		egg = egg,
	}
end

function EggPresentation.map(eggs, now: number?)
	local timestamp = now or os.time()
	local result = {}
	for _, egg in eggs or {} do
		table.insert(result, mapEgg(egg, timestamp))
	end
	return result
end

function EggPresentation.filterByTab(eggs, tab: string)
	local result = {}
	for _, egg in eggs or {} do
		if tabForStatus(egg.status or "INCUBATING") == tab then
			table.insert(result, egg)
		end
	end
	return result
end

EggPresentation.mapEgg = mapEgg
EggPresentation.remainingSeconds = remainingSeconds
EggPresentation.formatRemaining = formatRemaining
EggPresentation.formatHatchDate = formatHatchDate
EggPresentation.parentLabel = parentLabel
EggPresentation.statusLabel = statusLabel
EggPresentation.tabForStatus = tabForStatus
EggPresentation.Tabs = Tabs
return table.freeze(EggPresentation)
