# UI Architecture

Run 5 retains the component shell and wires it to authoritative Training Grounds snapshots,
commands, ordered event playback, terminal results, and restart.

## Data flow

```text
Client bootstrap
  -> BattleRequest
  -> sanitized server snapshot
  -> BattlePresentationMapper
  -> BattleScreenController
  -> BattleScreen component tree
  -> command callback
  -> authoritative response
  -> BattlePlayback events
  -> final snapshot reconciliation
```

Opponent private plans never enter a client snapshot during planning.

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
├── ResetButton
└── BattleResultOverlay
```

Components use `mount(parent, props)` and return handles with `update(props)` and `destroy()`.
Parents own child handles. Components receive presentation data, asset descriptors, and callbacks;
they do not access server services or mutate battle state.

## Presentation boundary

`BattlePresentationMapper` converts an authoritative snapshot into client-owned view data. It
resolves stable references, orders viewer team first, preserves hand order, and preserves supplied
initiative order. It never calculates initiative or combat outcomes.

Shield totals, effective Speed, statuses, reserved energy, initiative, and outcome are explicit
server projections. Missing references return structured errors instead of partially rendering data.

## Local planning

Target selection is client interaction state, but chosen IDs are validated by the server. Queue,
remove, reorder, clear, and commit responses replace local planning state with authoritative
snapshots. Command input locks while a request is pending or playback runs. Restart increments a playback
epoch so delayed events cannot overwrite the fresh battle.

## Stabilized layout

Run 3.1 adds explicit bounded regions for cards and Critters, visible Player/Enemy identity,
scrollable initiative and hand rows, and a compact queue grouped by source combatant ID. Initiative
display preserves supplied authoritative order. Queue grouping is a pure presentation transform and
does not change local planning intent.

`BattleScreen` applies desktop and compact-landscape metrics from viewport size. Short landscape
viewports use vertical screen scrolling rather than shrinking text below readable sizes. Resize
updates layout metrics without replacing planning state, and controller startup destroys any prior
screen handle before mounting another.
