# Architecture

## Boundaries

### Shared domain

`src/shared` contains replicated definitions, immutable configuration, validation contracts, and
future pure gameplay logic. Shared modules must not use GUI, DataStore, or server-only APIs.

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

## Server authority

Future remote requests require schema checks, ownership checks, state checks, and rate limits.
Server-generated events become the source of truth. Secrets and private profile data never enter
`ReplicatedStorage`.

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

## Determinism

Battle state records a seed and `PARK_MILLER_V1` stream state. Random operations use this explicit,
versioned stream rather than `math.random`. Initiative ordering contains no randomness: Speed descending,
alternating team priority by round, slot ascending, then combatant identifier. Resolution creates
one initiative snapshot after commitment; in-progress Speed changes do not reorder that snapshot.
