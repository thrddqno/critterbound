--!strict

return function(Harness)
	local AssetRegistry = require("../../src/client/Assets/AssetRegistry")

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
end
