--!strict

return function(Harness)
	local AssetRegistry = require("../../src/client/Assets/AssetRegistry")
	local AssetManifestValidator = require("../../src/client/Assets/AssetManifestValidator")
	local BloomSpriteManifest = require("../../src/client/Assets/BloomSpriteManifest")

	Harness.test("registered placeholder resolves safely", function()
		local registry =
			AssetRegistry.new({ { id = "creature.stone.default", category = "CREATURE_BASE" } })
		local resolved = registry:resolve("creature.stone.default")
		Harness.expect(resolved.isPlaceholder)
		Harness.equal(resolved.requestedId, "creature.stone.default")
	end)

	Harness.test("missing asset returns labeled fallback", function()
		local registry = AssetRegistry.new({})
		local resolved = registry:resolve("card.missing.art")
		Harness.expect(resolved.isPlaceholder)
		Harness.equal(resolved.resolvedId, "placeholder.missing")
		Harness.expect(string.find(resolved.label, "card.missing.art", 1, true) ~= nil)
	end)

	Harness.test("registered image and fallback chain resolve", function()
		local registry = AssetRegistry.new({
			{ id = "fallback.card", category = "CARD_ART", image = "rbxassetid://123" },
			{ id = "card.future", category = "CARD_ART", fallbackId = "fallback.card" },
		})
		local resolved = registry:resolve("card.future")
		Harness.expect(not resolved.isPlaceholder)
		Harness.equal(resolved.image, "rbxassetid://123")
		Harness.equal(resolved.resolvedId, "fallback.card")
	end)

	Harness.test("arbitrary image URI rejected", function()
		Harness.expect(not AssetRegistry.isImageUri("https://example.com/image.png"))
		Harness.expect(not AssetRegistry.isImageUri("rbxassetid://abc"))
		Harness.expect(AssetRegistry.isImageUri("rbxassetid://123"))
		local ok = pcall(function()
			AssetRegistry.new({
				{ id = "unsafe", category = "UI_TEXTURE", image = "https://example.com" },
			})
		end)
		Harness.expect(not ok)
	end)

	Harness.test("registered sprite preserves explicit placement metadata", function()
		local sprite = {
			slot = "body",
			canvasSize = { width = 1024, height = 1024 },
			pivot = { x = 0.5, y = 0.88 },
			position = { x = 0.5, y = 0.88 },
			size = { width = 1, height = 1 },
		}
		local registry = AssetRegistry.new({
			{
				id = "creature.verdant.test",
				category = "CREATURE_BASE",
				image = "rbxassetid://123",
				sprite = sprite,
			},
		})
		local resolved = registry:resolve("creature.verdant.test")
		Harness.expect(not resolved.isPlaceholder)
		Harness.equal(resolved.sprite.pivot.y, 0.88)
		Harness.equal(resolved.sprite.canvasSize.width, 1024)
		Harness.equal(registry:diagnostics().errors, 0)
	end)

	Harness.test("manifest reports missing imports and rejects invalid pivots", function()
		local missing = AssetManifestValidator.validate({
			{
				id = "creature.verdant.pending",
				category = "CREATURE_LAYER",
				importSlot = "bloom/eyes.png",
				sprite = {
					slot = "eyes",
					canvasSize = { width = 1024, height = 1024 },
					pivot = { x = 0.5, y = 0.88 },
					position = { x = 0.5, y = 0.88 },
					size = { width = 1, height = 1 },
				},
			},
		})
		Harness.expect(missing.ok)
		Harness.equal(missing.warnings, 1)
		Harness.equal(missing.diagnostics[1].code, "MISSING_SPRITE_IMAGE")
		local validation = AssetManifestValidator.validate({
			{
				id = "creature.verdant.invalid",
				category = "CREATURE_LAYER",
				image = "rbxassetid://123",
				sprite = {
					slot = "eyes",
					canvasSize = { width = 1024, height = 1024 },
					pivot = { x = 1.5, y = 0.5 },
					position = { x = 0.5, y = 0.5 },
					size = { width = 1, height = 1 },
				},
			},
		})
		Harness.expect(not validation.ok)
		Harness.equal(validation.diagnostics[1].code, "INVALID_SPRITE_PIVOT")
	end)

	Harness.test("Bloom import manifest is valid and intentionally awaits artwork", function()
		local validation = AssetManifestValidator.validate(BloomSpriteManifest)
		Harness.expect(validation.ok)
		Harness.equal(validation.errors, 0)
		Harness.equal(validation.warnings, #BloomSpriteManifest)
		Harness.equal(#BloomSpriteManifest, 9)
	end)
end
