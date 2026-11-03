# UI Architecture

Run 6C uses one application lifecycle owner. Client bootstrap mounts `AppController`; it waits for a
sanitized collection DTO, then enters Main Menu instead of automatically starting battle.

## Data flow

```text
Client bootstrap
  -> AppController
  -> PlayerDataRequest v2
  -> sanitized collection/inventory DTO
  -> CollectionPresentation
  -> active screen component
  -> callback
  -> revision-checked command
  -> refreshed authoritative DTOs
```

`NavigationController` owns only route state. `AppController` owns networking, cached revisions,
pending commands, screen teardown, and battle controller lifecycle. Components never invoke remotes.

## Routes

```text
MainMenu
├── CollectionScreen
│   └── CritterDetail
├── TeamBuilderScreen
├── InventoryScreen
│   └── EquipmentPanel
└── BattleScreen
```

All components use `mount(parent, props)` and return `update` plus `destroy`. Every event connection is
owned by its component and disconnected during destruction. Reinitializing app destroys previous
controller first.

## Player-data commands

Team and equipment mutations include `commandId`, `expectedRevision`, and a narrow payload. While a
request is pending, action buttons reject double clicks. Network retries reuse the same command ID.
Stale responses refresh authoritative DTOs and require user review rather than overwriting data.

## Battle lifecycle

Entering Training Grounds mounts existing `BattleScreenController`. Battle restart remains local to
that controller. Main Menu destroys playback/UI state; later battle start uses current selected-team
snapshot. Permanent collection HP and genes never reference combat state.

## Responsive shell

Screens use scale-based major regions, scrollable lists, readable fixed-size labels, and 40–60 pixel
actions. Layout targets desktop and landscape mobile. Logical assets resolve through `AssetRegistry`;
missing creature and item art renders labeled placeholders.
