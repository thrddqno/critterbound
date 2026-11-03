# Game Design

Critterbound is a fixed-perspective 3v3 creature card battler. Players build teams from owned
Critters and use energy to queue illustrated ability cards.

## Classes

- **Verdant:** healing and sustain
- **Tide:** control and defense
- **Feral:** burst damage
- **Gale:** speed and utility
- **Shade:** poison and attrition
- **Stone:** tanking and counters

## Combat identity

Players plan secretly and commit simultaneously. Speed determines execution order, not planning
order. Energy and unused cards carry between rounds under intended future rules.

Each actionable Critter receives one initiative entry. Higher Speed acts first. A Critter resolves
its full card queue in submitted order before the next Critter acts. Equal-Speed ties alternate
team priority by round, then use battlefield slot and combatant identifier. This tie rule is a
Foundation Run 2 assumption and may be balance-tested later without changing planning semantics.

Offensive `ENEMY` cards automatically focus the living opponent with lowest effective Speed. Slot,
then combatant ID break ties. This makes Speed both initiative and threat-management state while
preventing unrestricted focus fire. Ally and `ANY` targeting remain manual; self, frontline, and area
rules are automatic. Defeated Critters retire all their cards from active deck zones.

## Long-term systems

Appearance genetics and combat ability genetics remain independent. Future progression may include
breeding, equipment, crafting materials, collection, trading, PvE expeditions, competitive PvP,
and AI opponents. Persistent profiles own progression; server validation protects all changes.

Foundation fixtures for Stone, Feral, and Verdant demonstrate schema shape only. Their names,
stats, costs, and cards are not final balance or production content.
