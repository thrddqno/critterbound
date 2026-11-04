# Combat v1.0 Run 5.1 — Battle Pacing Root-Cause Analysis

## Executive conclusion

Long battles are primarily caused by low direct-damage throughput relative to total HP, compounded
by sustain and a long post-first-defeat tail. They are not primarily caused by the AI passing,
failing to spend energy, zero-card draws, or permanent defense loops.

Across the production baseline, aggregated over all eight Run 5 matchups:

- Mean duration: **27.12 rounds**.
- First defeat: **10.48 rounds**; completion then required another **16.65 rounds**.
- Direct HP damage: **71.36 per battle-round**.
- Poison: **10.33 per battle-round**.
- Healing: **24.69 per battle-round**.
- Shield absorption: **10.76 per battle-round**.
- Net team-HP progress: **57.00 per battle-round**.
- AI energy use: **99.98%**.
- Turns passed with an affordable legal card: **0**.

Only the isolated `3.0x` direct-damage counterfactual reached the 6–10-round target, averaging 7.62
rounds. This is diagnostic evidence, not a recommendation to triple every card without playtesting.
No production rule or authored value changed.

## Methodology

`tests/Simulation/CombatPacingAnalysis.luau` instruments the actual `BattleFactory`, `BattlePlan`,
`TrainingPlanner`, `RoundResolver`, catalogs, deck, and deterministic RNG. The runner is
`tests/analyze_run5_1.luau`.

Each scenario ran:

- All eight Run 5 compositions.
- 200 matches per matchup: 100 fixed seed pairs, each side-swapped.
- 1,600 matches per scenario.
- 11 scenarios and **17,600 total matches**.
- The same seeds and team compositions in every scenario.

Counterfactual definitions are detached copies passed only into the offline battle. Planner
counterfactuals live only in the analysis harness. Production files are never mutated.

Run with:

```sh
RUN51_MATCHES=200 lune run tests/analyze_run5_1
```

## Ranked root causes

### 1. Direct-damage throughput is low relative to effective HP

Baseline direct damage plus poison was 81.69 per battle-round. Healing and shield absorption returned
or prevented 35.45, equal to 43.4% of that pressure. Net combined HP progress was 57.00 across six
starting Critters per round.

Direct-damage scaling had the largest controlled effect:

| Isolated scenario | Mean rounds | Change from baseline |
| --- | ---: | ---: |
| Baseline | 27.12 | — |
| Damage `1.5x` | 18.38 | −32.2% |
| Damage `2.0x` | 12.19 | −55.1% |
| Damage `3.0x` | 7.62 | −71.9% |

This dose response is much larger than planner, healing, or shield changes. It is the strongest
evidence that base offensive throughput—not just bad choices—is the central pacing constraint.

### 2. Matches have a large post-first-defeat tail

The first defeat took 10.48 rounds, already outside the typical target. Completion then took another
16.65 rounds. Defeat retires all cards belonging to that Critter, reducing active deck size and
offensive options while surviving support cards can continue circulating. This is correct production
behavior, but it helps explain why a match does not rapidly collapse after the first knockout.

### 3. Sustain materially offsets offense, but is not the sole cause

- Healing restored 24.69 HP per battle-round.
- Shields absorbed 10.76 damage per battle-round.
- 8.92% of team-rounds with incoming damage ended at or above their starting HP because sustain
  fully neutralized that HP pressure.
- Healing restored 83.12% of requested amount; 16.88% was overheal. Healing actions were therefore
  usually effective rather than empty animation.
- Only 38.1% of prepared shield value was consumed; **61.9% expired unused**. Shield strength is not
  the leading pacing cause in aggregate.

Halving healing reduced duration by 8.8%; halving shields reduced it by 4.8%. Sustain matters, but
removing half of either category alone leaves 24.72- and 25.81-round battles.

### 4. The production AI uses many non-damage cards, but better tactical ordering has limited impact

Production card plays were:

| Category | Plays | Share |
| --- | ---: | ---: |
| Damage | 87,209 | 55.1% |
| Healing | 26,158 | 16.5% |
| Shield | 23,424 | 14.8% |
| Status-only | 21,453 | 13.6% |

A simulation-only tactical planner prioritizing noncritical lethal attacks and damage before ordinary
support reduced duration only from 27.12 to 25.53 rounds (5.9%). It raised direct damage from 71.36
to 79.16 per round, but also found more effective healing. AI quality contributes, but cannot explain
the full 17–21 excess rounds.

The production planner selected support while leaving a nominally lethal legal damage card unselected
on 954 of 86,792 team-turns (1.10%). This is an upper bound because the audit checks pre-plan energy;
some lethal cards would not fit after earlier selections. Ineffective support-over-lethal behavior is
real but uncommon.

### 5. Energy budget, not refusal to act, leaves large hands unplayed

The AI spent 99.98% of available energy and never passed while an affordable legal card existed.
Every legal card was individually affordable because cards cost at most two and round energy starts
at three, but the whole hand could not fit in the shared budget.

The AI played 158,244 of 736,851 legal cards observed in hand (21.48%). This low ratio does not mean
the AI passed: it means roughly eight or nine legal cards competed for enough energy to play about
two per team-round.

An AI that prioritized maximum-cost cards spent 100% energy but made pacing dramatically worse:
54.60 average rounds and 332/1,600 timeouts. It overselected expensive support cards, played fewer
cards, increased average hand residence to 18.58 rounds, and reduced net HP progress to 24.62 per
round. More spending is not available as a fix; spending quality matters.

### 6. Skill combo scarcity is genuine, but forcing combos does not solve pacing

Baseline hands contained only 0.019 legal, energy-feasible three-card combinations per team-turn on
average. Across 86,792 team-turns, 1,683 distinct legal triple combinations were seen and only 162
qualifying queues occurred naturally.

The combo planner raised activations from 162 to 1,193, yet mean duration increased from 27.12 to
27.69 rounds. Forced triples displaced higher-value immediate actions and increased healing. Combo
scarcity limits the Skill mechanic, but is not a root fix for pacing under current cards and energy.

## AI decision findings

| Metric | Production result |
| --- | ---: |
| Legal cards observed | 736,851 |
| Cards played | 158,244 (21.48%) |
| Energy spent | 99.98% |
| Passes with affordable card | 0 |
| Support-over-lethal opportunities | 954 (1.10% of team-turns) |
| Legal triple combinations | 1,683 |
| Natural combo activations | 162 |
| Tactical-AI duration improvement | 5.9% |

Conclusion: current scoring is imperfect and does not deliberately assemble combos, but passive AI
is not the main reason battles exceed 20 rounds.

## Card circulation and hand cap

| Metric | Production result |
| --- | ---: |
| Average planning hand | 8.51 cards |
| Actual scheduled draw | 2.07 cards/team-round |
| Zero-card draws | 0 / 83,592 |
| Full-hand planning turns | 61,671 / 86,792 (71.1%) |
| Full hand with post-plan energy for another card | 0 |
| Average observed card age in hand | 6.36 rounds |
| Team reshuffles | 22,569 (27.0% of draw opportunities) |
| No-valid-target cards | 1,558 (0.21% of legal-card observations) |
| Individually unaffordable cards | 0 |

Full hands were common, but after the chosen queue consumed energy, none retained enough energy for
another legal card. On full-hand turns, 446,851 unselected card observations were blocked by the
remaining energy budget. The hand cap therefore reduces incoming draws and extends card residence,
but does not cause passing or an exhausted/unusable hand.

Average hand distribution by originating slot was 1.95 / 2.95 / 3.60 cards. Slot-one Critters tend to
lose cards earlier through frontline defeat and card retirement, creating uneven combo access. Card
ownership affects which Critter can form a combo, but targeting blocked only 0.21% and individual
cost blocked none before total-budget allocation.

Forced discard remains unnecessary and was not reintroduced.

## Damage versus sustain

Production averages per battle-round:

| Effect | Value |
| --- | ---: |
| Direct HP damage | 71.36 |
| Poison HP damage | 10.33 |
| Shield absorption | 10.76 |
| Healing restored | 24.69 |
| Net combined HP progress | 57.00 |

Prepared shield totals were 1,226,926 across the sample; 759,799 expired unused. Shield preparation
works, but most shield value did not absorb damage. Healing was more consistently effective, with
83.12% of requested healing restored.

The key distinction is:

- Weak offensive decisions explain a small part: tactical AI added 7.80 direct damage per round.
- Support explains a meaningful part: healing plus shield absorption averaged 35.45 per round.
- Base throughput explains most of the controllable pacing: `3.0x` damage alone reached 7.62 rounds,
  while halving either support category did not approach the target.

## Controlled counterfactuals

Each row changes one dimension only and uses the same compositions and paired seeds.

| Scenario | Mean rounds | Relative change | Result |
| --- | ---: | ---: | --- |
| Production baseline | 27.12 | — | 1,600 complete |
| Tactical AI | 25.53 | −5.9% | 1,600 complete |
| Maximum-spend AI | 54.60 | +101.3% | 1,268 complete; 332 timeouts |
| Combo-valuing AI | 27.69 | +2.1% | 1,600 complete |
| Healing `0.5x` | 24.72 | −8.8% | 1 timeout |
| Shield `0.5x` | 25.81 | −4.8% | 1,600 complete |
| Direct damage `1.5x` | 18.38 | −32.2% | 1,600 complete |
| Direct damage `2.0x` | 12.19 | −55.1% | 1,600 complete |
| Direct damage `3.0x` | 7.62 | −71.9% | 1,600 complete |
| Battle HP `0.75x` | 21.01 | −22.5% | 1,600 complete |
| Battle HP `0.50x` | 13.64 | −49.7% | 1,600 complete |

The alternative-value scenarios keep production AI decisions based on original card definitions;
only resolution receives detached scaled effects. This prevents a damage/heal score change from
silently changing planner policy. HP scenarios alter only simulation battle HP after production
construction.

## Changes most likely to reach 6–10 rounds

1. **Global direct-damage throughput** has the clearest causal relationship. `3.0x` reached 7.62
   rounds; `2.0x` reached 12.19.
2. **A large HP reduction** also works directionally, but even `0.5x` HP averaged 13.64 rounds.
3. **Healing or shield reductions alone** cannot reach the target at tested levels.
4. **AI-only changes** cannot reach the target under current values. Tactical AI improved 5.9%;
   combo forcing worsened pacing.
5. **More aggressive energy use** is not viable because production already spends virtually all
   energy.

## Risks and tradeoffs

### Raising direct damage

- Pros: strongest measured pacing response; preserves Health formula, draw-to-cap, support identity,
  and deterministic engine behavior.
- Risks: first defeats moved from 10.48 rounds to 1.99 at `3.0x`; Speed and full-queue execution may
  become decisive; critical hits become much swingier; healing and poison lose relative value.

### Lowering HP

- Pros: simple global lever; leaves card text unchanged relative to itself.
- Risks: changes Health-stat identity and all sustain ratios; `0.5x` still missed target; low-Health
  Critters become vulnerable to one queue.

### Reducing healing

- Pros: targets the strongest unanimous Run 5 composition; improves net progress.
- Risks: only 8.8% pacing gain at `0.5x`; weakens an already narrow support role and does not fix
  offense mirrors.

### Reducing shields

- Pros: reduces pre-initiative effective HP.
- Risks: only 4.8% pacing gain; 61.9% already expires unused; risks deleting shield strategy without
  addressing duration.

### Improving AI

- Pros: fewer support-over-lethal choices and more direct pressure; better player-facing opponent.
- Risks: only 5.9% pacing gain; stronger focus fire could make PvE feel unfair without fixing card
  fundamentals.

### Increasing combo use

- Pros: makes Skill visible and rewards hand planning.
- Risks: forced combo policy increased duration; triples may include weak support and consume the full
  energy budget. Making combos easier could create burst/critical spikes for human optimizers.

## Smallest viable Combat v1.1 recommendation

Do not ship a blind `3.0x` damage multiplier despite it being the only tested isolated lever that met
6–10 rounds. Its 1.99-round first defeat is too abrupt and may turn Speed plus Morale into a severe
snowball.

The smallest defensible next adjustment is an **instrumented `2.0x` direct-damage prototype**, with
all other mechanics unchanged. It reduces mean duration to 12.19 rounds, moves first defeat to 3.72,
preserves support cards, and exposes the remaining post-defeat/sustain tail for targeted tuning. It is
the smallest tested single numeric lever with a major effect and no timeouts.

For a strict 6–10-round release target, no small isolated change tested here is sufficient. After the
`2.0x` prototype, human playtests should decide whether to add a smaller second adjustment—likely
healing throughput or post-defeat card economy—rather than escalating directly to `3.0x` damage.

**Recommendation:** prototype, do not automatically implement, `2.0x` direct damage as Combat v1.1
experiment one; retain current HP, shields, healing, draw-to-cap, energy, and AI as controls.
