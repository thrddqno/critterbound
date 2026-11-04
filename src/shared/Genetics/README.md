# Genetics

Run 7A separates appearance and ability inheritance. Every named locus stores one dominant (`D`) and
two recessive (`R1`, `R2`) logical gene IDs. Registry IDs never contain Roblox asset IDs.

Appearance loci: `body`, `eyes`, `wings`, `tail`, `color`, `markings`, `accessories`.

Ability loci: `mouth`, `horn`, `back`, `tail`, `traits`.

`GenomeValidator` checks exact schema shape, known genes, locus compatibility, class/body-rig
resolution, and four existing class-compatible cards. `AppearanceResolver` emits logical body/layer
metadata. `AbilityResolver` emits exactly four unique ability and card-definition IDs; neutral traits
emit no card.

Run 7E.1 adds curated appearance variants and twelve alternative class abilities. `CritterCatalog`
keeps four canonical `abilityIds` and an additive `abilityPool`; stored starter and offspring genomes
continue to use canonical defaults. Body genes never cross classes. Non-body appearance layers and
ability genes may cross classes only through explicit `compatibleClasses` metadata, and still must
pass each target class's body-rig, shape, and tag requirements. Cross-class card acceptance derives
from `GeneRegistry` plus `CardCatalog` through `AbilityResolver.cardClassFor`; supplied class maps are
never trusted. `founderGenomes` are separate from `defaultGenomes` and are reserved for Studio fixtures
and Training Grounds opponents.

Resolvers walk `D`, `R1`, then `R2`. If no compatible candidate exists, they choose registry fallback
by ascending `fallbackPriority`, then gene ID. This ordering is gameplay behavior and must remain
golden-tested. Compatibility repair replaces only unresolved dominant alleles and preserves recessive
carriers; fallback stays native to the offspring class.

Authoritative offspring generation lives only in `Server/Genetics/InheritanceEngine`. Each of 36
child allele positions consumes one fair parent draw and one parent-allele draw. Allele buckets are
`1..75 = D`, `76..95 = R1`, and `96..100 = R2`, totaling 72 RNG draws when mutation is disabled.
Compatibility repair replaces only unresolved dominant alleles and preserves recessive carriers.
Mutation is off by default; enabled mutation uses bounded sorted candidate lists and no retry loops.
G4 implements that future stage as pure server module `Server/Genetics/MutationEngine` with disabled
`MUTATION_POLICY_V1`. Only the 22 active-locus `R1`/`R2` positions are eligible; dominant genes and the
reserved `traits` locus remain unchanged. G4 does not wire mutation into production breeding.

Run 7A adds no breeding transaction, egg, trading, client-selected genes, final art, or combat effect.

Run 7E.2 adds deterministic, server-authored acquisition generation without changing breeding
inheritance weights or mutation behavior. `AcquisitionPools` defines `COMMON_FOUNDERS`,
`CLASS_SPECIFIC_FOUNDERS`, and `CROSS_CLASS_CARRIERS` with versioned source IDs, eligible classes,
class weights, gene weights/overrides, disabled genes, cross-class allowlists, and variant/carrier
limits. `Server/Genetics/VariantGenerator` consumes an explicit `DeterministicRng` seed, selects
classes and genes with integer weights, preserves every `D/R1/R2` triplet, and emits a trace of
selected genes, weights, retries, and caps. It uses bounded attempts and fails closed rather than
looping. Every result is re-validated through `GenomeValidator`, `AppearanceResolver`, and
`AbilityResolver`, with exactly four unique class-legal cards.

Visible variation is weighted, not guaranteed to be unique. Each pool enforces appearance and
ability variant caps plus carrier-slot limits; `CROSS_CLASS_CARRIERS` additionally limits cross-class
genes to its explicit allowlist and caps cross-class dominants at one. Class base stats come from
`CritterCatalog`, never from random generation. Generated instances persist the actual genomes and
source metadata and appear in Collection, Team Builder, Training Grounds, and breeding normally.
