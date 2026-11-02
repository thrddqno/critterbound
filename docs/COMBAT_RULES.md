# Combat Rules

This document records intended rules, not a Run 1 implementation.

## Round flow

1. Both players enter a private planning phase.
2. Each player may queue multiple cards for individual Critters, constrained by hand and energy.
3. Both plans commit without revealing or resolving one player first.
4. Server validates both plans against authoritative state.
5. Server creates one actionable initiative entry for each Critter with queued cards.
6. Critters execute full queues sequentially in Speed-based order.
7. Server emits ordered battle events, then advances round state.

Planning order is not attack execution order. Clicking a card earlier does not grant an earlier
attack. Simultaneous commitment closes planning; Speed and future combat rules determine execution.

## Starting design values

- Three Critters per team
- 3 initial energy; +2 each later round
- 6 starting cards; +3 each later round
- 24-card team deck
- Four ability definitions per Critter, two copies each

Energy and unused cards are intended to carry between rounds. Exact validation, defeat, targeting,
status, and card-resolution rules remain future work.

## Battle phases

Permitted transitions are deliberately linear:

```text
CREATED -> ROUND_START -> PLANNING -> COMMITTED -> RESOLVING -> ROUND_END
                      ROUND_END -> ROUND_START
                      ROUND_END -> COMPLETED
```

No other transition is legal. `COMPLETED` is terminal. Surrender and cancellation paths are not
modeled yet. Phase contracts validate transitions but do not mutate `BattleState`.

## Initiative

Initiative uses a total deterministic order:

1. Higher Speed first.
2. Equal Speed: team 1 first on odd rounds, team 2 first on even rounds.
3. Same team: lower battlefield slot first.
4. Final fallback: combatant identifier lexicographically ascending.

Team index must be assigned before planning and never depend on command arrival order. Only
Critters with queued cards enter the actionable list. Card order inside each Critter queue remains
unchanged. Initiative is snapshotted after both plans commit; later Speed effects cannot reorder an
in-progress resolution sequence.

## Planning validation

An empty plan is legal. A command may contain at most 24 cards and is further constrained by cards
actually held and available energy. Card instance identifiers may appear once per command.
Per-Critter `queueIndex` values must be contiguous from one. Current target rules require exactly
one target and support `SELF`, `ALLY`, `ENEMY`, and `ANY`.

## Unresolved rules

- Surrender and cancellation transitions
- Area and multi-target cards
- Defeated-target legality and automatic retargeting
- Status stacking, duration timing, and dispels
- Deck exhaustion, discard, reshuffle, and replacement draws
- Versioned deterministic RNG algorithm and stream allocation
- Stat caps, rounding, and fractional modifiers
