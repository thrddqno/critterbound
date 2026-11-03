# Roadmap

## Foundation Run 1 — complete

Toolchain, Rojo mappings, architectural boundaries, typed conventions, bootstraps, and design docs.

## Foundation Run 2 — complete

Versioned domain schemas, pure validators, deterministic initiative, battle phases, fixtures, and
Linux-compatible tests.

## Run 3 — complete

Studio-only placeholder UI, presentation mapping, local planning preview, asset registry, and future
sprite contracts. No authoritative gameplay or production artwork.

## Run 4A — complete

Deterministic 3v3 initialization, deck zones, energy reservation, simultaneous private planning,
idempotent authenticated command processing, and hidden-information projection.

## Run 4B — complete

Server-authoritative, deterministic round resolution: effective-Speed initiative, ordered card
effects, targeting and retargeting, class advantage, damage and shields, healing, typed statuses,
poison ticks, knockouts, victory and draws, round transition, and replayable battle events. The
engine is pure and covered by Lune tests.

## Run 5 — complete

Playable server-authoritative 3v3 Training Grounds PvE: authenticated request transport, one active
match per player, sanitized snapshots, legal queue/remove/reorder/clear/commit commands,
deterministic AI, ordered client playback, terminal results, restart, and multi-round end-to-end
tests. Placeholder Critters and cards remain replaceable authored content.

## Run 6A — complete

Versioned DataStore profiles, renewable session ownership, bounded retries, migrations, autosave,
one-time Stone/Feral/Verdant starter ownership, selected teams, sanitized profile DTOs, and
profile-backed Training Grounds battles. Inventory, breeding, trading, equipment, rewards, and
crafting remain unimplemented.

## Run 6B — complete

Stackable and unique inventory records, centralized fixture definitions, bounded idempotent grants,
single-slot Critter equipment, persisted team selection, sanitized player-data commands, schema
migration, and rollback-safe profile mutations. Equipment modifiers remain data only.

## Run 6C — complete

Main Menu navigation, collection details, ordered team builder, inventory/equipment UI, sanitized
atomic collection DTOs, revision-checked idempotent player-data commands, and Training Grounds
return flow. Placeholder assets support desktop and landscape mobile without production artwork.

## Later runs

1. Genetics, breeding, and crafting
2. Trading with atomic server-side validation
3. PvE expeditions and expanded AI opponents
4. Competitive PvP, production UI, animation, and asset integration

Each run should validate its contracts before adding dependent systems. Monetization and random
loot remain outside foundation scope.
