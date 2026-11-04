# Data Models

Run 7A adds versioned genetic loci while retaining inventory, equipment, mutable teams, and battle
contracts from earlier runs.

## Static definitions

`CritterDefinition` identifies class, display name, base stats, and four available ability IDs.
`CardDefinition` identifies class, ability reference, energy cost, targeting rule, and optional
ordered effects. Definitions are authored game data and contain no player ownership.

`CritterStats` contains required non-negative `health`, `speed`, `skill`, and `morale`. Battle stats
add server-derived `maxHealth = 150 + (4 * health)`. Skill participates in qualifying three- or
four-card damage combos; Skill and Morale also break initiative ties. Other caps, rounding, and
modifier formulas are documented in `COMBAT_RULES.md`.

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

- `AppearanceGenome` schema 2: `body`, `eyes`, `wings`, `tail`, `color`, `markings`, and
  `accessories` loci.
- `AbilityGenome` schema 2: `mouth`, `horn`, `back`, `tail`, and `traits` loci.

Every locus contains exact `D`, `R1`, and `R2` logical gene IDs. Resolvers derive phenotype data;
resolved output is not persisted. Appearance resolution returns body-rig family, logical base/layer
IDs, ordering, anchor/pivot keys, and attachment keys. Ability resolution requires exactly four
unique cards; native-class cards are always accepted, while cross-class cards require explicit gene
compatibility plus class ability-pool membership. Neutral trait genes produce no card. Curated
`founderGenomes` remain fixture/opponent data and never replace canonical starter genomes.

Changing appearance data cannot modify ability data. Each owned Critter also snapshots base stats,
acquisition metadata, tradability, breeding flags, and equipment ID references. Run 6A stores these
fields but implements no breeding, trading, equipment, inventory, or reward behavior.

## Player profile

`PlayerProfile` schema version 6 stores `userId`, revision, creation/update timestamps,
`starterGrantVersion`, `ownedCritters`, and an ordered `selectedTeam` of exactly three unique owned
IDs. Schema 6 retains the breeding operation receipts added by Run 7E.1 and the
`acquisitionOperationsById` plus `acquisitionOperationOrder` for idempotent Run 7E.2 grants. Each
acquisition receipt records the command ID, generated Critter ID, pool ID/version, seed, optional
class, source, and grant metadata. Receipts cap at 128 while the acquisition service retains 64 by
default. Progression remains an empty placeholder.

Schema 6 adds contract state: ordered contract instances, reward entitlements, and durable
redemptions. A `TRAINING_VICTORY` instance records definition ID/version, owner, `ACTIVE`, `COMPLETED`,
or `CLAIMED` status, progress, acceptance/completion/claim timestamps, entitlement ID, baseline battle
ID, and completed battle ID. Its entitlement stores the server seed and `COMMON_FOUNDERS` pool
version. On claim, the awarded Critter stores the actual generated genomes; the entitlement and
redemption store the immutable awarded Critter identity and class.

Contract instances and entitlements cap at 128 and may prune claimed display history. Redemptions cap
at 2048 and are never pruned; reaching that cap disables new acceptance. Thus retries after display
history pruning still resolve to the original owned Critter without rerolling or duplicating it.

Run 7E.2 acquisition is server-only. `CritterAcquisitionService.PreviewPool` and
`GenerateCandidate` are structural/internal APIs; no client remote exposes generation or granting.
`GrantCritter` requires a loaded, writable profile and an authorized server context, validates the
pool, seed, class, and genomes, then applies exactly one atomic `ProfileService.UpdateProfile`
mutation. The mutation re-checks the command ID and Critter ID, so a retry returns the existing
Critter rather than creating a duplicate, and a save failure leaves no partial grant. Persisted
`acquisition.source` is derived from the pool (`ACQUISITION.<POOL_ID>`), never from client input.

Acquired Critters use `CritterInstanceFactory`: immutable server-generated ID, catalog class and
base stats, valid appearance/ability genomes, generation `0`, empty equipment, no parents,
`successfulBreedCount = 0`, `breedable = true`, and explicit `tradable = false`. Starter metadata is
never reused and ownership is keyed by generated ID, not display name.

Inventory schema version 2 contains:

- `stacksByDefinitionId`: positive quantities for stackable definitions.
- `uniqueItemsById`: server-generated immutable item identities, ownership, acquisition metadata,
  and equipment state.
- `operationsById` plus `operationOrder`: at most 128 idempotent grant receipts.

`ItemDefinition` is static registry data: display name, category, rarity, stack behavior, maximum
stack, equipment slot, modifiers, and tradeability. Static definitions are never copied into profile
records. Fixture categories are material, catalyst, consumable, equipment, and collectible.

Migration `2 → 3` recognizes legacy starter tuples only, replaces only Critter schema/genome fields,
and preserves IDs, owners, stats, equipment, inventory, selected-team order, and revision. Unknown
legacy combinations fail closed without writing the DataStore record. Migration uses no RNG.
Migration `4 → 5` only adds empty acquisition operation tables; existing breeding receipts, Critters,
inventory, equipment, and team data are preserved.
Migration `5 → 6` adds empty contract, entitlement, and redemption tables without changing existing
Critters, eggs, breeding/acquisition receipts, inventory, equipment, or selected-team data.

Each Critter supports zero or one equipment item. A unique equipment item stores
`equippedCritterId`; the Critter stores the same item ID in `equipmentIds`. Validation requires both
references to agree. Equipping an occupied slot atomically makes the old item available and equips
the new item. Equipment modifiers are inert data in Run 6B.

Run 6C collection DTO version 1 contains profile revision, ordered selected IDs, and sanitized owned
Critter presentation records. Equipment is embedded as a display summary. Owner IDs, raw equipment
references, inventory operation receipts, session locks, and DataStore metadata are omitted.

Inventory DTO version 1 contains revision, stack summaries, and unique-item summaries. Static item
descriptions come from `ItemRegistry`; authoritative profile records never store presentation text.

Static `CritterDefinition` records are authored content and are never stored in a profile.
`CritterInstance` records are permanent ownership data. `BattleCombatant` records are disposable
snapshots. Current HP, shields, statuses, physical cards, and battle plans never write back to owned
Critters.

The DataStore value wraps the profile with `recordVersion` and an optional session lock containing a
server job ID, opaque token, and lease expiry. Lock metadata is operational server data and never
appears in profile DTOs.

Profile mutations clone cached state, validate the full candidate, and save under the Run 6A session
lock. Cache replacement happens only after successful persistence. DataStore failure therefore
cannot expose or retain a partially applied inventory, equipment, or team mutation.

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

Shields stack in deterministic preparation order and expire at the end of their preparation round.
Status and shield arrays are runtime battle state, not persisted creature data.

`BattleState` records phase, round, separate deterministic deck and critical RNG states, shared state version, last emitted event
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

`ContractRequest` supports `GET_CONTRACTS`, `ACCEPT_CONTRACT`, `GET_CONTRACT_PROGRESS`, and
`CLAIM_CONTRACT_REWARD`. Mutations require command IDs and expected profile revisions. No request kind
accepts completion evidence or reward-generation inputs.

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
Opponent hand IDs, queued cards during planning, draw order, both RNG states, and command receipts are
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

Battle event kinds include:

- `INITIATIVE_DETERMINED`
- `CARD_PLAYED`
- `TARGET_SELECTED`
- `DAMAGE_APPLIED`
- `SHIELD_PREPARED`
- `SHIELD_GRANTED` (direct resolver compatibility)
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
`schemaVersion = 3`; Combat Run 3 adds the dedicated server-only `criticalRng` stream. Run 4B added optional battle fields without changing the meaning of existing
ones. Network protocol versioning remains separate because a data migration and protocol change are
not equivalent. Persisted schema changes require explicit sequential migrations. Unknown future
versions and corrupt records fail closed rather than being replaced by defaults.
