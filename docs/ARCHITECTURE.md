# Architecture

## Boundaries

### Shared domain

`src/shared` contains replicated definitions, immutable configuration, validation contracts, and
pure gameplay logic. Shared modules must not use GUI, DataStore, or server-only APIs.

### Server

`src/server` owns authoritative gameplay and persistent state. Battle commands, breeding,
inventories, equipment, and trades are accepted only after server validation. Client messages are
requests, never trusted state transitions.

### Client

`src/client` owns input, interface state, layered sprites, animation, and audio. It may predict
presentation but never chooses authoritative battle results.

## Dependency direction

Client and server may depend on shared modules. Shared modules must not depend on client or server
modules. Server and client must not require each other. Feature modules should expose a narrow
public module and keep implementation details local.

Client presentation adds another one-way boundary: authoritative snapshot-shaped data flows through
`BattlePresentationMapper`, then into UI props. Components emit local callbacks but never import
battle rules, networking, or persistence. `PlanningState` represents tentative client intent only.

Shared battle modules resolve sibling modules through a small `requireSibling` helper. The helper
uses Roblox instance paths at runtime and relative string requires under the Lune test runner, so
the same source remains pure and testable on Linux without changing production mappings.

## Server authority

Run 5 exposes one `ReplicatedStorage.Remotes.BattleRequest` `RemoteFunction`. Request kinds are
`START_BATTLE`, `COMMAND`, `REQUEST_SNAPSHOT`, and `RESTART_BATTLE`. Roblox supplies the authenticated
`Player.UserId`; request payloads never establish identity or ownership.

`BattleService` owns one in-memory session per player. It validates command envelopes through
`BattleCommandProcessor`, plans AI cards through the same command path, resolves committed plans
exactly once, and projects only viewer-safe state. Raw state, RNG state, opponent hands and plans,
and command receipts never enter replicated snapshots. Disconnect removes the session. Explicit
transport rate limiting remains future work.

## Persistent data

Run 6A profiles use explicit schema versions, migration hooks, bounded `UpdateAsync` retries, and
renewable session locks. Missing records may be created; failed, corrupt, future-version, or
concurrently owned records never fall back to writable defaults. Autosave, disconnect, and shutdown
release paths all verify the lock token. Persistent records remain separate from runtime battle
state.

`ProfileService` retains repository handles server-side and projects detached DTOs. Training Grounds
loads the selected owned team through `TrainingBattleInputAdapter`; `BattleFactory` then snapshots
base stats and genomes into combatants. Battle mutation cannot reach cached ownership records.

Run 6B adds one serialized mutation boundary per loaded profile. Inventory, equipment, and team
services mutate a cloned candidate through `ProfileService.UpdateProfile`. Repository validation and
locked persistence complete before the candidate replaces cached state. Mutations racing autosave or
another command wait on the same writer lock.

`PlayerDataRequest` exposes only sanitized reads, team selection, equip, and unequip commands.
Authenticated `Player.UserId` supplies ownership. Item grants and removals remain server-only; client
payloads never contain authoritative item records.

Run 6C routes this remote through `PlayerDataService`. Reads return detached collection or inventory
DTOs. Mutations require a bounded command ID and expected profile revision. Duplicate receipt lookup
precedes stale-revision validation; conflicting command-ID reuse fails. Accepted team changes
invalidate only the active battle snapshot. Session-memory receipts are bounded and cleared on
disconnect.

Run 7A keeps registries, validators, and resolvers under `Shared/Genetics`; these modules are pure and
replicated for presentation. `Server/Genetics/InheritanceEngine` alone generates offspring genomes.
No remote accepts offspring genes. It consumes explicit `PARK_MILLER_V1` state, records every source
selection, uses bounded deterministic fallback, and defaults mutation off. Battle construction
resolves four ability genes before creating two physical cards per ability, preserving 24-card teams.
Curated cross-class genes still resolve through the source Critter's class and trusted registry/card
metadata; founder genomes are limited to Studio fixtures and Training Grounds opponents.

Run 7E.3 adds `ContractRequest` and a server-owned `ContractService`. Clients may list, accept, inspect,
and claim contracts, but cannot submit battle outcomes, seeds, genes, classes, reward IDs, or
completion evidence. `BattleService` alone sends authenticated Training Grounds completion evidence.
The contract is marked complete only after `ProfileService.UpdateProfile` persists the winning battle
ID. Claiming creates the Critter, marks the entitlement claimed, and writes a durable redemption in
one profile mutation.

Claimed display history may be pruned at bounded capacity, but redemption records keyed by contract
instance survive that pruning. These records return the original Critter for all later retries and
prevent a second grant. New contracts stop at the redemption capacity rather than deleting lifetime
idempotency evidence.

Failed completion callbacks remain pending in the active in-memory battle session and retry before
restart or another start. This prevents acknowledgement before persistence, but does not recover a
callback across server-process crash. A crash after battle resolution and before the profile write can
lose that completion. Player removal also performs only one final flush before discarding the session,
so a simultaneous write outage has the same limitation. Smallest safe follow-up is a durable
battle-completion outbox keyed by battle ID, written before terminal success is acknowledged and
consumed idempotently by `ContractService`; durable battle sessions/checkpoints remain future work.

## Domain contracts

`Types/Domain.luau` separates three data lifetimes:

- Static definitions describe authored Critters and cards.
- Persistent records describe owned Critter identity and independent genomes.
- Temporary battle records describe teams, combatants, commands, events, and round state.

Pure modules under `Validation` and `Battle` accept data and return new results without mutating
callers. They intentionally avoid Roblox services, networking, persistence, and hidden global
state. This permits deterministic Lune tests on Linux and reuse under Roblox.

Validators establish structural trust boundaries but do not authorize remote requests. Server code
loads authoritative state, enforces ownership, phase, stale-version, and replay rules, and ignores
client-provided results.

Run 4A adds pure battle construction/planning under `Shared/Battle`. Authoritative command receipts
and sanitized projections remain under `Server/Services`. Authenticated user identity enters command
processing separately from untrusted envelopes. Raw battle state never becomes a client snapshot.

## Run 4B resolution modules

`Shared/Battle/RoundResolver` is the public resolution entry point. It orchestrates smaller pure
modules, each with one responsibility:

- `Initiative`: deterministic action order and initiative snapshots.
- `TargetResolver`: targeting rules, retargeting, and skipped effects.
- `ClassAdvantage`: the six-class advantage ring.
- `DamageCalculator`: documented damage pipeline and shield absorption.
- `CardEffectResolver`: ordered card effect execution, healing, shields, and status application.
- `StatusEffects`: status stacking, effective stats, poison ticks, and expiry.
- `RoundTransition`: discard, energy, draw, plan reset, and round advancement.
- `BattleEvents`: deterministic event factory and stable event IDs.
- `DeepClone`: input isolation for resolved state.
- `CombatConstants`: replay-breaking tuning values.

`resolveRound(state, dependencies)` returns `{ ok = true, value = { state, events, stateVersion,
matchOutcome } }` or a structured tagged failure. The returned state is a deep copy; the input state,
plans, and static card definitions are never mutated. The caller supplies card definitions and may
override deck, economy, shuffle, and draw-count dependencies for tests.

One atomic call owns the whole lifecycle:

```text
COMMITTED -> RESOLVING -> ROUND_END -> PLANNING
COMMITTED -> RESOLVING -> ROUND_END -> COMPLETED
```

Intermediate phases exist only inside the call. Duplicate resolution is rejected by the
`COMMITTED` phase check and the `lastResolvedRound` guard.

Shield preparation is an internal stage at the beginning of `resolveRound`, not a network command or
new battle phase. Resolution clones committed state, indexes snapshotted queues, validates shield card
ownership and current targets, then applies shields in team/source/queue/effect/target order. Only
after every eligible shield emits `SHIELD_PREPARED` does resolution calculate and emit initiative.
Ordinary card execution skips shield effects, preventing mixed cards from applying them twice while
retaining the existing one-commit, one-consumption lifecycle.

## Determinism

Battle state records separate versioned `PARK_MILLER_V1` stream states for deck operations and
critical hits. Deck shuffles consume only `rng`; eligible direct-damage hits consume only
`criticalRng`. Production critical seeds derive from server-only GUID material and are never accepted
from clients. `BattleProjector` explicitly omits both RNG states and all future rolls. Initiative
ordering contains no randomness: effective Speed descending, current HP ascending, Skill descending,
Morale descending, then combatant identifier. Resolution creates one initiative snapshot after
commitment; in-progress Speed changes do not reorder that snapshot.

Preparation ordering contains no Speed or RNG input. Shield-only rounds advance neither deck nor
critical RNG. Existing phase and resolved-round guards prevent preparation from being reapplied to an
already-resolved state.

Combatant and team traversal always use explicit sort keys: team index, battlefield slot, then
identifier. Event IDs derive only from battle ID and a monotonic sequence. No wall clock, table hash
order, or uncontrolled RNG call enters the event stream. Identical state, plans, definitions, deck
RNG state, and critical RNG state therefore produce identical state and events. Actual critical
outcomes are recorded in `DAMAGE_APPLIED`; client commands carrying critical outcomes are rejected.

Inheritance uses the same explicit RNG contract. Thirty-six child positions consume a fair parent
draw plus a `75/20/5` allele draw each. Disabled mutation therefore consumes exactly 72 draws. No
hash traversal, global randomness, or retry loop affects offspring.

## Run 5 presentation flow

`BattleProjector` derives shield totals, effective Speed, reserved energy, initiative, status state,
and outcome while preserving hidden information. `BattlePresentationMapper` converts that snapshot
to UI props. On resolution, transport returns a committed pre-resolution snapshot, ordered events,
and final snapshot. Pure `BattlePlayback` applies each event in order; final HP and outcome are not
shown before their events. Playback epochs cancel stale work during restart or controller teardown.
