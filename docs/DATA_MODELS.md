# Data Models

Run 5 uses the combat contracts in a versioned request protocol and sanitized snapshot projection.
It still does not define profile storage formats or production persistence.

## Static definitions

`CritterDefinition` identifies class, display name, base stats, and four available ability IDs.
`CardDefinition` identifies class, ability reference, energy cost, targeting rule, and optional
ordered effects. Definitions are authored game data and contain no player ownership.

`CritterStats` contains `maxHealth`, `attack`, `defense`, and `speed`, plus optional `skill` and
`resolve`. Values must be finite and non-negative; `maxHealth` must be positive. `skill` and
`resolve` break initiative ties and default to zero when absent. Other caps, rounding, and modifier
formulas are documented in `COMBAT_RULES.md`.

`CardDefinition.targetingRule` supports `SELF`, `ALLY`, `ENEMY`, `ANY`, `FRONT_ENEMY`,
`ALL_ALLIES`, and `ALL_ENEMIES`. `SELF`, `ENEMY`, `FRONT_ENEMY`, `ALL_ALLIES`, and `ALL_ENEMIES`
are server-derived and require an empty client target list. `ALLY` and `ANY` require one target.

`CardDefinition.effects` is an optional ordered `{ CardEffect }` array:

```text
CardEffect = {
  kind: "DAMAGE" | "HEAL" | "SHIELD" | "STATUS",
  amount: number?,
  statusId: string?,
  magnitude: number?,
  duration: number?,
}
```

Effects execute in authored order. Only fields relevant to `kind` are read. Missing effects make a
legal no-op card. Validators bound the array, known kinds, amounts, status identifiers, magnitudes,
and durations.

## Persistent creature data

`CritterInstance` contains owned identity, definition reference, owner user ID, and two independent
genomes:

- `AppearanceGenome`: species, body variant, palette, and pattern identifiers.
- `AbilityGenome`: exactly four unique combat ability identifiers.

Changing appearance data cannot modify ability data. No inheritance, breeding, mutation, level,
equipment, or persistence behavior exists through Run 5.

`CardInstance` identifies one physical deck/hand card and its source Critter instance. It references
a static card definition rather than duplicating card rules. Defeat removes sourced card IDs from
active zones but retains these immutable records for event and replay references.

## Temporary battle data

`BattleTeam` records one owner, optional team index, and exactly three combatant IDs.
`BattleCombatant` snapshots battle identity, team, slot, class, abilities, stats, current health,
status effects, and optional shields. Creature IDs and team slots must be unique within a team.

`StatusEffect` is typed battle state:

```text
StatusEffect = {
  id: string,
  statusId: string,
  sourceCombatantId: string,
  targetCombatantId: string,
  magnitude: number,
  duration: number,
  stackCount: number,
  appliedRound: number,
  expiresAtRound: number,
}
```

`BattleShield` is an ordered shield record:

```text
BattleShield = {
  id: string,
  sourceCombatantId: string,
  amount: number,
  expiresAtRound: number,
}
```

Shields stack in grant order and expire at the end of their grant round. Status and shield arrays are
runtime battle state, not persisted creature data.

`BattleState` records phase, round, deterministic RNG state, shared state version, last emitted event
sequence, last resolved round, teams, combatants, physical cards, and per-team private zones/plans.
`eventVersion` and `lastResolvedRound` make event replay and duplicate-resolution checks possible.
Runtime battle state is not a persisted profile.

`BattleCommandEnvelope` supports queue, remove, reorder, clear, and commit requests. It carries
shared and private expected versions plus an idempotent command ID. Authenticated ownership is
supplied separately by server session, never trusted from payload.

## Resolution result

`RoundResolver.resolveRound` returns a tagged result. Success contains:

```text
BattleResolutionResult = {
  state: BattleState,
  events: { BattleEvent },
  stateVersion: number,
  matchOutcome: BattleOutcome?,
}

BattleOutcome = {
  isDraw: boolean,
  winnerTeamId: string?,
  reason: string,
}
```

Failure uses the standard `{ ok = false, errors = { DomainError } }` shape. The returned state is a
deep copy. The input state and static definitions are never mutated.

## Network requests and snapshots

`BattleRequest` accepts `{ kind, ... }` tables. `COMMAND` carries a versioned
`BattleCommandEnvelope`; restart carries an idempotent `requestId`. Responses use the same tagged
success/failure shape as domain modules. Resolution responses contain:

```text
{
  preSnapshot: BattleSnapshot,
  events: { BattleEvent },
  finalSnapshot: BattleSnapshot,
  matchOutcome: BattleOutcome?,
}
```

`BattleSnapshot` contains public combat state plus viewer-owned hand, queue, energy, reserved energy,
and plan version. It also projects shield totals, effective Speed, latest initiative, and outcome.
Opponent hand IDs, queued cards during planning, draw order, RNG state, and command receipts are
omitted.

## Battle events

`BattleEvent` is an ordered, serializable output envelope:

```text
BattleEvent = {
  id: string,
  battleId: string,
  sequence: number,
  roundNumber: number,
  kind: string,
  sourceCombatantId: string?,
  targetCombatantIds: { string },
  payload: { [string]: any }?,
}
```

Event IDs use `evt:<battleId>:<sequence>`. Sequence starts after the state's stored `eventVersion`, so
events remain unique across rounds. No event contains a wall-clock timestamp or uncontrolled random
value. Payload fields are documented with their event kinds in `COMBAT_RULES.md`; payloads are plain
serializable tables and may grow compatibly within a schema version.

Event kinds emitted by Run 4B:

- `INITIATIVE_DETERMINED`
- `CARD_PLAYED`
- `TARGET_SELECTED`
- `DAMAGE_APPLIED`
- `SHIELD_GRANTED`
- `SHIELD_ABSORBED`
- `HEAL_APPLIED`
- `STATUS_APPLIED`
- `STATUS_TICKED`
- `STATUS_EXPIRED`
- `CRITTER_DEFEATED`
- `ACTION_CANCELED`
- `ROUND_COMPLETED`
- `MATCH_COMPLETED`

## Validation results

Pure validators return `DomainResult`-compatible tagged results:

- Success: `{ ok = true, value = ... }`
- Failure: `{ ok = false, errors = { DomainError } }`

Each error has stable `code`, human-readable `message`, and optional `path`. Callers must branch on
codes, not messages. Validators neither coerce nor mutate input.

Run 4B validation adds:

- `INVALID_CARD_EFFECTS`, `INVALID_CARD_EFFECT`, `INVALID_EFFECT_KIND`
- `INVALID_EFFECT_AMOUNT`, `INVALID_STATUS_ID`, `INVALID_STATUS_MAGNITUDE`,
  `INVALID_STATUS_DURATION`
- `INVALID_TARGET_COUNT` for automatic and manual targeting rules

## Versioning

Authored static and persistent schemas currently use version `1`. Runtime `BattleState` uses
`schemaVersion = 2`; Run 4B added optional battle fields without changing the meaning of existing
ones. Network protocol versioning remains separate because a data migration and protocol change are
not equivalent. Future persisted schema changes require explicit migrations.
