# Combat Rules

Run 4B implements server-authoritative round resolution as pure Luau. This document records the
implemented rules and the tuning assumptions that were not previously specified. It does not
describe client presentation, networking, persistence, or production artwork.

## Round flow

1. Both players enter a private planning phase.
2. Each player may queue multiple cards for individual Critters, constrained by hand and energy.
3. Both plans commit without revealing or resolving one player first.
4. Server validates both plans against authoritative state.
5. Server creates one actionable initiative entry for each living Critter with queued cards.
6. Critters execute full queues sequentially in initiative order.
7. After all actions, round-end poison ticks, knockouts, and status expiry are applied.
8. Server emits ordered battle events, then advances round state or completes the match.

Planning order is not attack execution order. Clicking a card earlier does not grant an earlier
attack. Simultaneous commitment closes planning; initiative and the rules below determine execution.

## Starting design values

- Three Critters per team
- 3 initial energy; +2 each later round
- 6 starting cards; +3 each later round
- 24-card team deck
- Four ability definitions per Critter, two copies each

Energy and unused cards carry between rounds. Energy caps at 10. Hands cap at 10; excess draws stay
in the draw pile. Empty draw piles reshuffle discard deterministically when another draw is needed.
Cards resolved during the round are discarded before the next draw, so they can be reshuffled and
drawn again when the draw pile is empty.

## Battle phases

Permitted transitions are deliberately linear:

```text
CREATED -> ROUND_START -> PLANNING -> COMMITTED -> RESOLVING -> ROUND_END
                      ROUND_END -> ROUND_START
                      ROUND_END -> COMPLETED
```

No other transition is legal. `COMPLETED` is terminal. A single `resolveRound` call moves the state
through `RESOLVING` and `ROUND_END` atomically, then leaves it in `PLANNING` for the next round or in
`COMPLETED` when the match ends. Intermediate phases are not exposed as separate server calls.

Resolution requires `phase == COMMITTED`, every team state to be committed, and
`lastResolvedRound < roundNumber`. These guards reject duplicate resolution.

## Initiative

Run 4B initiative uses a total deterministic order:

1. Higher effective Speed first.
2. Lower current HP first.
3. Higher `skill` first; missing `skill` counts as zero.
4. Higher `resolve` first; missing `resolve` counts as zero.
5. Combatant identifier lexicographically ascending.

Effective Speed includes active `SPEED_UP` and `SPEED_DOWN` statuses, clamped at zero. Only living
Critters with queued cards enter the actionable list. Card order inside each Critter queue remains
unchanged. Initiative is snapshotted before the first action; Speed changes during resolution affect
the next round, never the current queue. Defeated Critters lose all pending actions.

The legacy Run 2 team-alternating comparator remains available for its original tests but is not
used by `RoundResolver`.

## Planning validation

An empty plan is legal. A command may contain at most 24 cards and is further constrained by cards
actually held and available energy. Card instance identifiers may appear once per command.
Per-Critter `queueIndex` values must be contiguous from one.

Single-target rules require exactly one submitted target: `SELF`, `ALLY`, `ENEMY`, and `ANY`.
Server-derived rules require an empty client target list: `FRONT_ENEMY`, `ALL_ALLIES`, and
`ALL_ENEMIES`. The server derives their targets at resolution time.

Run 4A reserves energy while planning and deducts it on authoritative commit. Cards remain in hand
and queue until resolution. One committed team does not end planning for the other team.

## Card effects

`CardDefinition.effects` is an ordered array. Effects execute in authored order, and every effect on
one card shares the targets resolved once for that card. A card with no effects is a legal no-op.
Known effect kinds:

- `DAMAGE`: amount is base card damage.
- `HEAL`: amount is requested healing.
- `SHIELD`: amount is granted shield.
- `STATUS`: `statusId`, `magnitude`, and `duration` describe the applied status.

Card definitions are static and are never mutated by resolution.

## Targeting and retargeting

Targets are resolved against current living combatants before effects execute:

- `SELF`: the source Critter while alive.
- `ALLY`: the submitted living ally; otherwise the lowest-slot living ally other than the source.
- `ENEMY`: the submitted living enemy; otherwise the lowest-slot living enemy.
- `FRONT_ENEMY`: the lowest-slot living enemy; submitted targets are ignored.
- `ALL_ALLIES`: every living ally ordered by slot, including the source.
- `ALL_ENEMIES`: every living enemy ordered by slot.
- `ANY`: the submitted living target; otherwise the effect is skipped.

Slot ties are broken by combatant identifier. If no legal target exists, the effect is skipped but
the card still consumes its turn and is discarded. `TARGET_SELECTED` records whether retargeting or
skipping occurred.

## Damage pipeline

Damage is calculated in this fixed order:

1. Base card damage.
2. Class multiplier: `1.15` advantage, `0.85` disadvantage, `1.00` neutral.
3. Flat attack modifier: effective Attack minus base Attack. Missing modifiers count as zero.
4. Flat defense reduction: `floor(defense * 0.5)`.
5. Status vulnerability multiplier: `1.00` in Run 4B.
6. Floor once and clamp to at least zero.
7. Shield absorption in grant order.
8. HP damage clamped to remaining HP.

Effective Attack includes active `ATTACK_UP` and `ATTACK_DOWN` statuses, clamped at zero before the
modifier is derived. Negative final damage is impossible.

### Class ring

The six classes form a ring:

```text
Verdant -> Tide -> Feral -> Gale -> Shade -> Stone -> Verdant
```

A class is advantaged against the next two classes and disadvantaged against the previous two.
Self and the opposite class are neutral. Changing the ring or multipliers is replay-breaking.

## Shields

`BattleCombatant.shields` is an ordered array of `{ id, sourceCombatantId, amount, expiresAtRound }`.
Shields stack, absorb in grant order, and are removed when fully consumed. Ordinary shields expire
at the end of the round in which they are granted; they never carry to the next round. Damage
records both the pre-shield amount and the absorbed amount. Poison bypasses shields.

`SHIELD_ABSORBED` is emitted before `DAMAGE_APPLIED` when a shield consumes part of an attack.
`STATUS_EXPIRED` with `statusId = "SHIELD"` reports any remaining shield at round end. A shield
fully consumed during the round produces no expiry event.

## Healing

Healing clamps to `maxHealth` and reports the requested and restored amounts. Defeated Critters
cannot be healed and are never revived; such an attempt emits `HEAL_APPLIED` with `rejected = true`
and reason `TARGET_DEFEATED`. Healing has no effect on shields or statuses.

## Status effects

`StatusEffect` records `id`, `statusId`, `sourceCombatantId`, `targetCombatantId`, `magnitude`,
`duration`, `stackCount`, `appliedRound`, and `expiresAtRound`. Known statuses:

| Status | Effect | Maximum stacks |
| --- | --- | --- |
| `POISON` | Round-end damage equal to `magnitude * stackCount` | 5 |
| `ATTACK_UP` | Adds `magnitude * stackCount` to effective Attack | 3 |
| `ATTACK_DOWN` | Subtracts `magnitude * stackCount` from effective Attack | 3 |
| `SPEED_UP` | Adds `magnitude * stackCount` to effective Speed | 3 |
| `SPEED_DOWN` | Subtracts `magnitude * stackCount` from effective Speed | 3 |

Duration counts the application round. A duration of 2 applied in round 1 is active during rounds 1
and 2 and expires at the end of round 2. Reapplying the same status increments `stackCount` up to its
cap, keeps the original magnitude, and extends expiry to the later round. A duration of zero expires
at the end of the application round.

Poison ticks at round end before status expiry, bypasses shields, and can defeat a Critter. All
living combatants tick once in deterministic team-index, slot, then combatant-ID order; victory is
evaluated once after the batch. Attack and Speed modifiers apply only to later damage calculations or
the next round's initiative.

## Knockouts, victory, and draws

Knockouts are evaluated after each card action and after the round-end poison batch. A defeated
Critter cannot act again; pending actions are canceled with `ACTION_CANCELED` and reason `DEFEATED`.

The match completes when at most one team has a living Critter:

- One living team wins with reason `TEAM_DEFEATED`.
- No living teams produce a draw with reason `MUTUAL_DESTRUCTION`.

A draw is reachable in Run 4B through one atomic effect or simultaneous poison defeating the last
living Critters of both teams. When a match completes, remaining actions are canceled with reason
`MATCH_COMPLETED`. `COMPLETED` is terminal: round-end poison, status expiry, and round transition do
not run after match completion.

## Round transition

After a live round:

1. Poison ticks and knockouts are resolved.
2. Statuses and shields expiring this round are removed.
3. Every queued card, including canceled cards, leaves hand for discard.
4. Queues clear, reserved energy resets, commitment resets, and `planVersion` advances.
5. Unused energy carries and gains +2, capped at 10.
6. Each team draws three cards in team-index order, capped at 10 hand cards.
7. `roundNumber` advances and the phase returns to `PLANNING`.

The RNG stream continues from `state.rng`; shuffles use `PARK_MILLER_V1`. Duplicate transitions are
prevented by the resolver guards above.

## Battle events

Events are ordered, serializable, and deterministic. Each event has a stable ID
`evt:<battleId>:<sequence>`, the battle ID, sequence, round number, kind, optional source, target
IDs, and a payload. `state.eventVersion` stores the last emitted sequence.

| Kind | Purpose |
| --- | --- |
| `INITIATIVE_DETERMINED` | Ordered acting combatant IDs for the round |
| `CARD_PLAYED` | Card, definition, source, and queue index |
| `TARGET_SELECTED` | Resolved targets, retargeting, and skip state |
| `DAMAGE_APPLIED` | Full damage breakdown and HP result |
| `SHIELD_GRANTED` | Shield amount, expiry round, and stack count |
| `SHIELD_ABSORBED` | Absorbed amount and remaining damage |
| `HEAL_APPLIED` | Requested and restored healing or rejection reason |
| `STATUS_APPLIED` | Status, magnitude, stacks, expiry, and stacking state |
| `STATUS_TICKED` | Poison damage and HP result |
| `STATUS_EXPIRED` | Expired status or remaining shield |
| `CRITTER_DEFEATED` | Defeated combatant and zero health |
| `ACTION_CANCELED` | Canceled card and reason |
| `ROUND_COMPLETED` | Next round number and phase |
| `MATCH_COMPLETED` | Draw flag, winner team, and reason |

Events contain no wall-clock timestamps or uncontrolled randomness. Identical state, plans,
definitions, and RNG state produce identical state and event streams.

## Unresolved rules

- Surrender and cancellation transitions
- Dispel, cleanse, immunity, and status-vulnerability multipliers
- Status refresh semantics beyond stack cap and expiry extension
- Multi-team battles and non-frontline positioning
- Equipment, abilities outside card effects, and persistent progression
- Production animation timing and audiovisual presentation

## Run 5 playback contract

The server returns a committed pre-resolution snapshot, ordered events, and final authoritative
snapshot. Client playback starts from the pre-snapshot and applies events sequentially. HP, shields,
statuses, defeats, initiative, and match outcome become visible only when their corresponding event
is applied. The final snapshot reconciles presentation after playback; it never determines event
order or combat results.
