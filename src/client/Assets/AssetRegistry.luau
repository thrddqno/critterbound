--!strict

export type AssetCategory =
	"CREATURE_BASE"
	| "CREATURE_LAYER"
	| "CREATURE_ANIMATION"
	| "CARD_ART"
	| "CLASS_ICON"
	| "EQUIPMENT_ICON"
	| "STATUS_ICON"
	| "BATTLEFIELD_BACKGROUND"
	| "UI_TEXTURE"
	| "VISUAL_EFFECT"

export type SpritePlacement = {
	slot: string,
	canvasSize: { width: number, height: number },
	pivot: { x: number, y: number },
	position: { x: number, y: number },
	size: { width: number, height: number },
}

export type AssetEntry = {
	id: string,
	category: AssetCategory,
	image: string?,
	fallbackId: string?,
	importSlot: string?,
	sprite: SpritePlacement?,
}

export type ResolvedAsset = {
	requestedId: string,
	resolvedId: string,
	category: AssetCategory?,
	image: string?,
	isPlaceholder: boolean,
	label: string,
	importSlot: string?,
	sprite: SpritePlacement?,
}

export type Registry = {
	resolve: (self: Registry, id: string) -> ResolvedAsset,
	has: (self: Registry, id: string) -> boolean,
	diagnostics: (self: Registry) -> any,
}

local AssetRegistry = {}
local function requireValidator()
	if script ~= nil then
		return require(script.Parent.AssetManifestValidator)
	end
	return require("./AssetManifestValidator")
end
local AssetManifestValidator = requireValidator()

local function isImageUri(value: unknown): boolean
	return type(value) == "string" and string.match(value, "^rbxassetid://%d+$") ~= nil
end

local function new(entries: { AssetEntry }): Registry
	local validation = AssetManifestValidator.validate(entries)
	if not validation.ok then
		local firstError = nil
		for _, value in validation.diagnostics do
			if value.severity == "ERROR" then
				firstError = value
				break
			end
		end
		error(
			`Asset manifest validation failed: {if firstError ~= nil
				then firstError.code .. ": " .. firstError.message
				else "unknown error"}`
		)
	end
	local catalog: { [string]: AssetEntry } = {}

	for _, entry in entries do
		assert(catalog[entry.id] == nil, `Duplicate asset identifier: {entry.id}`)
		assert(entry.image == nil or isImageUri(entry.image), `Invalid image URI for {entry.id}`)
		catalog[entry.id] = table.freeze({
			id = entry.id,
			category = entry.category,
			image = entry.image,
			fallbackId = entry.fallbackId,
			importSlot = entry.importSlot,
			sprite = entry.sprite,
		})
	end

	local registry = {} :: any

	function registry:has(id: string): boolean
		return catalog[id] ~= nil
	end

	function registry:diagnostics()
		return validation
	end

	function registry:resolve(id: string): ResolvedAsset
		local requestedId = id
		local currentId = id
		local visited: { [string]: boolean } = {}

		while not visited[currentId] do
			visited[currentId] = true
			local entry = catalog[currentId]
			if entry == nil then
				break
			end
			if entry.image ~= nil then
				return {
					requestedId = requestedId,
					resolvedId = currentId,
					category = entry.category,
					image = entry.image,
					isPlaceholder = false,
					label = currentId,
					importSlot = entry.importSlot,
					sprite = entry.sprite,
				}
			end
			if entry.fallbackId == nil then
				return {
					requestedId = requestedId,
					resolvedId = currentId,
					category = entry.category,
					image = nil,
					isPlaceholder = true,
					label = `Placeholder\n{requestedId}`,
					importSlot = entry.importSlot,
					sprite = entry.sprite,
				}
			end
			currentId = entry.fallbackId
		end

		return {
			requestedId = requestedId,
			resolvedId = "placeholder.missing",
			category = nil,
			image = nil,
			isPlaceholder = true,
			label = `Missing asset\n{requestedId}`,
			importSlot = nil,
			sprite = nil,
		}
	end

	return table.freeze(registry) :: Registry
end

AssetRegistry.new = new
AssetRegistry.isImageUri = isImageUri

return table.freeze(AssetRegistry)
