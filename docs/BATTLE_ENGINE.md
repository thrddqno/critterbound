# Battle Planning Engine

Run 4A implements deterministic battle initialization and server-authoritative planning. Run 4B
executes cards and advances rounds; Run 5 integrates both through `BattleService`.

## Initialization

`BattleFactory.create` accepts two distinct-owner teams, three owned Critter instances per team,
static Critter/card definitions, and an explicit seed. Each Critter contributes two physical copies
of each of its four ability cards. Team IDs sort lexicographically into stable team indices.

Each 24-card deck is shuffled through `PARK_MILLER_V1`, then six cards are drawn. Card instance IDs
are deterministic battle-local identities. Changing algorithm, canonical deck order, or stream
allocation is replay-breaking.

RNG stream allocation is fixed: team 1 shuffle and opening draw complete before team 2 shuffle and
opening draw. `RngState` stores algorithm, current state, and draw count.

## Card zones and energy

Team state owns draw, hand, discard, queue, energy, and private plan version. Draws stop at ten cards;
excess cards stay in draw pile. Empty draw piles reshuffle discard through the explicit RNG stream.
Defeat retires every card whose authoritative `sourceCritterInstanceId` belongs to that Critter.
Retirement filters all active zones without deleting immutable card records or consuming RNG.

Planning reserves energy without reducing the pool. Commit validates again, deducts reserved cost,
and locks that team. Rejection leaves energy unchanged. Cards stay in hand and queue until Run 4B
resolves them; Run 4A never discards queued cards.

Round-one energy is three. Future round setup uses `min(unused + 2, 10)`, but Run 4A does not advance
rounds automatically.

## Simultaneous planning

Global phase remains `PLANNING` when only one team commits. Other team can continue planning. Phase
becomes `COMMITTED` only after both commits. Run 4A stops there.

Two versions prevent opponent-private changes from causing false stale requests:

- `stateVersion` changes for shared battle transitions.
- `planVersion` changes for accepted private team mutations.

Command envelopes carry both expected versions. Authenticated user ID is a trusted processor
argument; client-supplied `teamId` only selects a team and never proves ownership. Exact command
replays return stored receipts. Reusing a command ID with different content is rejected.

## Projection

`BattleProjector` is the future network boundary. During planning, a viewer receives own hand and
queue, public combatants, zone counts, and commitment status. Opponent hand IDs, opponent queue,
draw order, RNG state, and command receipts remain absent. Both queues reveal only after phase
reaches `COMMITTED`.

## Run 5 service

`BattleService` serializes commands per player session, invokes `BattleCommandProcessor.process`
with authenticated `Player.UserId`, sends deterministic AI requests through the same processor,
resolves both committed plans, and calls `BattleProjector.project`. Exact command replays return
stored receipts without resolving twice. Restart IDs are also idempotent. Player disconnect removes
the in-memory session. Raw `BattleState` and `processedCommandsById` are never replicated.

Production rate limiting, receipt pruning, and persistence remain future work.

Protocol version 3 makes `SELF` and `ENEMY` automatic target rules. Clients submit empty target lists;
the server resolves `ENEMY` to the living opponent with lowest effective Speed, then slot and ID.
