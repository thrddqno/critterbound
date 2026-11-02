# Architecture

## Boundaries

### Shared domain

`src/shared` contains replicated definitions, immutable configuration, validation contracts, and
pure gameplay logic. Shared modules must not use GUI, DataStore, or server-only APIs.

### Server

`src/server` owns authoritative gameplay and persistent state. Future battle commands, breeding,
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

Future remote requests require schema checks, ownership checks, state checks, and rate limits.
Server-generated events become the source of truth. Secrets and private profile data never enter
`ReplicatedStorage`.

Run 4B resolution is deliberately not wired to remote transport yet. A server caller must load
authoritative state and card definitions, call `RoundResolver.resolveRound`, persist the returned
state, append the returned events, and only then project or broadcast sanitized data. The resolver
itself performs no I/O and trusts only its caller-supplied state.

## Persistent data

Profiles will use explicit schema versions, migrations, bounded writes, and session-safe ownership.
DataStore failures must be expected and recoverable. Persistent records remain separate from
runtime battle state. No persistence exists in Run 1.

## Domain contracts

`Types/Domain.luau` separates three data lifetimes:

- Static definitions describe authored Critters and cards.
- Persistent records describe owned Critter identity and independent genomes.
- Temporary battle records describe teams, combatants, commands, events, and round state.

Pure modules under `Validation` and `Battle` accept data and return new results without mutating
callers. They intentionally avoid Roblox services, networking, persistence, and hidden global
state. This permits deterministic Lune tests on Linux and reuse under Roblox.

Validators establish structural trust boundaries but do not authorize remote requests. Future
server code must still load authoritative state, enforce phase and replay rules, rate-limit
requests, and ignore client-provided results.

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

## Determinism

Battle state records a seed and `PARK_MILLER_V1` stream state. Random operations use this explicit,
versioned stream rather than `math.random`. Initiative ordering contains no randomness: effective
Speed descending, current HP ascending, Skill descending, Resolve descending, then combatant
identifier. Resolution creates one initiative snapshot after commitment; in-progress Speed changes do
not reorder that snapshot.

Combatant and team traversal always use explicit sort keys: team index, battlefield slot, then
identifier. Event IDs derive only from battle ID and a monotonic sequence. No wall clock, table hash
order, or uncontrolled RNG call enters the event stream. Identical state, plans, definitions, and RNG
state therefore produce identical state and events.

## Compatibility notes

Run 4A planning, projection, and Studio mock presentation continue to operate unchanged. The
projector does not yet derive shield totals or initiative previews from Run 4B state, and the client
does not yet render resolved events. That wiring belongs to the transport and presentation
integration run.
