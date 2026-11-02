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

export type AssetEntry = {
	id: string,
	category: AssetCategory,
	image: string?,
	fallbackId: string?,
}

export type ResolvedAsset = {
	requestedId: string,
	resolvedId: string,
	category: AssetCategory?,
	image: string?,
	isPlaceholder: boolean,
	label: string,
}

export type Registry = {
	resolve: (self: Registry, id: string) -> ResolvedAsset,
	has: (self: Registry, id: string) -> boolean,
}

local AssetRegistry = {}

local function isImageUri(value: unknown): boolean
	return type(value) == "string" and string.match(value, "^rbxassetid://%d+$") ~= nil
end

local function new(entries: { AssetEntry }): Registry
	local catalog: { [string]: AssetEntry } = {}

	for _, entry in entries do
		assert(catalog[entry.id] == nil, `Duplicate asset identifier: {entry.id}`)
		assert(entry.image == nil or isImageUri(entry.image), `Invalid image URI for {entry.id}`)
		catalog[entry.id] = table.freeze({
			id = entry.id,
			category = entry.category,
			image = entry.image,
			fallbackId = entry.fallbackId,
		})
	end

	local registry = {} :: any

	function registry:has(id: string): boolean
		return catalog[id] ~= nil
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
		}
	end

	return table.freeze(registry) :: Registry
end

AssetRegistry.new = new
AssetRegistry.isImageUri = isImageUri

return table.freeze(AssetRegistry)
