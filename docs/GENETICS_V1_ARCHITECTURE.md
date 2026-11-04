# Critterbound Genetics v1.0 Architecture

Status: G4 D/R1/R2 mutation foundation. `CLASSIC_INHERITANCE_V1` and
`MUTATION_POLICY_V1` are implemented but not enabled in the production breeding lifecycle.

This document supersedes the earlier paired-allele proposal. Critterbound keeps its existing schema-2 gene triplets and does not migrate saved Critters or eggs to another inheritance representation.

## 1. Existing system and G2 disposition

| Area | Current contract | G2 disposition |
| --- | --- | --- |
| Appearance genotype | `body`, `eyes`, `wings`, `tail`, `color`, `markings`, and `accessories`, each `{ D, R1, R2 }` | Preserve |
| Ability genotype | `mouth`, `horn`, `back`, `tail`, and reserved `traits`, each `{ D, R1, R2 }` | Preserve |
| Genome schema | Appearance and ability schema version 2 | Preserve; no profile, Critter, or egg migration |
| Registry | Logical IDs, locus metadata, class/species/rig compatibility, defaults, curated cross-class genes | Reuse; pin current definitions as gene content version 1 |
| Validation | Exact shapes, exact loci/positions, registered IDs, locus matching, resolvable phenotype | Reuse and add content-version validation |
| Legacy inheritance | Every child position independently samples a parent and then 75/20/5; fallback rewrites `D` | Preserve only for current production lifecycle |
| Classic foundation | Not previously available | Add opt-in `CLASSIC_INHERITANCE_V1` without production wiring |
| Class inheritance | Same class is retained; mixed classes select either parent 50/50 | Preserve as `CLASS_INHERITANCE_V1` |
| Appearance expression | Existing resolver can inspect D, R1, then R2 and use fallback | Preserve legacy API; add dominant-only Classic resolution |
| Ability expression | Fixed mouth/horn/back/tail order, curated cross-class support, duplicate prevention, fallback | Preserve legacy API; add dominant-only Classic resolution |
| Cards/decks | Four resolved abilities, two cards per ability, eight cards per Critter, 24 per 3v3 team | Preserve |
| Breeding/eggs/hatching | Server-authoritative atomic profile mutation and stored schema-1 eggs | Preserve unchanged |

## 2. Persisted genetic structure

```luau
AppearanceGenomeV2 = {
	schemaVersion = 2,
	slots = {
		body = { D = geneId, R1 = geneId, R2 = geneId },
		-- eyes, wings, tail, color, markings, accessories
	},
}

AbilityGenomeV2 = {
	schemaVersion = 2,
	slots = {
		mouth = { D = geneId, R1 = geneId, R2 = geneId },
		-- horn, back, tail, traits
	},
}
```

`D` is the ordinary expressed position. `R1` and `R2` are hidden carrier positions. All three positions are heritable. Position names are stable persisted schema, not paired alleles.

Every ID must resolve in the selected gene content version and match both genome kind and locus. G2 assigns all current definitions to `GeneRegistry.ContentVersion == 1`. Unknown content versions, unknown IDs, wrong-kind IDs, and wrong-locus IDs fail closed. Version 1 definitions must remain readable while persisted records reference them.

Existing records do not gain a new field in G2. Their schema-2 genome contract is mapped to content version 1 by the current Critter/egg schema. A later persistence version must store an explicit content-version field before introducing content version 2.

## 3. `CLASSIC_INHERITANCE_V1`

### 3.1 Stable iteration and integer sampling

Inheritance iterates appearance loci, then ability loci, using `GeneRegistry.AppearanceSlots`, `GeneRegistry.AbilitySlots`, and positions `D`, `R1`, `R2`. It never relies on hash iteration.

For each child position:

1. Select parent A or B with integer weight `1:1`.
2. Select that parent's source position with integer weights over 16 units:
   - D: 12/16 = 75%
   - R1: 3/16 = 18.75%
   - R2: 1/16 = 6.25%
3. Copy the selected registered gene ID unchanged.
4. Record genome, locus, child position, parent source, parental position, and gene ID in the trace.

For child `D`, total contributions are:

| Source | Probability |
| --- | ---: |
| Parent A D | 37.5% |
| Parent A R1 | 9.375% |
| Parent A R2 | 3.125% |
| Parent B D | 37.5% |
| Parent B R1 | 9.375% |
| Parent B R2 | 3.125% |

Sampling uses Park-Miller state plus rejection-based bounded integer selection. This avoids floating-point comparisons and modulo bias. Seed/state is explicit and injectable into pure generation; clients cannot provide authoritative genetics.

### 3.2 Explicit offspring R1/R2 compatibility policy

Exact historical Axie Classic generation rules for offspring R1 and R2 are not established by repository evidence. G2 therefore does **not** claim historical equivalence.

`CLASSIC_INHERITANCE_V1` adopts this deterministic Critterbound compatibility policy:

- Child R1 independently repeats the same `parent 50/50 -> parental D/R1/R2 12/3/1` selection.
- Child R2 independently repeats the same selection.
- Sampling is with replacement. One child locus may receive zero through three genes from either parent, and repeated IDs are valid.
- Each child position consumes its own parent and source-position draw, except a rejection sampler may consume extra raw RNG values at its deterministic rejection boundary.

Tradeoff: this preserves the existing triplet lifecycle, hidden-gene transmission, and simple traceability, but may differ from historical Axie recessive-slot construction. Changing this policy later requires a new algorithm ID; `CLASSIC_INHERITANCE_V1` outcomes must not be reinterpreted.

### 3.3 Policy gate

`InheritanceEngine.inherit` remains the legacy production entry point. `InheritanceEngine.inheritWithPolicy("CLASSIC_INHERITANCE_V1", ...)` exposes the new foundation. No breeding service, remote, egg writer, profile schema, or hatch path selects it in G2.

## 4. Expression and compatibility fallback

Classic ordinary expression is dominant-only:

1. Try the inherited `D` gene in the offspring class/species/rig context.
2. If compatible and legal, express it.
3. If incompatible or unable to produce a legal unique ability, use the existing deterministic canonical fallback for phenotype only.
4. Never inspect R1/R2 as ordinary phenotype alternatives under the Classic policy.
5. Never overwrite D, R1, or R2 during compatibility repair.

The expression trace reports `FALLBACK`; inherited genotype remains byte-for-byte unchanged. This permits an incompatible hidden or dominant gene to survive and be transmitted to a later compatible descendant.

Appearance keeps body-first resolution, species/rig/tag constraints, stable layer sorting, and canonical class fallback. Ability expression keeps fixed mouth/horn/back/tail ordering, curated cross-class support, duplicate rejection, canonical per-slot fallback, and exactly four legal CardCatalog abilities. `traits` remains a validated, inherited compatibility locus and resolves no fifth combat ability.

Legacy resolvers and legacy inheritance retain their existing behavior for production compatibility. Classic code calls the new dominant-only resolver entry points.

## 5. Class inheritance

`CLASS_INHERITANCE_V1` is separate from gene inheritance:

- same-class parents produce that class and consume no class-selection draw;
- mixed-class parents select A or B with equal probability using unbiased bounded integer sampling;
- result and parental source are traced;
- no hybrid or mutated class exists in G2.

Class and all parent data come from authoritative server records. Parent order can change a trace label but cannot change the distribution or expression rules.

## 6. Validation and lifecycle boundaries

Generation validates both parents before sampling and validates the child against gene content version 1 afterward. Validation covers exact triplets, all required loci, registered IDs, and locus/kind matching. Classic phenotype resolution must produce compatible appearance and exactly four legal abilities.

Production authority remains unchanged:

- remotes accept bounded IDs/commands, not classes, genes, outcomes, or RNG state;
- `Player.UserId` determines identity;
- profile mutation remains under `ProfileService.UpdateProfile` and ownership locks;
- conception stores genomes once; hatch does not reroll;
- current production breeding continues using legacy inheritance;
- current Critter schema 3, egg schema 1, profile schema, saved eggs, cards, combat formulas, and Blood Moon remain unchanged.

## 7. Determinism and tests

Required automated coverage:

- exact D/R1/R2 shape; unknown, wrong-locus, and unsupported-content-version rejection;
- fixed-seed output and complete source traces;
- both parent sources and hidden-position transmission;
- large deterministic sampling against 37.5/9.375/3.125% dominant-source expectations;
- multigenerational emergence of a recessive carrier into D;
- same-class and mixed-class policy behavior;
- incompatible D fallback without genotype rewriting;
- exactly four legal resolved abilities;
- eight cards per Critter and 24 cards per 3v3 team;
- unchanged Critter and egg schema compatibility.

Statistical tests use fixed seeds and explicit tolerances wide enough to avoid flaky random failures while narrow enough to detect wrong 75/20/5 weights.

## 8. Security and failure behavior

- Unsupported policy IDs and content versions fail closed.
- Parent genomes are fully validated before use.
- RNG is explicit, deterministic, server-owned, and bounded without floating-point probability checks.
- Stable arrays define all genetic iteration order.
- Traces are diagnostic values; G2 does not add them to persistent profiles.
- No client-controlled payload can author or repair genes.

## 9. G2 decisions retained through G4

1. Confirm or replace the Critterbound R1/R2 compatibility policy if authoritative historical Axie behavior is obtained. Any change becomes a new policy version.
2. Decide where explicit `geneContentVersion` and `inheritancePolicy` fields live in future Critter and egg schemas before content version 2.
3. Define durable conception seed/state metadata and compact trace/digest persistence.
4. Decide whether parent ordering should be canonicalized for seed derivation and lineage labels.
5. Complete lifecycle/migration rehearsal before selecting Classic policy in `BreedingService`.
6. Decide whether legacy fallback-repaired genotypes need audit tooling; G2 does not migrate or rewrite them.
7. Keep `traits` reserved or define its future non-card semantics. G2 preserves it unchanged.

Live enablement still requires separate approval after profile, egg, hatch, retry/idempotency, and
published test-universe validation.

## 10. G4 `MUTATION_POLICY_V1`

G4 adds `Server/Genetics/MutationEngine` as a pure post-inheritance stage. It is not called by
`BreedingService`, `InheritanceEngine`, any remote, or either bootstrap. The intended future pipeline
is:

```text
parent genomes
-> CLASSIC_INHERITANCE_V1
-> MUTATION_POLICY_V1 (separate server RNG stream)
-> GenomeValidator
-> GenotypeExpressor
```

`MutationPolicy.Default` is server-owned and frozen. It is disabled and carries the proposed test
probability as the exact fraction `1/10`; this is configuration, not an immutable gameplay rule. A
caller may provide another validated integer fraction. Live configuration or experimentation can be
added at a server composition boundary later without adding Roblox services to the engine.

Mutation walks stable registry order: seven appearance loci, then active ability loci `mouth`, `horn`,
`back`, and `tail`; each visits `R1` then `R2`. This gives exactly 22 eligible positions. `D` and the
entire reserved `traits` triplet are never visited. Each eligible position receives an independent
bounded integer roll. A successful roll builds the registered same-layer/same-locus candidate list,
sorts by gene ID, excludes the original ID, and selects through rejection-sampled bounded RNG. It does
not filter by current offspring class, so valid hidden carriers survive even when they cannot currently
express. Existing class, species, rig, tags, and curated cross-class metadata remain registry truth.

The engine validates the incoming genotype, clones it, mutates only selected recessives, and validates
the result. It returns a tagged result and never changes its input. Invalid policy versions, rates, RNG
state, dependencies, or genotypes fail closed.

For per-position probability `p`:

- expected mutations per conception: `22p`;
- probability of at least one mutation: `1 - (1 - p)^22`;
- at the proposed test rate `p = 0.10`: expected count is `2.2`, and probability of at least one is
  approximately `90.15%`;
- zero and multiple mutations remain valid outcomes.

Trace length is bounded at 22 entries. Enabled runs record one outcome per eligible position:
`NO_MUTATION`, `NO_ALTERNATIVE`, or `MUTATED`. Example successful entry:

```luau
{
	layer = "APPEARANCE",
	locus = "eyes",
	position = "R1",
	previousGeneId = "gene.appearance.eyes.stone.default",
	newGeneId = "gene.appearance.eyes.universal.bright",
	outcome = "MUTATED",
}
```

The enclosing trace records policy version, exact probability fraction, eligible and mutated counts,
overall outcome, RNG algorithm, and draw-count range. Raw RNG state is excluded from the trace. The
continuation state is returned separately to the authoritative server caller and is not projected to
clients or persisted in G4.

## 11. Decisions before G5

1. Approve a live mutation rate, rollout strategy, and whether Experience Configs should supply policy
   values at the server composition boundary.
2. Define authoritative mutation seed derivation and durable conception reproducibility metadata.
3. Decide whether compact mutation receipts or trace digests belong in a future egg/profile schema.
4. Decide how newly registered genes enter versioned mutation pools before gene content version 2.
5. Complete published test-universe lifecycle, retry, idempotency, and migration rehearsal before any
   `BreedingService` enablement.
6. Keep `traits` reserved until its non-card gameplay meaning and mutation behavior are approved.

G5 must not start automatically.
