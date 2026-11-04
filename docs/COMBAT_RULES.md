# Combat Rules

Combat v1.1 keeps server-authoritative round resolution in pure Luau. Blood Moon adds endgame
pressure without changing Combat v1.0 card, class, Skill, Morale, healing, poison, or shield rules.
Core combat uses Health, Speed, Skill, and Morale; Attack, Defense, and Resolve remain retired.

Maximum HP is server-derived as `150 + (4 * Health)`. Combatants enter battle at maximum HP.
Owned Critters persist Health, Speed, Skill, and Morale; derived maximum HP is battle state only.

## Round flow

1. Both players enter a private planning phase.
2. Each player may queue multiple cards for individual Critters, constrained by hand and energy.
3. Both plans commit without revealing or resolving one player first.
4. Server validates both plans against authoritative state.
5. Server snapshots both committed plans and prepares every valid queued shield effect.
6. Server creates one actionable initiative entry for each living Critter with queued cards.
7. Critters execute full queues sequentially in initiative order.
8. After all actions, round-end poison ticks, Blood Moon, knockouts, and status expiry are applied.
9. Server emits ordered battle events, then advances round state or completes the match.

Planning order is not attack execution order. Clicking a card earlier does not grant an earlier
attack. Simultaneous commitment closes planning; initiative and the rules below determine execution.

## Starting design values

- Three Critters per team
- 3 initial energy; +2 each later round
- 6 starting cards; +3 each later round
- 24-card team deck
- Four ability definitions per Critter, two copies each

Energy and unused cards carry between rounds. Energy caps at 10. Hands cap at 9; each scheduled
draw only fills available hand slots, so a full hand draws nothing. Empty draw piles reshuffle
discard deterministically when needed.
Cards resolved during the round are discarded before the next draw, so they can be reshuffled and
drawn again when the draw pile is empty. When a Critter is defeated, all cards sourced from that
Critter retire from draw, hand, discard, and queue before the next draw.

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
4. Higher `morale` first; missing `morale` counts as zero.
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

Manual rules require exactly one submitted target: `ALLY` and `ANY`. Automatic rules require an
empty client target list: `SELF`, `ENEMY`, `FRONT_ENEMY`, `ALL_ALLIES`, and `ALL_ENEMIES`. The server
derives automatic targets at resolution time and rejects forged target IDs.

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

Card definitions are static and are never mutated by resolution. Run 4 support values remain in the
versioned card catalog rather than live configuration so balance cannot change mid-battle and break
deterministic replay.

## Targeting and retargeting

Targets are resolved against current living combatants before effects execute:

- `SELF`: the source Critter while alive.
- `ALLY`: the submitted living ally; otherwise the lowest-slot living ally other than the source.
- `ENEMY`: the living enemy with lowest effective Speed; ties use slot, then combatant identifier.
- `FRONT_ENEMY`: the lowest-slot living enemy; submitted targets are ignored.
- `ALL_ALLIES`: every living ally ordered by slot, including the source.
- `ALL_ENEMIES`: every living enemy ordered by slot.
- `ANY`: the submitted living target; otherwise the effect is skipped.

Automatic `ENEMY` selection uses effective Speed at that card's resolution time. Earlier Speed
effects can therefore change later targets even though initiative remains snapshotted. If no legal
target exists, the effect is skipped but the card still consumes its turn and is discarded.
`TARGET_SELECTED` records whether retargeting or skipping occurred.

## Damage pipeline

Damage is calculated in this fixed order:

1. Base card damage.
2. Class multiplier: `1.15` advantage, `0.85` disadvantage, `1.00` neutral.
3. Same-class multiplier: `1.10` when card class matches source Critter class; otherwise `1.00`.
4. Skill combo multiplier: `1 + (0.03 * Skill)` for a source with at least three committed cards;
   otherwise `1.00`.
5. Flat `DAMAGE_UP`/`DAMAGE_DOWN` modifier, then clamp to at least zero.
6. Critical multiplier: `1.50` on a successful eligible roll; otherwise `1.00`.
7. Floor once.
8. Shield absorption in grant order.
9. HP damage clamped to remaining HP.

Ordinary damage does not read Attack or Defense. Negative final damage is impossible.

```text
floor(max(0, BaseDamage * Class * SameClass * Skill + FlatModifier) * Critical)
```

Skill combo eligibility is snapshotted from each originating Critter's committed queue. Three- and
four-card queues qualify equally. Cross-class cards count toward their owner's combo, while cards
from different Critters never combine. Eligibility does not change when cards fail or are canceled.
Skill does not modify healing, shields, poison ticks, or status magnitudes.

### Morale and critical hits

Morale changes only critical probability:

```text
CritChance = min(0.35, 0.05 + 0.02 * Morale)
```

Morale 0, 5, 10, and 15 therefore produce 5%, 15%, 25%, and 35% chances. Chance remains
capped at 35%. Speed does not reduce incoming critical chance, and critical damage is always `1.50`.
There is no Last Stand mechanic.

Direct `DAMAGE` effects are critical-eligible by default. Single-target, frontline, and area damage
use the same rule; area effects roll independently for each living target in deterministic target
order. A triggered damage effect is ineligible unless its authored effect explicitly sets
`triggered = true, criticalEligible = true`. Healing, shields, status application, and poison ticks
never roll and never critically strike.

Critical rolls use `BattleState.criticalRng`, a dedicated `PARK_MILLER_V1` stream separate from the
deck shuffle stream in `BattleState.rng`. Production seeds come from server-only, nonpublic GUID
material. Both states advance only on the server and are omitted by `BattleProjector`; clients receive
only resolved outcomes in events.

Critical RNG advances exactly once for each critical-eligible `DAMAGE` effect applied to a valid,
living target. A valid zero-base or zero-modified-damage hit still consumes one roll, but records
`isCritical = false` and multiplier `1.00` to avoid false presentation. Missing, defeated, or invalid
targets consume no roll. Skipped targeting, missing definitions, defeated-source actions, canceled
actions, healing, shields, statuses, and poison consume no roll. There is no separate miss mechanic;
if one is added later, its critical consumption rule must be specified. Multi-target damage consumes
one roll per living target, in resolved target order.

### Card-driven damage statuses

Former Attack-modifying cards permanently use flat outgoing-damage statuses:

| Card | Provisional replacement |
| --- | --- |
| `feral.frenzy` | `DAMAGE_UP` +8 for 2 rounds |
| `feral.fury` | `DAMAGE_UP` +10 for 3 rounds |
| `stone.crush` | `DAMAGE_DOWN` 5 for 2 rounds after damage |
| `shade.weaken` | `DAMAGE_DOWN` 6 for 2 rounds |
| `shade.curse` | `DAMAGE_DOWN` 5 for 3 rounds |
| `shade.terror` | `DAMAGE_DOWN` 4 for 2 rounds after damage |

### Class ring

The six classes form a ring:

```text
Verdant -> Tide -> Feral -> Gale -> Shade -> Stone -> Verdant
```

A class is advantaged against the next two classes and disadvantaged against the previous two.
Self and the opposite class are neutral. Changing the ring or multipliers is replay-breaking.

## Shields

`BattleCombatant.shields` is an ordered array of `{ id, sourceCombatantId, amount, expiresAtRound }`.
Shields stack, absorb in preparation order, and are removed when fully consumed. Same-class shield
cards receive the `1.10` same-class multiplier exactly once; cross-class cards use `1.00`. Amounts are
floored once after this multiplier. Skill and class matchups do not modify shields. Shields expire at
the end of the round in which they are prepared; they never carry to the next round. Damage records
both the pre-shield amount and the absorbed amount. Poison bypasses shields.

After both plans commit, shield preparation runs before initiative. It reads the cloned committed
plans and processes eligible shield effects in this total order:

1. Team index ascending.
2. Source battlefield slot ascending, then source combatant ID.
3. Per-Critter queue index ascending.
4. Authored effect index ascending.
5. Resolved target order from the targeting rule.

The source must be living, the queued card must belong to that source, and every target must resolve
as valid and living. Each application emits `SHIELD_PREPARED` with card, effect, and preparation-order
metadata. All preparation events precede `INITIATIVE_DETERMINED`, so source Speed cannot delay shield
activation. Drawing or queueing alone never activates a shield.

Normal action resolution skips shield effects. A shield-only card still produces normal card-play and
target events and moves through the card lifecycle once. For mixed cards, only shield effects run in
preparation; all non-shield effects retain authored order and run during the ordinary action. Energy
is deducted once at commitment, and the card is consumed once. A prepared shield remains if its
source is later defeated or its ordinary action is canceled, until consumed or expired.

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
| `DAMAGE_UP` | Adds `magnitude * stackCount` to outgoing card damage | 3 |
| `DAMAGE_DOWN` | Subtracts `magnitude * stackCount` from outgoing card damage | 3 |
| `SPEED_UP` | Adds `magnitude * stackCount` to effective Speed | 3 |
| `SPEED_DOWN` | Subtracts `magnitude * stackCount` from effective Speed | 3 |

Duration counts the application round. A duration of 2 applied in round 1 is active during rounds 1
and 2 and expires at the end of round 2. Reapplying the same status increments `stackCount` up to its
cap, keeps the original magnitude, and extends expiry to the later round. A duration of zero expires
at the end of the application round.

Poison ticks at round end before status expiry, bypasses shields, and can defeat a Critter. All
living combatants tick once in deterministic team-index, slot, then combatant-ID order; victory is
evaluated after the following Blood Moon batch. Damage and Speed modifiers apply only to later damage
calculations or the next round's initiative.

## Blood Moon

The server-owned production configuration enables Blood Moon at round 10 with 50 HP damage, adding
30 HP each later round: `50 + 30 * (roundNumber - 10)`. It runs once per eligible round after poison
and before final outcome evaluation, status expiry, or round transition. A card-action victory remains
immediate and skips later poison and Blood Moon processing.

Blood Moon applies one fixed value to every living Critter in team-index, slot, then combatant-ID
order. The full batch completes before victory is evaluated. It bypasses shields, ignores class,
Skill, Morale, statuses, and all ordinary damage modifiers, cannot critically strike, consumes no
critical or deck RNG, clamps HP at zero, and never revives or targets defeated Critters.

`src/server/Config/CombatConfig.luau` owns `Enabled`, `StartingRound`, `InitialDamage`,
`DamageIncrement`, and `BypassesShields`. `BattleService` injects this configuration into the pure
resolver. `BattleProjector` exposes a cloned read-only projection only for HUD messaging; clients
cannot submit an override. `lastBloodMoonRound` prevents a duplicate tick for the same round.

## Knockouts, victory, and draws

Knockouts are evaluated after each card action and after the combined round-end poison/Blood Moon
batches. A defeated
Critter cannot act again; pending actions are canceled with `ACTION_CANCELED` and reason `DEFEATED`.
Its sourced cards retire from every active zone. Retirement preserves survivor order, consumes no
RNG, grants no energy refund, and does not add replacement draws. Immutable `CardInstance` records
remain available for event history.

The match completes when at most one team has a living Critter:

- One living team wins with reason `TEAM_DEFEATED`.
- No living teams produce a draw with reason `MUTUAL_DESTRUCTION`.

A draw is reachable through one atomic effect or the full poison/Blood Moon processing defeating the
last living Critters of both teams. When a match completes, remaining actions are canceled with
reason `MATCH_COMPLETED`. `COMPLETED` is terminal: later round-end processing and round transition do
not run after match completion.

## Round transition

After a live round:

1. Poison ticks, Blood Moon, and knockouts are resolved as ordered full batches.
2. Statuses and shields expiring this round are removed.
3. Cards sourced from defeated Critters retire from all active zones.
4. Remaining queued cards, including canceled cards, leave hand for discard.
5. Queues clear, reserved energy resets, commitment resets, and `planVersion` advances.
6. Unused energy carries and gains +2, capped at 10.
7. Each team draws three cards in team-index order, capped at 9 hand cards.
8. `roundNumber` advances and the phase returns to `PLANNING`.

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
| `DAMAGE_APPLIED` | Full damage breakdown, `isCritical`, shield absorption, and HP result |
| `SHIELD_PREPARED` | Pre-initiative shield amount, card/effect identity, order, and stack count |
| `SHIELD_GRANTED` | Compatibility event for direct effect-resolution callers |
| `SHIELD_ABSORBED` | Absorbed amount and remaining damage |
| `HEAL_APPLIED` | Requested and restored healing or rejection reason |
| `STATUS_APPLIED` | Status, magnitude, stacks, expiry, and stacking state |
| `STATUS_TICKED` | Poison damage and HP result |
| `BLOOD_MOON_DAMAGE` | Environmental source, round damage, HP before/after, bypass state, and defeat flag |
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
