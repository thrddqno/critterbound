# UI Architecture

Run 3 provides a plain Studio-only battle shell. It demonstrates data flow and component ownership;
it does not submit commands, resolve combat, or represent authoritative state.

## Data flow

```text
Studio bootstrap
  -> MockBattleSession
  -> BattlePresentationMapper
  -> BattleScreenController
  -> BattleScreen component tree
  -> local callback
  -> PlanningState
  -> component update
```

Future server snapshots replace `MockBattleSession`. Mapper and components remain unchanged.
Opponent private plans must never enter a client snapshot during planning.

## Component hierarchy

```text
BattleScreen
├── BattlePhaseIndicator
├── EnergyCounter
├── InitiativeTimeline
├── BattlefieldView
│   └── 6 x CritterView
│       ├── PlaceholderRenderer
│       └── CritterHealthBar
├── CardQueue
├── CardHand
│   └── CardView
├── CommitButton
└── ResetButton
```

Components use `mount(parent, props)` and return handles with `update(props)` and `destroy()`.
Parents own child handles. Components receive presentation data, asset descriptors, and callbacks;
they do not access server services or mutate battle state.

## Presentation boundary

`BattlePresentationMapper` converts a future authoritative snapshot into client-owned view data. It
resolves stable references, orders viewer team first, preserves hand order, and preserves supplied
initiative order. It never calculates initiative or combat outcomes.

Shield values remain an explicit snapshot projection because Run 2 has not defined shield gameplay
semantics. Missing references return structured errors instead of partially rendering unsafe data.

## Local planning

`PlanningState` is immutable local intent. It supports queueing unique card instances, removal,
energy preview, commit lock, and reset. These checks improve interaction only. Future server command
validation remains authoritative.

Run 3 mounts the shell only when `RunService:IsStudio()` is true. No render loop, animation
scheduler, networking, or global store is present.

## Stabilized layout

Run 3.1 adds explicit bounded regions for cards and Critters, visible Player/Enemy identity,
scrollable initiative and hand rows, and a compact queue grouped by source combatant ID. Initiative
display preserves supplied authoritative order. Queue grouping is a pure presentation transform and
does not change local planning intent.

`BattleScreen` applies desktop and compact-landscape metrics from viewport size. Short landscape
viewports use vertical screen scrolling rather than shrinking text below readable sizes. Resize
updates layout metrics without replacing planning state, and controller startup destroys any prior
screen handle before mounting another.
