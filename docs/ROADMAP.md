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

## Run 7A — complete

Logical appearance and ability gene registries, exact allele-triplet validation, deterministic
server-only inheritance and trace, bounded compatibility fallback, placeholder appearance metadata,
four-ability resolution, profile schema-3 starter migration, and unchanged 24-card PvE battles.
Breeding transactions, eggs, trading, final art, and new combat effects remain out of scope.

## Run 7E.1 — complete

Curated appearance variants, twelve alternative class abilities, explicit `compatibleClasses` for
cross-class genes, additive class ability pools, founder fixture genomes, and diversity simulations
that assert multiple resolved appearances plus legal ability sets. Stored starter, egg, and offspring
genomes remain unchanged; inheritance order, allele weights, fallback repair, mutation defaults, and
24-card team decks are preserved.

## Run 7E.2 — complete

Server-authorized deterministic acquisition pools, genetically varied breedable Critters, persisted
pool/seed/genome metadata, atomic grants, bounded durable receipts, and Collection/Team/Training
compatibility. Clients cannot choose class, genes, seed, identity, or source.

## Run 7E.3 — complete

Repeatable Training Victory contracts, legitimate Training Grounds victory completion, schema-6
contract entitlements, durable non-pruned redemption identity, atomic idempotent `COMMON_FOUNDERS`
claims, contract UI, and security/regression coverage. Completion callback retries survive ordinary
save failure while the battle session lives; server-process crash before the profile completion write
remains unsupported.

## Run 7E.3.1 — complete

Unified client profile revision ownership, revision-aware resource caches, out-of-order response
rejection, global mutation gating, exact uncertain-request retries, affected-resource refreshes, and
screen-lifetime guards. Egg list responses now carry profile revision under Egg protocol version 2.

## Run 7E.4 — complete

Full real-service journey coverage now connects starter profiles, Training Grounds victories,
contracts, reward acquisition, equipment, team selection, breeding, incubation, hatching, offspring
battles, and profile reload. Late breeding retries remain idempotent after bounded receipt pruning,
generated egg IDs cannot overwrite existing records, and contract reward navigation targets the
awarded Critter. Durable battle-completion recovery across process crash remains a documented
follow-up requiring a battle-ID outbox.

## Later runs

1. Breeding transactions and crafting
2. Trading with atomic server-side validation
3. PvE expeditions and expanded AI opponents
4. Competitive PvP, production UI, animation, and asset integration

Each run should validate its contracts before adding dependent systems. Monetization and random
loot remain outside foundation scope.
