--!strict

local AssetManifestValidator = {}
local VALID_SLOTS = table.freeze({
	shadow = true,
	body = true,
	color = true,
	markings = true,
	tail = true,
	wings = true,
	eyes = true,
	mouth = true,
	accessories = true,
})
local VALID_CATEGORIES = table.freeze({
	CREATURE_BASE = true,
	CREATURE_LAYER = true,
	CREATURE_ANIMATION = true,
	CARD_ART = true,
	CLASS_ICON = true,
	EQUIPMENT_ICON = true,
	STATUS_ICON = true,
	BATTLEFIELD_BACKGROUND = true,
	UI_TEXTURE = true,
	VISUAL_EFFECT = true,
})

local function diagnostic(severity: string, code: string, message: string, path: string?)
	return { severity = severity, code = code, message = message, path = path }
end

local function normalizedPoint(value): boolean
	return type(value) == "table"
		and type(value.x) == "number"
		and type(value.y) == "number"
		and value.x >= 0
		and value.x <= 1
		and value.y >= 0
		and value.y <= 1
end

local function positiveSize(value): boolean
	return type(value) == "table"
		and type(value.width) == "number"
		and type(value.height) == "number"
		and value.width > 0
		and value.height > 0
end

function AssetManifestValidator.validate(entries)
	local diagnostics = {}
	local seen = {}
	for index, entry in entries do
		local path = `entries[{index}]`
		if type(entry.id) ~= "string" or entry.id == "" then
			table.insert(
				diagnostics,
				diagnostic(
					"ERROR",
					"INVALID_ASSET_ID",
					"Asset ID must be a non-empty string",
					`{path}.id`
				)
			)
		elseif seen[entry.id] then
			table.insert(
				diagnostics,
				diagnostic(
					"ERROR",
					"DUPLICATE_ASSET_ID",
					`Duplicate asset identifier: {entry.id}`,
					`{path}.id`
				)
			)
		else
			seen[entry.id] = true
		end
		if not VALID_CATEGORIES[entry.category] then
			table.insert(
				diagnostics,
				diagnostic(
					"ERROR",
					"INVALID_ASSET_CATEGORY",
					"Asset category is unknown",
					`{path}.category`
				)
			)
		end
		if entry.importSlot ~= nil and type(entry.importSlot) ~= "string" then
			table.insert(
				diagnostics,
				diagnostic(
					"ERROR",
					"INVALID_IMPORT_SLOT",
					"Import slot must be a string",
					`{path}.importSlot`
				)
			)
		end
		if
			entry.image ~= nil
			and (
				type(entry.image) ~= "string"
				or string.match(entry.image, "^rbxassetid://%d+$") == nil
			)
		then
			table.insert(
				diagnostics,
				diagnostic(
					"ERROR",
					"INVALID_IMAGE_URI",
					"Image must use rbxassetid://<digits>",
					`{path}.image`
				)
			)
		end
		local sprite = entry.sprite
		if sprite ~= nil then
			if not VALID_SLOTS[sprite.slot] then
				table.insert(
					diagnostics,
					diagnostic(
						"ERROR",
						"INVALID_SPRITE_SLOT",
						"Sprite slot is unknown",
						`{path}.sprite.slot`
					)
				)
			end
			if not positiveSize(sprite.canvasSize) then
				table.insert(
					diagnostics,
					diagnostic(
						"ERROR",
						"INVALID_CANVAS_SIZE",
						"Sprite canvas size must be positive",
						`{path}.sprite.canvasSize`
					)
				)
			end
			if not normalizedPoint(sprite.pivot) then
				table.insert(
					diagnostics,
					diagnostic(
						"ERROR",
						"INVALID_SPRITE_PIVOT",
						"Sprite pivot must be normalized",
						`{path}.sprite.pivot`
					)
				)
			end
			if not normalizedPoint(sprite.position) then
				table.insert(
					diagnostics,
					diagnostic(
						"ERROR",
						"INVALID_SPRITE_POSITION",
						"Sprite position must be normalized",
						`{path}.sprite.position`
					)
				)
			end
			if not positiveSize(sprite.size) then
				table.insert(
					diagnostics,
					diagnostic(
						"ERROR",
						"INVALID_SPRITE_SIZE",
						"Sprite render size must be positive",
						`{path}.sprite.size`
					)
				)
			end
			if entry.image == nil then
				table.insert(
					diagnostics,
					diagnostic(
						"WARNING",
						"MISSING_SPRITE_IMAGE",
						`Sprite import slot has no image: {entry.id}`,
						path
					)
				)
			end
		end
	end
	local errors = 0
	local warnings = 0
	for _, value in diagnostics do
		if value.severity == "ERROR" then
			errors += 1
		else
			warnings += 1
		end
	end
	return { ok = errors == 0, errors = errors, warnings = warnings, diagnostics = diagnostics }
end

return table.freeze(AssetManifestValidator)
