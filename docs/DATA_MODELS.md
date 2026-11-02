# Data Models

Foundation Run 2 defines contracts, not storage formats or battle resolution.

## Static definitions

`CritterDefinition` identifies class, display name, base stats, and four available ability IDs.
`CardDefinition` identifies class, ability reference, energy cost, and targeting rule. Definitions
are authored game data and contain no player ownership.

`CritterStats` currently contains `maxHealth`, `attack`, `defense`, and `speed`. Values must be
finite and non-negative; `maxHealth` must be positive. Final caps, rounding, and modifier formulas
remain unresolved.

## Persistent creature data

`CritterInstance` contains owned identity, definition reference, owner user ID, and two independent
genomes:

- `AppearanceGenome`: species, body variant, palette, and pattern identifiers.
- `AbilityGenome`: exactly four unique combat ability identifiers.

Changing appearance data cannot modify ability data. No inheritance, breeding, mutation, level,
equipment, or persistence behavior exists in Run 2.

`CardInstance` identifies one physical deck/hand card and its source Critter instance. It references
a static card definition rather than duplicating card rules.

## Temporary battle data

`BattleTeam` records one owner and exactly three combatant IDs. `BattleCombatant` snapshots battle
identity, team, slot, class, abilities, stats, health, and statuses. Creature IDs and team slots must
be unique within a team.

`BattleState` records phase, round, deterministic seed, teams, combatants, and per-team energy/hand
state. This is a future runtime state contract, not a persisted player profile.

`BattleCommand` currently supports `COMMIT_PLAN`. Each `QueuedCard` identifies card instance,
source combatant, target list, and per-Critter queue position. Commands express player intent;
future server code remains authoritative.

`BattleEvent` is an ordered output envelope. Event payload schemas remain deferred until resolution
rules exist.

## Validation results

Pure validators return `DomainResult`-compatible tagged results:

- Success: `{ ok = true, value = ... }`
- Failure: `{ ok = false, errors = { DomainError } }`

Each error has stable `code`, human-readable `message`, and optional `path`. Callers must branch on
codes, not messages. Validators neither coerce nor mutate input.

## Versioning

Current schemas use version `1`. Future persisted schema changes require explicit migrations.
Network protocol versioning remains separate because a data migration and protocol change are not
equivalent.
