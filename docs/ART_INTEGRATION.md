# Art Integration

Run 7A.2 accepts modular transparent PNG layers while retaining Run 7A.1 geometric fallback. Artwork
replacement must not require gameplay code changes. Bloom's pending import contract is documented in
`BLOOM_SPRITE_IMPORT.md`.

## Static and layered Critters

Prepare a consistent canvas, transparent background, facing direction, baseline, and anchor point.
Layered appearance art must share identical dimensions and normalized pivots. Runtime order:

1. Shadow
2. Tail
3. Wings
4. Base body, head, and feet
5. Color overlay
6. Markings
7. Eyes
8. Mouth
9. Accessories

Appearance genome fields select logical layer IDs through `AppearanceResolver`. Ability genome
fields never select appearance assets. Missing combinations use deterministic class/body-rig
placeholders and never alter combat data. Curated variants may cross classes only when gene metadata
declares compatibility and the target body rig, shape, and required tags all accept them; body genes
remain class-locked.

`CritterSpriteModel` converts resolved logical assets into ordered layers. Genetics retain the
compatibility families `heavy`, `round`, and `agile`; body genes separately select one of six visual
rig presets: `stone`, `feral`, `verdant`, `tide`, `gale`, or `shade`. `SpriteRigCatalog` owns each
preset's normalized attachments, palette, style, layer order, and animation offsets. Shadow and mouth
are structural appearance layers; mouth never derives from ability genes. `CritterSpriteRig` reuses
GUI instances when genomes change and asks `AssetRegistry` for every logical asset. Missing images use
the selected class geometry. Full logical asset IDs appear only in the Studio preview inspector.

Real layers carry explicit canvas size, pivot, normalized render position, and normalized render size
through the asset manifest. A registered image hides only its matching geometric layer; unresolved
eyes, mouth, tail, accessories, or other parts continue using safe fallback independently.

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

`SpriteSheetPlayer.frameAt` provides deterministic frame selection for looped and finite clips.
`CritterSpriteRig.setSheetFrame` applies explicit rectangles. Production sheets should register under
`creature.animation.<rig>.<state>` and retain static layer assets as fallback.

States are `IDLE`, `ATTACK`, `HIT`, and `DEFEAT`. Attack and hit return to idle after completion;
defeat persists. Battle events map to animation commands in presentation code only.

AI-generated single illustrations are not assumed to contain valid animation frames or separable
layers. They require manual preparation and consistency review.

## Cards and interface art

Card illustrations need a shared aspect ratio, safe crop region, readable silhouette, and no baked
text. UI textures should tolerate scaling or use documented slicing metadata. Class and status
icons need legible shapes at small sizes.

## Intentionally absent

- Production sprite-sheet scheduler wiring
- Particle systems and visual effects
- Equipment-specific compositing beyond appearance accessories
- Approved Bloom PNG layers and Roblox asset IDs
- Production artwork or Roblox asset IDs
