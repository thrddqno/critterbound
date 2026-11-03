--!strict

return function(Harness)
	local GeneRegistry = require("../../src/shared/Genetics/GeneRegistry")
	local AppearanceResolver = require("../../src/shared/Genetics/AppearanceResolver")
	local CritterSpriteModel = require("../../src/client/Rendering/CritterSpriteModel")
	local SpriteRigCatalog = require("../../src/client/Rendering/SpriteRigCatalog")
	local CritterAnimationState = require("../../src/client/Rendering/CritterAnimationState")
	local SpriteSheetPlayer = require("../../src/client/Rendering/SpriteSheetPlayer")

	Harness.test("sprite model emits explicit ordered structural and genetic layers", function()
		local genomes = GeneRegistry.defaultGenomes("Verdant")
		local resolved = AppearanceResolver.resolve(genomes.appearanceGenome, "Verdant")
		Harness.expect(resolved.ok)
		local model = CritterSpriteModel.build(resolved.value, "LEFT")
		Harness.equal(model.rigFamily, "round")
		Harness.equal(model.spriteRigId, "verdant")
		Harness.equal(model.facing, "LEFT")
		Harness.equal(#model.layers, 9)
		local expected = {
			"shadow",
			"tail",
			"wings",
			"body",
			"color",
			"markings",
			"eyes",
			"mouth",
			"accessories",
		}
		for index, slot in expected do
			Harness.equal(model.layers[index].slot, slot)
			if index > 1 then
				Harness.expect(model.layers[index - 1].order < model.layers[index].order)
			end
		end
		Harness.expect(model.layers[1].placeholder)
		Harness.expect(model.layers[8].placeholder)
		for name, attachment in model.attachments do
			Harness.expect(name ~= "")
			Harness.expect(attachment.position.x >= 0 and attachment.position.x <= 1)
			Harness.expect(attachment.position.y >= 0 and attachment.position.y <= 1)
			Harness.expect(attachment.size.width > 0 and attachment.size.width <= 1)
			Harness.expect(attachment.size.height > 0 and attachment.size.height <= 1)
		end
	end)

	Harness.test("appearance swaps change only selected sprite layer", function()
		local variants = {
			body = "gene.appearance.body.verdant.compact",
			eyes = "gene.appearance.eyes.verdant.wide",
			tail = "gene.appearance.tail.verdant.leafy",
			accessories = "gene.appearance.accessories.verdant.sprout",
		}
		for slot, variant in variants do
			local genomes = GeneRegistry.defaultGenomes("Verdant")
			local beforeResolved = AppearanceResolver.resolve(genomes.appearanceGenome, "Verdant")
			local before = CritterSpriteModel.build(beforeResolved.value)
			genomes.appearanceGenome.slots[slot] = { D = variant, R1 = variant, R2 = variant }
			local afterResolved = AppearanceResolver.resolve(genomes.appearanceGenome, "Verdant")
			local after = CritterSpriteModel.build(afterResolved.value)
			for index, layer in before.layers do
				if layer.slot == slot then
					Harness.expect(layer.assetId ~= after.layers[index].assetId)
				else
					Harness.equal(layer.assetId, after.layers[index].assetId)
				end
			end
		end
	end)

	Harness.test(
		"six class sprite rigs have distinct geometry palettes and valid tail anchors",
		function()
			local expectedBodyColors = {
				stone = { 112, 105, 94 },
				feral = { 196, 73, 45 },
				verdant = { 91, 151, 105 },
				tide = { 50, 139, 176 },
				gale = { 221, 205, 112 },
				shade = { 75, 55, 103 },
			}
			local signatures = {}
			for _, rigId in SpriteRigCatalog.Ids do
				local rig = SpriteRigCatalog.get(rigId)
				Harness.equal(rig.id, rigId)
				Harness.equal(rig.palette.body.red, expectedBodyColors[rigId][1])
				Harness.equal(rig.palette.body.green, expectedBodyColors[rigId][2])
				Harness.equal(rig.palette.body.blue, expectedBodyColors[rigId][3])
				Harness.expect(rig.attachments.tail.position.x < rig.attachments.body.position.x)
				Harness.expect(rig.attachments.tail.size.width > 0)
				local body = rig.attachments.body
				local head = rig.attachments.head
				local signature =
					`{rig.style}|{body.position.x}|{body.size.width}|{body.size.height}|{head.position.x}|{head.position.y}`
				Harness.expect(not signatures[signature])
				signatures[signature] = true
			end
		end
	)

	Harness.test(
		"class body genes select class-specific visual rigs under missing assets",
		function()
			for _, className in { "Stone", "Feral", "Verdant", "Tide", "Gale", "Shade" } do
				local genomes = GeneRegistry.defaultGenomes(className)
				local resolved = AppearanceResolver.resolve(genomes.appearanceGenome, className)
				local model = CritterSpriteModel.build(resolved.value)
				Harness.equal(model.spriteRigId, string.lower(className))
				Harness.expect(model.layers[1].placeholder)
			end
		end
	)

	Harness.test(
		"temporary animation completion returns idle and rejects stale completion",
		function()
			local idle = CritterAnimationState.new()
			local attack = CritterAnimationState.transition(idle, "ATTACK")
			local hit = CritterAnimationState.transition(attack, "HIT")
			Harness.equal(CritterAnimationState.completion(hit, attack.revision).id, "HIT")
			Harness.equal(CritterAnimationState.completion(hit, hit.revision).id, "IDLE")
			local defeat = CritterAnimationState.transition(hit, "DEFEAT")
			Harness.equal(CritterAnimationState.completion(defeat, defeat.revision).id, "DEFEAT")
		end
	)

	Harness.test("sprite sheet frame math loops and clamps", function()
		local clip = {
			looped = true,
			frames = {
				{ x = 0, y = 0, width = 32, height = 32, durationSeconds = 0.1 },
				{ x = 32, y = 0, width = 32, height = 32, durationSeconds = 0.2 },
			},
		}
		local _, index, completed = SpriteSheetPlayer.frameAt(clip, 0.35)
		Harness.equal(index, 1)
		Harness.expect(not completed)
		clip.looped = false
		local frame, lastIndex, done = SpriteSheetPlayer.frameAt(clip, 1)
		Harness.equal(lastIndex, 2)
		Harness.equal(frame.x, 32)
		Harness.expect(done)
	end)
end
