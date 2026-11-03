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

Run 7E.3.1 gives `AppController` one `ProfileStateCoordinator` for collection, inventory, contract,
and egg DTOs. Profile revision is global; each resource also records request sequence and applied
revision. A lower revision or older same-revision completion cannot replace newer state. Higher
revisions invalidate older resource snapshots, and route entry refreshes invalid data before mounting.

## Routes

```text
MainMenu
├── CollectionScreen
│   └── CritterDetail
├── TeamBuilderScreen
├── InventoryScreen
│   └── EquipmentPanel
├── BreedingScreen
├── EggCollectionScreen
│   └── EggOffspringScreen
├── ContractsScreen
└── BattleScreen
Studio only: SpritePreviewScreen
```

All components use `mount(parent, props)` and return `update` plus `destroy`. Every event connection is
owned by its component and disconnected during destruction. Reinitializing app destroys previous
controller first.

## Player-data commands

Team and equipment mutations include `commandId`, `expectedRevision`, and a narrow payload. While a
request is pending, action buttons reject double clicks. Network retries reuse the same command ID.
Stale responses refresh authoritative DTOs and require user review rather than overwriting data.

Only one profile mutation may run client-side at once, including mutations sent through different
remotes. Network-uncertain retries preserve the complete original request and command ID; writes are
never retried automatically. Development traces contain request ID, operation, revisions, completion
order, and applied/ignored status, but never profile contents.

Contracts use the same controller-owned transport pattern through `ContractRequest`. The screen shows
available, active, completed, and claimed states; progress; accept/claim pending states; tagged errors;
duplicate-retry feedback; and the claimed placeholder Critter with a Collection link. Components never
provide battle results or reward-generation fields.

## Battle lifecycle

Entering Training Grounds mounts existing `BattleScreenController`. Battle restart remains local to
that controller. Main Menu destroys playback/UI state; later battle start uses current selected-team
snapshot. Permanent collection HP and genes never reference combat state.

## Responsive shell

Screens use scale-based major regions, scrollable lists, readable fixed-size labels, and 40–60 pixel
actions. Layout targets desktop and landscape mobile. Logical assets resolve through `AssetRegistry`;
missing creature and item art renders labeled placeholders.

## Layered Critter lifecycle

Battlefield rows and Critter handles reconcile by stable team/combatant ID. Snapshot updates reuse all
six `CritterSpriteRig` instances, preserving temporary animation state. Each rig owns its tween and
completion connection; `destroy` cancels and disconnects both. Collection detail uses the same rig.

Studio exposes a local sprite preview route. It compares all six class rigs, then clones a default
Verdant genome for body, eyes, tail, markings, and accessory swaps without writing profile state or
invoking remotes.

Collection detail renders the same class-specific rig and presents wrapped sections for Stats,
Appearance, Abilities, Equipment, and Restrictions. Presentation mapping converts internal gene and
ability identifiers to readable labels; raw identifiers remain confined to the Studio asset inspector.
