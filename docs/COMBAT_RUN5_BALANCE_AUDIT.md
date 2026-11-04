# Combat v1.0 Run 5 — Battle Simulation and Balance Audit

## 1. Executive summary

Combat is deterministic, conserves cards and energy, orders shield preparation correctly, and
completed all 8,000 audited matches without a timeout, resolution failure, replay mismatch, or
detected state-integrity error. The engine is technically ready for wider **instrumented**
playtesting.

Balance pacing is not ready to treat as final. Every matchup exceeded the stated duration targets.
The shortest observed match was 12 rounds; matchup means ranged from 15.07 to 39.93 rounds. These
were long but not permanent loops: no match reached the 100-round simulation guard, and the longest
streak without HP damage was three rounds.

Three outcomes need human validation before any tuning:

1. Healing-heavy, high-Morale/support, and low-Speed/support compositions won 100% of their paired
   samples despite opponents dealing much more raw damage.
2. Poison-focused teams beat shield-focused teams 100%; poison bypass worked, but that team also had
   healing and direct damage, so poison alone is not proven overpowered.
3. Skill combos were extremely rare under the current Training AI. The nominal high-Skill team made
   only 39 qualifying queues in 1,000 matches, fewer than the ordinary team's 75. This is primarily
   planner behavior and hand distribution, not evidence that the Skill multiplier is weak.

No balance values or production combat behavior were changed during this audit.

## 2. Confirmed executable configuration

Source inspection confirmed:

- Stats: Health, Speed, Skill, Morale.
- Maximum HP: `150 + 4 * Health`.
- Class ring multipliers: advantage `1.15`, neutral `1.00`, disadvantage `0.85`.
- Same-class damage and shield multiplier: `1.10`.
- Skill combo: at least three cards committed by one Critter; multiplier
  `1 + 0.03 * Skill`.
- Critical chance: `min(0.35, 0.05 + 0.02 * Morale)`; critical damage `1.50`.
- Eligible area targets roll independently.
- Shields prepare after both commitments and before initiative, in team/slot/source/queue/effect/
  target order.
- Run 4 healing, shield, and poison amounts come directly from `CardCatalog.luau`.
- Three Critters contribute four abilities with two copies each: 24 cards per team.
- Opening draw: six. Scheduled draw: three into free slots only. Hand cap: nine.
- Empty draw piles recycle discard through the explicit deterministic RNG stream.
- One Critter executes its complete queue before the next initiative entry.
- Energy starts at three, carries unused energy, gains two each round, and caps at ten.

### Documentation discrepancies

Numeric rules agree with executable code. Phase prose does not:

- `docs/COMBAT_RULES.md` describes `COMMITTED` and `COMPLETED`; executable phases are
  `PLANNING`, `RESOLVING`, and `FINISHED`.
- `docs/BATTLE_ENGINE.md` likewise says both commitments produce `COMMITTED` and describes the
  projector revealing at that phase. `BattlePlan.commitPlan` actually sets `RESOLVING`.
- `COMBAT_RULES.md` says all effects on a card share one target resolution. Mixed shield cards
  resolve targets once during preparation and resolve again for ordinary action effects. A dynamic
  target can therefore differ between those two times.

These are documentation defects, not simulation failures.

## 3. Methodology

Harness: `tests/Simulation/CombatBalanceSimulation.luau`, invoked by
`tests/simulate_run5.luau`.

- Uses production `BattleFactory`, `BattlePlan`, `TrainingPlanner`, `RoundResolver`, `Deck`, card and
  Critter catalogs, genetics-backed default ability resolution, and Park–Miller RNG.
- Runs 500 fixed seed pairs per matchup. Each pair is run in both team positions, giving 1,000
  matches per matchup and 8,000 total.
- Team IDs remain `team.a` and `team.b`; archetypes swap between them. This controls stable team
  index, deck-stream allocation, and identifier ordering.
- Captures complete event streams when requested through `Simulation.capture(matchupId, seed,
  swapped)`. Aggregate runs retain deterministic event hashes.
- Replays one exact input per matchup and compares rounds and event hashes.
- Uses the same greedy Training AI for both teams. Maximum simulation length is 100 rounds; reaching
  it counts as timeout/stalemate.
- Win-rate intervals are two-sided 95% Wilson intervals over all 1,000 matches. They describe these
  AI-controlled compositions, not all possible play.

Run with:

```sh
RUN5_MATCHES=1000 lune run tests/simulate_run5
```

`RUN5_MATCHES` must be even. Seed pair `i` for matchup index `m` is
`((m * 1,000,003 + i * 7,919) mod 2,147,483,646) + 1`.

## 4. Matchup outcomes

All values use 1,000 matches, including side swaps.

| Matchup (A vs B) | A win | 95% CI | B win | 95% CI | Draw |
| --- | ---: | ---: | ---: | ---: | ---: |
| Offense A vs Offense B | 38.8% | 35.8–41.9% | 61.2% | 58.1–64.2% | 0% |
| Offensive vs Defensive | 66.5% | 63.5–69.4% | 33.5% | 30.6–36.5% | 0% |
| Poison vs Shield | 100% | 99.6–100% | 0% | 0–0.4% | 0% |
| High-Speed vs Low-Speed | 0% | 0–0.4% | 100% | 99.6–100% | 0% |
| High-Morale vs Low-Morale | 100% | 99.6–100% | 0% | 0–0.4% | 0% |
| High-Skill vs Ordinary | 0% | 0–0.4% | 100% | 99.6–100% | 0% |
| Mixed vs Specialized Feral | 80.5% | 77.9–82.8% | 19.5% | 17.2–22.1% | 0% |
| Healing vs Burst | 100% | 99.6–100% | 0% | 0–0.4% | 0% |

Team-index wins were close to even after swaps: 53.6/46.4 in offense/offense, 52.1/47.9 in
offense/defense, and between 49.5/50.5 and 50/50 elsewhere. Strong archetype results are therefore
not explained by fixed side alone.

The two offensive teams contain the same classes in different frontline order
(`Feral/Shade/Gale` vs `Shade/Feral/Gale`). Their result indicates slot placement and frontline
targeting matter; it is not a nominally identical mirror.

## 5. Duration and defeat timing

| Matchup | Avg | Median | P90 | Min–max | Avg first defeat | Winner HP |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Offense/offense | 15.07 | 15 | 17 | 12–21 | 3.69 | 43.27 |
| Offense/defense | 22.85 | 23 | 25 | 15–32 | 9.53 | 68.01 |
| Poison/shield | 26.22 | 26 | 30 | 20–37 | 10.51 | 253.32 |
| High-/low-Speed | 32.92 | 33 | 37 | 23–46 | 13.31 | 257.95 |
| High-/low-Morale | 33.98 | 34 | 39 | 26–46 | 13.37 | 335.89 |
| High-Skill/ordinary | 23.70 | 24 | 27 | 17–33 | 12.63 | 203.04 |
| Mixed/specialized | 21.97 | 22 | 24 | 18–34 | 7.55 | 58.77 |
| Healing/burst | 39.93 | 40 | 45 | 28–54 | 12.89 | 341.26 |

None met the 3–5 one-sided, 6–10 typical, or 10–14 defensive targets. Even unanimous outcomes took
23–40 rounds on average. First defeat was also delayed except in offense/offense and
mixed/specialized. Long matches were active rather than permanently stalled: 6,346 zero-HP-progress
rounds occurred across all 8,000 matches, but no consecutive streak exceeded three.

## 6. Damage, healing, shields, and poison

Values are averages per match. Damage is HP damage after shields; poison is reported separately.
Shield is damage absorbed by that role's shields.

| Matchup | A damage / shield / heal / poison | B damage / shield / heal / poison |
| --- | --- | --- |
| Offense/offense | 731.07 / 123.79 / 0 / 36.00 | 756.20 / 126.49 / 0 / 29.47 |
| Offense/defense | 1,066.74 / 130.00 / 0 / 100.98 | 753.71 / 203.38 / 269.44 / 0 |
| Poison/shield | 883.72 / 0 / 353.49 / 344.90 | 962.16 / 234.81 / 306.62 / 0 |
| High-/low-Speed | 1,528.37 / 85.85 / 0 / 154.95 | 565.51 / 295.16 / 955.27 / 232.49 |
| High-/low-Morale | 606.82 / 363.58 / 1,029.62 / 191.19 | 1,526.84 / 89.55 / 0 / 152.90 |
| High-Skill/ordinary | 1,017.43 / 151.75 / 0 / 70.64 | 645.45 / 166.02 / 337.12 / 136.55 |
| Mixed/specialized | 700.16 / 132.78 / 485.03 / 115.86 | 1,368.60 / 0 / 0 / 17.64 |
| Healing/burst | 271.34 / 169.55 / 1,614.79 / 526.66 | 2,087.62 / 49.67 / 0 / 135.91 |

Observations:

- Poison bypass is meaningful: poison dealt 344.90 per match into the shield team and was never
  absorbed. The poison team won every match. Because it also healed 353.49 and dealt 883.72 direct
  damage, this does not isolate poison as the sole cause.
- Shield preparation absorbed substantial damage (up to 363.58 per match) and had zero ordering
  violations, but did not independently dominate outcomes.
- Healing repeatedly reversed large damage totals. Healing-heavy teams restored 1,614.79 while
  facing 2,087.62 direct damage and won all matches. The high-Morale/support and low-Speed/support
  teams restored roughly 1,000 per match and also won all matches.
- Defensive is not universally dominant: the offense team beat Stone/Tide/Gale 66.5%, although the
  matchup still averaged 22.85 rounds.

## 7. Skill and Morale

| Matchup | A crits / rolls / rate | B crits / rolls / rate | A/B combo queues |
| --- | --- | --- | ---: |
| Offense/offense | 2,005 / 20,221 / 9.9% | 2,136 / 20,573 / 10.4% | 48 / 38 |
| Offense/defense | 3,302 / 32,913 / 10.0% | 3,004 / 21,656 / 13.9% | 47 / 46 |
| Poison/shield | 3,131 / 29,250 / 10.7% | 3,272 / 24,229 / 13.5% | 45 / 33 |
| High-/low-Speed | 4,997 / 48,466 / 10.3% | 2,609 / 16,447 / 15.9% | 47 / 30 |
| High-/low-Morale | 2,734 / 17,469 / 15.7% | 5,041 / 50,274 / 10.0% | 32 / 41 |
| High-Skill/ordinary | 3,037 / 27,336 / 11.1% | 2,039 / 20,127 / 10.1% | 39 / 75 |
| Mixed/specialized | 1,819 / 18,936 / 9.6% | 3,451 / 39,091 / 8.8% | 90 / 66 |
| Healing/burst | 958 / 6,365 / 15.1% | 6,206 / 63,267 / 9.8% | 55 / 44 |

Critical rates track composition Morale and show no reproducibility errors. Observed rates from
8.8% to 15.9% are consistent with the represented base Morale values. Outcome variance was small
relative to composition effects: several matchups remained 100/0 despite critical randomness.

Skill combo access is poor under this AI. Across each 1,000-match matchup, qualifying queues numbered
only 30–90 per role despite 15–40 average rounds. High Skill increases combo payoff but does not make
three matching hand cards or planner selection more likely. The high-Skill team losing 100% is not
evidence against the `+3% * Skill` formula because its planner almost never invoked that formula.

## 8. Deck, hand cap, and energy

Both teams spent essentially all available energy; average unused committed energy was 0.00–0.04
per match. Long duration therefore was not caused by routine passing or energy hoarding.

| Matchup | A/B cards drawn per match | A/B cap-blocked draw opportunities | A/B partial draws |
| --- | ---: | ---: | ---: |
| Offense/offense | 33.73 / 34.15 | 52.0% / 47.3% | 7,626 / 7,436 |
| Offense/defense | 47.52 / 46.39 | 61.6% / 67.1% | 14,630 / 16,092 |
| Poison/shield | 48.49 / 52.97 | 80.2% / 69.9% | 20,269 / 19,137 |
| High-/low-Speed | 66.17 / 61.78 | 64.7% / 81.8% | 24,584 / 27,290 |
| High-/low-Morale | 61.19 / 68.09 | 88.0% / 64.4% | 29,136 / 25,763 |
| High-Skill/ordinary | 48.62 / 45.24 | 51.1% / 73.6% | 15,898 / 17,129 |
| Mixed/specialized | 42.75 / 47.98 | 70.3% / 44.0% | 15,569 / 14,296 |
| Healing/burst | 76.56 / 80.42 | 86.4% / 52.9% | 34,599 / 31,866 |

Partial draws include cap blocking and occasional insufficient active cards after defeat. Explicit
cap-block rates use only scheduled draws ending with a nine-card hand. The cap frequently leaves
cards in the draw pile, reducing cycling. This is expected draw-to-cap behavior, not card loss, but
it contributes to low combo availability when the planner cannot use enough cards from one Critter.

Every match preserved all 48 card instances exactly once across active/removed zones. No duplicate
or lost cards were detected, including after defeat retirement and discard recycling.

## 9. AI limitations

The Training AI is deterministic and legal, but not a balance-optimal player:

- Greedy global card scoring does not reserve energy, build three-card Skill combos, model future
  draws, or optimize authored queue order.
- It strongly prefers healing only below 60% HP. This produces effective reactive sustain but does
  not compare healing against lethal incoming queues.
- Shield scoring sees automatic multi-target cards through the source Critter proxy and generally
  gives full-health shields low priority. It does not value pre-initiative protection or predict
  enemy burst.
- It does not reason about class advantage, poison bypass, status duration, focus fire, frontline
  placement, or opponent hand/plan probabilities.
- Automatic `ENEMY` targeting attacks the slowest living enemy by rule, not a planner choice. This
  can focus durable support targets and amplify healing loops.
- Stable card-ID tie breaks can create consistent preferences across many seeds.

Therefore, unanimous composition outcomes are playtest warnings, not proof that one numeric card
value is defective.

## 10. Defects and reproducibility

### Confirmed engine defects

None found in this run.

Across 8,000 matches:

- 0 timeouts or 100-round stalemates.
- 0 factory, planning, commit, or resolution failures.
- 0 card duplication/loss or conservation violations.
- 0 event sequence violations.
- 0 shield-preparation-after-initiative violations.
- 0 stale status/shield expiry violations in nonterminal states.
- 0 deterministic replay mismatches.
- 0 draws; every match produced one surviving team.

Terminal matches intentionally skip round-end expiry under the current rules; the expiry audit does
not incorrectly flag terminal residual statuses.

### Confirmed non-engine defects

The phase and mixed-target documentation discrepancies listed in section 2 are reproducible by
comparing `BattlePhase.luau`, `BattlePlan.luau`, `RoundResolver.luau`, and the cited docs.

## 11. Balance concerns and possible adjustments

These are proposals for Combat v1.1 investigation, **not changes made by Run 5**.

1. **Prioritize pacing before class-specific damage tuning.** All means exceed targets, including
   nominal offense mirrors. Test a global pacing lever (for example damage, HP, or energy cadence)
   in isolated branches. Tradeoff: shorter matches improve tempo but reduce status, deck-cycle, and
   comeback windows.
2. **Test healing throughput and targeting with human or stronger AI.** Healing teams restored
   955–1,615 HP per match and won three relevant matchups 100%. Candidate experiments include lower
   heal amounts, healing fatigue, or stronger burst/focus tools. Tradeoff: reducing sustain may make
   support cards unattractive and increase first-actor snowballing.
3. **Do not nerf Speed from these results.** High-Speed lost 0/1,000 against a support-heavy
   low-Speed team despite full-queue initiative. Tradeoff: a premature Speed nerf could remove its
   main identity without addressing sustain.
4. **Do not tune Skill until combo-capable planning is tested.** Combo activation was too rare for a
   valid multiplier assessment. First improve simulation policy or run scripted legal combo plans.
   Tradeoff: making combos easier could create burst spikes and worsen hand-order variance.
5. **Evaluate hand cap jointly with planner behavior.** Cap blocking affected 44–88% of scheduled
   draw opportunities. Raising the cap would improve options and combo access but reduce deck cycling
   pressure and increase planning complexity; changing draw count could instead slow card access.
6. **Retest poison with controlled compositions.** Poison beat shields as intended, but its team also
   contained healing/direct damage. Reducing poison now risks removing its shield-counter role.
7. **Retain shield preparation ordering.** It worked without integrity errors and shield totals were
   meaningful but not universally winning. No ordering or duration adjustment is supported by this
   dataset.
8. **Investigate frontline slot sensitivity.** Reordering the same three offensive classes shifted
   wins to 38.8/61.2. Human tests should determine whether placement is legible strategic depth or an
   opaque pre-match trap. Changing frontline targeting would affect class identity and focus-fire.

## 12. Recommended Combat v1.1 priorities

1. Add a stronger simulation policy with explicit focus fire, defensive prediction, and combo
   construction; retain Training AI as a separate baseline.
2. Run human playtests with round count, card choices, cap blocks, and perceived repetition logged.
3. Establish a global pacing experiment targeting 6–10 ordinary rounds before individual card
   changes.
4. Run controlled ablations: identical teams with one stat changed, and identical card sets with one
   support category removed. Current class compositions confound stats with abilities.
5. Validate healing-heavy and poison/shield results first; both are decisive and affect core
   counterplay.
6. Correct phase and mixed-card targeting documentation.
7. Keep deterministic replay, shield preparation, card conservation, and server-authoritative
   lifecycle unchanged unless new evidence identifies a defect.

**Readiness verdict:** engine correctness supports wider instrumented playtesting; pacing and
composition balance do not yet support declaring Combat v1.0 balanced or release-final.
