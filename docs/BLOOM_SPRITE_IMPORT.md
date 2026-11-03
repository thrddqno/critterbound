# Bloom Sprite Import Slot

No Bloom artwork is currently present in the repository. Run 7A.2 therefore registers reviewed-art
slots without inventing Roblox asset IDs. `src/client/Assets/BloomSpriteManifest.luau` is the single
integration point.

## Required source layers

Prepare transparent PNGs on one shared 1024×1024 canvas:

| Slot | Import name | Logical asset |
| --- | --- | --- |
| Shadow | `bloom/shadow.png` | `creature.structural.shadow.verdant` |
| Tail | `bloom/tail_default.png` | `creature.layer.tail.verdant.default` |
| Wings | `bloom/wings_default.png` | `creature.layer.wings.verdant.default` |
| Body | `bloom/body_default.png` | `creature.verdant.default` |
| Color | `bloom/color_default.png` | `creature.layer.color.verdant.default` |
| Markings | `bloom/markings_default.png` | `creature.layer.markings.verdant.default` |
| Eyes | `bloom/eyes_default.png` | `creature.layer.eyes.verdant.default` |
| Mouth | `bloom/mouth_default.png` | `creature.structural.mouth.verdant` |
| Accessory | `bloom/accessory_default.png` | `creature.layer.accessories.verdant.default` |

Every file must preserve transparent padding, baseline, and ground pivot `(0.5, 0.88)`. Do not crop
layers independently. Eyes, mouth, tail, and accessories must contain only their own pixels so gene
or structural swaps do not replace unrelated art.

## Import procedure

1. Review source artwork for clean transparency, shared proportions, and separable layers.
2. Upload each approved PNG through normal Roblox asset ownership workflow.
3. Add its real `rbxassetid://<digits>` URI to the matching manifest entry's `image` field.
4. Keep `sprite.canvasSize`, `pivot`, `position`, and `size` aligned with the authored source.
5. Run tests, lint, Rojo build, and Studio preview. Verify each layer against geometric fallback.

`AssetManifestValidator` rejects malformed URIs, categories, slots, pivots, positions, canvas sizes,
and render sizes. Missing images remain warnings and resolve to class-specific geometric fallback.
Diagnostics are available through `AssetCatalog:diagnostics()` and the Studio-only preview inspector.

## Animation behavior

The existing whole-rig `IDLE`, `ATTACK`, `HIT`, and `DEFEAT` transforms apply to real layers and
fallback layers identically. This import slot does not claim that a single illustration is an authored
sprite sheet. State-specific sheets require separately reviewed frames and manifest entries.
