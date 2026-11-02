# Art Integration

Run 3 renders static placeholders only. Artwork replacement must not require gameplay code changes.

## Static and layered Critters

Prepare a consistent canvas, transparent background, facing direction, baseline, and anchor point.
Layered appearance art must share identical dimensions and pivots. Suggested layer order:

1. Shadow
2. Base body
3. Palette or pattern
4. Body details
5. Equipment
6. Battle effects

Appearance genome fields select visual layer IDs through a future appearance resolver. Ability
genome fields never select appearance assets. Missing combinations fall back to base sprite and
never alter combat data.

## Sprite sheets

`SpriteContracts.luau` defines frame rectangles, frame duration, loop behavior, animation state,
layer order, anchors, and playback lifecycle. Before integration, every sheet needs:

- Fixed frame dimensions or explicit frame rectangles
- Stable anchor and baseline across frames
- Transparent padding policy
- State names and fallback frame
- Timing authored in seconds
- Documented loop and completion behavior
- Consistent layer registration when animations use separate layers

AI-generated single illustrations are not assumed to contain valid animation frames or separable
layers. They require manual preparation and consistency review.

## Cards and interface art

Card illustrations need a shared aspect ratio, safe crop region, readable silhouette, and no baked
text. UI textures should tolerate scaling or use documented slicing metadata. Class and status
icons need legible shapes at small sizes.

## Intentionally absent

- Sprite playback scheduler
- Animation event binding
- Hit, attack, and defeat transitions
- Particle systems and visual effects
- Equipment compositing
- Automated genome-to-layer resolution
- Production artwork or Roblox asset IDs
