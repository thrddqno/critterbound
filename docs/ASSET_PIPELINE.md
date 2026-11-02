# Asset Pipeline

## Logical identifiers

UI code references stable logical IDs rather than Roblox asset IDs:

- `creature.stone.default`
- `creature.gale.default`
- `card.stone.rune_guard`
- `arena.training.background`
- `icon.class.verdant`

Identifiers remain stable when uploaded assets are replaced. Categories cover creature bases,
appearance layers, animation sheets, cards, class/equipment/status icons, battlefields, UI textures,
and effects.

## Registration

`src/client/Assets/AssetCatalog.luau` is immutable allowlisted catalog. Add an authored entry after
upload and moderation:

```luau
{
	id = "card.stone.rune_guard",
	category = "CARD_ART",
	image = "rbxassetid://<ROBLOX_ASSET_ID>",
}
```

Replace `<ROBLOX_ASSET_ID>` with digits before committing. Executable entries accept only
`rbxassetid://` followed by digits. Snapshot data cannot inject image URLs.

## Missing assets

Entries may omit `image` while art is pending. Registered but empty entries render a labeled
placeholder. Unknown IDs and invalid fallback chains resolve to a generic missing descriptor that
contains requested logical ID. Components never receive `nil` from normal resolution.

Future fallback art can be registered once and referenced with `fallbackId`; component code does
not change.

## Intake checklist

1. Record source, creator, license, generation workflow, and human review.
2. Verify originality and Roblox policy compliance.
3. Export required dimensions and transparency.
4. Upload through approved Roblox ownership context.
5. Confirm moderation and intended permissions.
6. Register logical ID and numeric Roblox asset URI.
7. Test fallback, aspect ratio, and common viewport sizes in Studio.
