# Canonical type IDs (design, 2026-10-13)

## Problem

Checked types are stored as *instance rows*: one row per type-expression
occurrence in source (keyed by token), plus private rows allocated past
source capacity by materialization and body replay. Rows are not
deduplicated, and a row's arguments may be declaration-side parameters that
only mean something under a *context* (an environment instance). So type
identity is decided by walking whole type graphs:

- `scoped_type_refs_equal` / `scoped_type_ref_hash` walk two graphs with
  per-thread stacks of 64 entries (and nested constant walkers);
- `instance_scoped_reference` re-interns a substituted type at every use
  site: hash the whole substituted tree, then run full scoped equality
  against each bucket candidate;
- materialization, expansion (`03e1`), closure checks and native layout
  (`01c`) are further stack walkers that call the ones above.

Measured consequences on the laptop (RTX 3070, NVIDIA 595.99):

- 167 of 850 shaders declare per-thread local arrays, up to ~30 KB per
  thread, which spill;
- the driver inlines everything, so these shaders take minutes to create
  (`03e1` did not finish in 15 min fully inlined; `01c` takes 121 s);
- with helpers kept out of line (`DontInline`), dispatches hang depending on
  which trivial leaf helpers are marked and on the input. There is no
  inlining policy that is both fast to compile and correct.

## Idea: hash-consing

Give every distinct type exactly one **canonical ID** (a `uint`), and store
each canonical type as a flat record whose children are canonical IDs:

```
ct_kind[id]    scalar | param | named | array | slice | ref
ct_head[id]    scalar code | parameter token | declaration token
ct_extern[id]  (library, unit, local) for imported declarations
ct_len[id]     canonical constant ID (arrays only)
ct_arity[id], ct_arg[ct_arg_base[id] + i]   canonical child IDs
ct_height[id]  1 + max child height
```

Because children are already canonical, identity is `==` on IDs, and the
hash of a record is computed from O(arity) words. Nothing walks a tree.
Declaration-side types are canonical too: their parameter leaves are
`param` records keyed by the parameter's declaration token, so `T` in two
different scopes never collides.

Constants (array lengths, constant generic arguments) get canonical IDs the
same way: concrete values by `(scalar, lo, hi)`, bare parameters by token,
projections as records over child constant IDs.

## Interning without locks or spinning

*Phase 0 design, superseded by the single-dispatch protocol in
"Implementation (P2)" below.*

Rows are interned one *height level* at a time, in rounds. A row is
*ready* when all its children have canonical IDs. Each round has four
dispatches, each doing O(arity) work per thread with no local arrays:

1. **propose**: every ready row writes its key (the flat record) to a
   candidate buffer, and computes its hash;
2. **claim**: probe an open-addressing table `ct_slot[]`. An empty slot is
   claimed by CAS-ing in `CANDIDATE | row`. An occupied slot is compared
   by key, either against a published record or against the occupying
   candidate's key, which is visible because it was written in dispatch 1.
   Equal means "map to the occupant"; otherwise probe on;
3. **publish**: each claimant allocates an ID, writes the record, and
   replaces its slot value with the ID;
4. **resolve**: rows that matched another candidate copy its ID.

Nothing ever waits for another invocation, so this is safe without
forward-progress guarantees. ID numbering depends on atomic order;
semantics do not.

The number of rounds is the maximum type height (the existing walkers
already cap depth at 64). Termination uses a changed-count readback, the
same way call inference does today.

## Substitution as a memo table

`subst(env, t)` is the canonical ID of term `t` with the parameters of
environment `env` (a canonical `named` application, or a generic function
instance) replaced by its arguments. It is computed in two sweeps over a
memo table keyed by `(env, t)`:

- **expand** (top-down, by depth): a request for `(env, t)` requests
  `(env, child)` for each child of `t` that contains parameters
  (`ct_closed` tracks this, so closed subterms map to themselves);
- **intern** (bottom-up, by height): build the substituted record from the
  children's results and intern it as above.

Field types of a nominal application are `subst(C, field_decl_type)`.
Monomorphization closure (today's `03e1` expansion) is the fixpoint
"request every field of every new closed nominal ID" until no new IDs
appear.

## Native layout by levels

`words(id)`: scalars are 1 word (`str` is 2), slices are
`NATIVE_SLICE_WORDS`, refs are 1, and arrays are `count * words(elem)`.
Structs are the sum of their substituted fields; enums are the
tag/overhead plus the maximum group sum. Each round, every ID whose
dependencies all have widths computes its own. That replaces `01c`'s walker
with one O(fields) thread per ID per round.

## Migration plan (incremental, measured)

Each phase keeps the generics matrix (`tools/generics_matrix.py`) passing.
Each records local-array bytes (`target/claude-work/local_arrays.py`) and
pipeline creation times.

0. **Canonicalize existing rows.** Add the canonical tables and
   `row_canon[row]` for source, seed and generated rows, plus a debug
   validation pass that checks `row_canon` equality against
   `scoped_type_refs_equal` on the fixture corpus. Rows with unsupported
   shapes get `CANON_UNKNOWN`, and consumers fall back to the old path for
   those.
1. **Layout.** Replace `01c_generic_native_words` with a lookup of
   level-computed widths (needs field substitution, phase 2's machinery,
   restricted to fields).
2. **Substitution and closure.** Replace `03e1` expansion and
   `instance_scoped_reference` with the memo table.
3. **Equality and hash consumers.** Replace `scoped_type_refs_equal` and
   `scoped_type_ref_hash` call sites (38 and 17 shaders) with ID
   comparisons, then delete the walkers and their local arrays.
4. **Constants.** Move constant identity (`inspect_constant_reference`,
   `concrete_value_words` and related) onto canonical constant IDs.

Non-goals for now: replacing body replay, or the type checker's inference
rounds.

## Implementation (P2, 2026-10-14)

This section describes what is built. `shaders/type_checker/canonical/`
holds the code and `crates/laniusc-compiler/src/type_checker/canonical_passes.rs`
holds the passes. The design sections above remain the motivation. Where the
two differ, this section is authoritative.

### Interning protocol: single-dispatch and lock-free

A lane interns a key in one pass, and no lane ever waits for another.

1. **Write the complete record.** This covers the key (`ct_head`, `ct_args`)
   and the facts (`ct_meta`, `ct_extra`). The record is allocated when the
   probe first reaches an empty slot (`ct_intern_key`), or it is a lane-owned
   *spare*.
2. **Release.** Call `DeviceMemoryBarrier()`.
3. **Publish.** `InterlockedCompareExchange(ct_slot[s], 0, record)` on the
   first empty slot of the linear probe sequence, which starts at
   `ct_probe_start(shash)`.
4. **Handle an occupied slot.** The lane issues `DeviceMemoryBarrier()`
   (acquire) and compares the occupant's record with its own key.
   - Equal: adopt the occupant's ID.
   - Different: probe on.
   - A lane that loses a CAS re-reads the slot it lost and continues the same
     way.
5. **Publish a candidate's state.** A release fence comes first
   (`ct_publish_candidate`). A lane that reads a child's reference from
   `canonical_row`/`atom`/`projection` and then fences (acquire) therefore
   sees the child's record, even if the child adopted a record that a third
   lane published.

Every table is declared `globallycoherent`. Slang 2026.2 emits the following
SPIR-V for these constructs:

- the memory model is `OpMemoryModel Logical GLSL450`;
- the tables carry the `Coherent` decoration;
- `DeviceMemoryBarrier` becomes `OpMemoryBarrier` with Device scope and
  semantics `0x848` (AcquireRelease | UniformMemory | ImageMemory);
- the CAS is a Device-scope `OpAtomicCompareExchange`.

No SPIR-V is post-patched. The protocol never needs forward progress, because
a lane only reads records whose publication it has already observed.

Allocation stays bounded:

- **Only a new key takes a record.** No candidate or dependency node owns a
  record. `ct_intern_key` probes the table, adopts an equal published
  record, and allocates (`ct_alloc_record`) and stores a record only when it
  reaches an empty slot. Count classes (`cc_intern_count`) and other small
  keys do the same through `ct_intern_small`. A re-interned candidate after
  a body replay (see Stages) therefore never touches its earlier key's
  record.
- **Losers keep their record.** A lane that loses the slot to an equal key
  keeps its record unpublished. A `spare` lane reuses it for its next key; a
  candidate lane interns one key, so its record is simply never referenced.
  Allocation is at most one record per key a lane publishes or loses.

**Gate (week 1).** Two tests in
`crates/laniusc-compiler/src/gpu/canonical_intern_stress_tests.rs` exercise the
protocol:

- `shaders/tests/canonical_intern_stress.slang` uses 1M lanes. Each lane
  interns one nested chain of 1–12 levels. A level is a slice, an array whose
  length is a count class, a 3–6-operand named type with shared leaves, or a
  reference.
  - Chains repeat 2^20 / {64, 4096, 65536, 2^20} times. Even seeds place equal
    chains in the same wave and odd seeds spread them across waves.
  - A second dispatch then rehashes every published record. It checks
    duplicates, broken probe chains and facts recomputed from the children,
    and walks each lane's result against its chain.
  - The live-record count must equal a CPU count of distinct keys.
- `canonical_intern_incoherent.slang` is the same protocol without coherence
  or fences. It is a negative control showing that the check detects
  failures.

Measurements:

| | runs | failures | intern dispatch |
|---|---|---|---|
| protocol (RTX 3070 laptop, NVIDIA 615.71) | 1000 (32 debug, 968 release) | 0 duplicates, 0 broken chains, 0 wrong facts, 0 unpublished | release: mean 4.9 ms, max 11.0 ms per 1M-lane run; debug: mean 9.9 ms, max 45 ms (submit to readback) |
| incoherent control | 16 | 8/16 runs with duplicates (up to 1.6M) or broken chains (up to 1.75M) | — |

**Decision:** the single-dispatch protocol is used, and the level-round
fallback (propose/claim/publish/resolve) is deleted. Rounds still exist, but
only because a candidate's children must be interned before it. Each round
interns every ready candidate in one dispatch.

To re-run the gate, use
`LANIUS_CANONICAL_STRESS_RUNS=N LANIUS_CANONICAL_STRESS_BASE=K cargo test -p laniusc-compiler --lib canonical_intern`
through the heavy lock.

### Records

Records live in four tables:

| table | contents |
|---|---|
| `ct_head[id]` | `uint4(kind \| arity << 8 \| type_slots << 16, w0, w1, w2)` |
| `ct_meta[id]` | `uint4(arg_base, height \| flags << 16, shash.lo, shash.hi)` |
| `ct_extra[id]` | `uint2`: per-kind facts (see below) |
| `ct_args[arg_base + i]` | canonical child references |

The record kinds:

| kind | words | args | extra |
|---|---|---|---|
| `CT_KIND_SCALAR` 1 | scalar code | — | — (IDs 1..17 are preseeded; no record) |
| `CT_KIND_NAMED` 2 | stable declaration (library, unit, local) | ordered operands, type and constant | (local declaration token or INVALID, constant-operand mask) |
| `CT_KIND_ARRAY` 3 | — | (element, length count class) | — |
| `CT_KIND_SLICE` 4 / `CT_KIND_REF` 5 | — | (element) | — |
| `CC_KIND_VALUE` 8 | (scalar, lo, hi) | — | (count or INVALID, count class) |
| `CC_KIND_CAST` 9 | target scalar | (symbolic child) | (INVALID, count class of child) |
| `CC_KIND_COUNT` 10 | count | — | (count, NONE) |
| `CT_KIND_ENV` 16 | (owner, type mask, constant mask); owner 0 is a call environment | bound type slots in slot order, then bound constant slots (typed IDs) | — (P3 `ct_subst`; a mask hole is an unbound slot) |

A reference is one of three things:

- a record ID in `[1, 2^30)`;
- a parameter leaf:
  - type parameters are `CT_PARAM_BIT | token`;
  - constant parameters are `CT_PARAM_BIT | CT_CONST_PARAM_BIT | token`;
  - parameters of a dependency signature add `CT_DEP_PARAM_BIT` and carry
    the declaration's slot instead of a token (`ct_dep_type_param(slot)`,
    `ct_dep_const_param(slot, scalar)`); their binder is the declaration or
    callee whose environment is applied, so they never equal a local
    parameter. A constant slot also carries its declared scalar in bits
    5..9 (`ct_dep_param_slot`, `ct_dep_param_scalar`), so a substitution is
    checked without the signature node;
- a sentinel: `CT_PENDING`, `CT_UNKNOWN` or `CT_NONE`, the three largest
  values.

Parameter leaves carry their declaration token, so `T` of two binders never
collides.

**Nominal identity.** A named type's key is its declaration triple.

- Local declarations use `(job library, job unit, interface index)`, where
  the interface index is
  `interface_public_decl_index_by_local[decl_id_by_name_token[token]]`.
  Declarations that are not exported use `CT_PRIVATE_LOCAL_BIT | local id`.
- The job's (library, unit) arrives in `TypeCheckParams.canonical_library_id`
  and `canonical_unit_id`. Jobs without a library use `0xfffffffe` for both.
- A declaration reached locally and through an import therefore has one ID.
  The bridge token in `ct_extra` comes from the local spelling in both cases,
  so the stored facts do not depend on which lane published the record.

**Constant identity is typed.**

- `CC_VALUE(scalar, lo, hi)` is the typed identity. `3u32` and `3usize`
  differ.
- `cc_count_class(id)` is the count identity. It is a `CC_COUNT(n)` record
  for any count-valid value, or the constant parameter itself. Array keys
  store the count class of their length, so `[T; 3u32]` and `[T; 3usize]`
  have one ID, as in the previous walkers.
- **Projections:**
  - a projection of a concrete count folds to `CC_VALUE` of the target
    scalar, once every level fits;
  - a symbolic projection becomes `CC_CAST(target; child)`, whose count class
    is the child's.

**Facts** are written at publish time in O(arity):

- `ct_height` is 1 + the maximum child height. Parameters have height 0 and
  scalars height 1. It is capped at 0xffff.
- `ct_flags` holds `CTF_TYPE_PARAM` and `CTF_CONST_PARAM`. `ct_closed(id)`
  means neither is set.
- `ct_shash` is a 64-bit structural hash built from kinds, key words and
  child hashes, never from IDs. It is deterministic across runs and jobs. It
  is the only identity allowed to leave the GPU or decide an ordering, for
  example symbol names, cache keys or sort keys.

### Invariants

1. **Uniqueness.** Two published records are never key-equal. Equal keys
   always yield the same ID within one job, so identity is `==`.
2. **Immutability.** A record is complete before its slot CAS, and it is
   never written again. Only a lane's unpublished spare is ever rewritten.
3. **Children first.** Children are canonical before their parent's key is
   built. `ct_args` holds IDs or parameter leaves, never a sentinel.
4. **IDs are job-local; `ct_shash` is not.** ID numbering depends on atomic
   order. Nothing that leaves the GPU, or that orders output, may depend on
   an ID.
5. **Sentinels.**
   - `CT_UNKNOWN` means the candidate has an unsupported shape (an
     unsupported kind, more than 32 operands, an invalid parameter or a
     capacity overflow).
   - `CT_NONE` means there is nothing to intern (an empty row, or a
     non-constant atom).
   - `CT_PENDING` never survives the last round.

### Rounds and termination

A candidate is a checked instance row, a constant atom or a constant
projection. A candidate is ready when all of its children have references.
The candidate's own lane interns it, and no lane waits for another lane's
result.

- **`00_clear`** empties the slots and sets every candidate and dependency
  node to `CT_PENDING`.
- **`01_intern`** performs one round.
  - Round 0 is a direct dispatch over all candidates: constants first, then
    rows from the last.
  - Rounds after that are indirect dispatches over the frontier list the
    previous round produced.
  - A candidate whose child is still pending appends itself to the next
    frontier.
- **`02_round_args`**, a single lane, closes a round:
  - it swaps the frontier lists and writes the next round's dispatch
    arguments;
  - if a round resolved nothing (a cycle) or the round limit
    `CT_MAX_ROUNDS = 64` is reached, the next round is *final*, and a final
    round turns pending candidates into `CT_UNKNOWN`.
- **The host records batches.** It records `CANONICAL_ROUNDS_PER_BATCH = 8`
  rounds, then copies `ct_counts` to a host-visible buffer.
  - It reads one done flag per batch: the pending count and the overflow bits.
  - It records another batch only while candidates are pending, so the number
    of rounds is the maximum candidate height (usually under 8, so there is
    one readback per stage).
  - Empty indirect rounds dispatch zero workgroups.

### Stages: dependency pages, early and late

Each job interns into one table, so an ID stays valid for the whole job.

- **Clear** (`00_clear`). It is recorded unconditionally after
  `type_instances.project`, ahead of the dependency pages.
- **Dependency pages** (`04_dependency_begin`, then rounds of
  `05_intern_dependency`). They run inside the per-page projection closure,
  after `dependencies.type_instances.project`, so each page interns its
  signature types (checked tag 5) while it is resident; a single resident
  page is interned once in the same place. Node `t` of a page is stored at
  `canonical_dependency_type[span + t]`, where `span` is the page's
  constant-type span base (`dependency_constant_type_span_base`), and that
  table persists across pages. The interface exports checked rows node by
  node in the rows' operand order, so nodes mirror rows: kinds 3..6
  (named, array, slice, reference) build the row keys, 9 and 10 the
  constant keys (`canonical_constants.slang`, shared with the checked
  constants), and 2 and 8 are slot leaves. A type alias node is its
  signature node (`canonical_type_roots`); function types (7) are
  `CT_UNKNOWN`, as rows have no function kind. An imported row and the
  signature node it came from therefore share one ID.
- **Imported alias targets** (dependencies/14a, substitution/08). A job
  with dependency pages clears the substitution state right after the
  canonical clear. On each page, 14a interns every imported alias use's leaf
  row on demand and substitutes the alias signature under it (`ct_subst`),
  publishing a pending target ID. After the last page, 08 realizes the
  targets as rows (twice with retry, then 08a reports a busy row). Alias
  normalization then rewrites rows 14a interned, so 14a sets
  `CT_COUNT_EARLY_REARM` and the early `03_rearm` re-arms every interned
  candidate, as a body replay's late one does; round 0 of `01_intern` clears
  the flag. An unchanged key adopts its existing record. The post-early
  substitution clear drops the rows 08 recorded.
- **Early** (`03_rearm`, then rounds). It is recorded unconditionally after
  the declaration refs (`type_instances.decl_refs_for_bindings`) and before
  `type_instances.index_closed_applications`. It interns the source rows and
  the constants that exist by then.
- **Late** (`03_rearm`, then rounds). It is recorded before
  `semantic_artifact.generic_native_words`. `03_rearm` sets every candidate
  that is `CT_NONE` or `CT_UNKNOWN` back to `CT_PENDING` and keeps the rest,
  and round 0 skips every candidate that is not pending. This stage
  picks up what was produced in between: materialized and generated
  applications, body specialization, generic call results, and constants
  published during inference.
- **Body replay re-interns.** A replay job (`body_specialization_inputs`
  has a type or constant argument) rewrites rows and constants after the
  early stage: 00f points `T` at the replayed graph, so `[T; 2]` becomes
  `[i32; 2]` in place. Its late `03_rearm` therefore re-arms every
  candidate. A candidate adopts an equal published record or takes a new
  one, so unchanged rows keep their IDs, and the early records stay valid
  for the references that still name them. A consumer recorded between the replay and the
  late stage would read early IDs of rewritten rows; none exists yet.
- Outside a replay, interned rows must not be rewritten afterwards. The
  cross-check at the end of the late stage reports a rewritten row as a
  false or missed merge (and the bridge self-check as a mismatch).
- Graph registration follows recording order. The clear is registered after
  `type_instances.project` and the dependency passes after
  `dependencies.type_instances.project`. The early passes are registered
  between the declaration refs and `type_instances.infer_imported_decl_refs`.
  That pass is recorded later (inside inference), so registering it after
  the canonical passes keeps its workspace from sharing storage with the
  canonical tables.
- Each page costs one readback when its rounds fit one batch.
- Call environments (`CT_ENV`) are interned by the substitution passes
  (`shaders/type_checker/substitution/`, `substitution_passes.rs`) once
  per inference round, after the early stage; they are not candidates.

### Capacities and overflow

No candidate or dependency node owns a record. A key the table does not hold
yet takes one at the first empty slot it reaches (`ct_intern_key`), and an
equal key found while probing is adopted. Scalar rows reuse the preseeded
IDs 1..17, and empty rows are `CT_NONE`, so neither takes a record.

Worst-case bounds:

- **Records:** 32 + 2 × (candidates + dependency nodes) + 4 × constant rows
  + the substitution producers' records (`substitution_canonical_extra`).
  - A candidate or node allocates at most once per stage it is re-armed in:
    the early stage, and the late stage again after a body replay.
  - Count classes add at most 4 records per constant row.
  - A lost race wastes its record. When the lanes of one wave intern the
    same new key, all of them miss and all of them allocate. The losers'
    records stay stored, but no slot or row references them, as with an
    unused spare. The waste is bounded by the concurrent attempts on one
    key, which the per-attempt bound already counts.
- **Slots:** the next power of two at or above 2 × records.
- **Arguments:** the checked argument storage, plus 2 words per row and 1
  word per projection, twice (a replay builds every candidate's key again),
  plus 2 words per dependency node (a signature tree has fewer edges than
  nodes), plus the substitution producers' words.
- **Frontier:** two lists of max(candidates, largest page's nodes).

A job starts at capacity scale 1. The records, the argument words and the
frontier lists start at 1/64 of their bounds, with floors of 4,096 records,
16,384 words and 4,096 frontier rows (`canonical_scaled_capacity`).

An overflow sets a sticky `CT_OVERFLOW_*` bit:

| bit | name | retries |
|---:|---|---|
| 1 | `CT_OVERFLOW_TABLE` | yes |
| 2 | `CT_OVERFLOW_RECORDS` | yes |
| 4 | `CT_OVERFLOW_ARGS` | yes |
| 8 | `CT_OVERFLOW_ROUNDS` | no |
| 16 | `CT_OVERFLOW_SUBST_MEMO` (`substitution/ct_subst.slang`) | yes |
| 32 | `CT_OVERFLOW_FRONTIER` (a frontier append past the end) | yes |

On a retrying bit (`CANONICAL_RETRY_OVERFLOW_BITS`):

1. The host abandons the job (`CanonicalCapacityOverflow`).
2. It doubles the scale, which is part of the resident cache key and only
   grows.
3. It records the job again.

At scale 64 the tables hold the worst-case bounds, so an overflow there is a
broken invariant and fails the job.

Debug variables:

- `LANIUS_DEBUG_CANONICAL_SHRINK=n` divides the records, the argument words
  and the frontier lists by 2^n to exercise the retry. It divides the whole
  bound, so a large `n` can fail at scale 64 on a valid job. On generics
  matrix probe p04, `n` = 12 passes after 4 retries and `n` = 14 fails.
- `LANIUS_TRACE_CANONICAL=1` prints the use per batch. Its `records=` count
  excludes the 32 preseeded records.

What stays capacity-sized:

- The per-candidate outputs (`canonical_row`, `canonical_atom`,
  `canonical_projection`), at 4 bytes per row, which consumers index by row.
- The round-0 dispatch over every candidate. A lane on an empty row returns
  at once.
- Shrinking these needs compacted `type_instances` rows.

Measured use at scale 1, 2026-10-15, harness build (late stage, after both
stages). No job retried.

| job | records | argument words | frontier rows |
|---|---:|---:|---:|
| 100-file generated project (29,956 lines), check | 267 / 133,166 | 375 / 352,842 | 33,284 |
| whole stdlib, one check job | 932 / 148,526 | 1,823 / 393,546 | 37,124 |
| generics probe (option results) | 130 / 4,128 | 191 / 16,384 | 4,096 |

Before compaction (2026-10-14), the generated project took 2,130,209 fixed
plus 86,538 dynamic records, and the stdlib took 2,375,969 plus 96,522.

The `ct_*` tables of the generated project at scale 1:

| | fixed records (2026-10-14) | records only for new keys |
|---|---:|---:|
| `ct_head`, `ct_meta`, `ct_extra` | 89 MB | 5.3 MB |
| `ct_slot` | 34 MB | 2.1 MB |
| `ct_args` | 1.4 MB | 1.4 MB |
| `canonical_frontier` | 17 MB | 0.27 MB |
| total | about 141 MB | about 9 MB |

The per-row outputs, at about 8.5 MB, are now most of what remains.

With the validator on, the generated project shows:

- 201 live records;
- no duplicates, broken chains, inconsistent facts, unpublished or pending
  states, or missed merges.

The validator's `false_merges` counts (133 on the generated project, 14 on
the option-results probe and 1,516 on the stdlib) still need a comparison
against a pinned build from before compaction (`tools/pin_laniusc.py`).

Record IDs depend on atomic order, so the old and new kernels cannot be
compared buffer for buffer. The CPU replay compare of captured `01_intern`
dispatches compares each candidate's `ct_shash` and resolved state instead,
which are ID-free, and finds them equal.

### Validation

Validation is enabled with `LANIUS_DEBUG_VALIDATE_CANONICAL=1`. It prints a
`[canonical_validate]` line per job, using the counter names in
`canonical_passes.rs`.

- **`88_validate_table`** (1.2k instructions) checks uniqueness and facts
  only. Per slot it checks for duplicate records, broken probe chains and
  facts that differ when recomputed from the children. Per candidate it
  counts pending, unknown and unpublished references, and per dependency
  node unknown and resolved ones (`unknown_dependency`,
  `resolved_dependency`, after the witness pairs).
- **`89_crosscheck_buckets` and `90_validate`** compare against the previous
  graph equality. Only `90_validate` imports `scoped_type_equality`, and it
  calls the walker at one site, with the checked graph on the left and the
  bridge graph on the right (21.4k instructions fully inlined, 13.8k
  before the bridge check; `01_intern` is 5.3k).
  - **Bridge mismatch:** the old walker rejects a row against its own ID
    read through the bridge (`bridge_mismatches`, after the dependency
    counters). Each row's whole bridged tree is compared, since a bridged
    record's operands are bridged too.
  - **False merge:** a row whose ID is another row's record while
    `scoped_type_refs_equal` says the rows differ. A top-level difference
    between a declaration token and an imported triple is the intended
    local/imported unification, and is counted as `normalized_merges`.
  - **Missed merge:** two rows of one coarse bucket (kind, arity, declaration
    spelling, type-operand IDs; constant operands are left out) that the old
    walker accepts but that have different IDs.
  - **Unknown rows:** rows whose candidate ended as `CT_UNKNOWN`.
  - A row whose ID is a dependency node's record (no row owns it) is
    confirmed against the next row of its bucket chain with the same ID,
    which chains every such row of the bucket.

### Bridge

`canonical_bridge.slang` is a read path from IDs to the checked graph's row
interface, not a second producer. `CanonicalBridgeTypeGraph` implements
`IScopedTypeGraph`:

- A tag-3 payload at or above `CT_ROW_BASE` (`0x40000000`) is the ID
  `payload - CT_ROW_BASE`. So is a constant reference of kind 1 (a value or
  a count class) or kind 3 (a cast), and `ct_ref` / `ct_constant_ref` map
  these back to the ID.
- Rows below the base go to `ScopedCheckedTypeGraph` unchanged. The bridge
  bounds them itself, so a bridged comparison passes
  `CT_BRIDGE_TYPE_CAPACITY` as the type capacity.
- Fields follow the checked rows: kind 1–4 for NAMED, ARRAY, SLICE and REF;
  field 1 is the local declaration token. Fields 7–9 hold the (library,
  unit, local) triple when there is no token. Field 2 is the operand count,
  fields 3/4 the element operand, and fields 5/6 either the named domains
  (type count, interleave flag, constant mask) or the array length.
- An imported reference to the job's own declaration reads as the local
  spelling, since both share one ID.
- An array length is its count class. A count reads as its u32 value, and
  the walkers compare lengths by count identity.
- Dependency slot parameters have no checked spelling and fail closed.
- `ct_bridge_operand(ref)` gives the checked (tag, payload) of any
  reference, with payload `INVALID` when there is none.

Consumers opt in by naming `CanonicalBridgeTypeGraph` where they name
`ScopedCheckedTypeGraph`. Kernels that do not import the module are
unchanged: no production kernel imports it yet.

The plan put the read inside `ScopedCheckedTypeGraph` itself. That would
add the `ct_*` bindings and the decode to all 37 of its importers, including
calls/ and codegen/, which are out of scope here. Every bridged read is
straight-line selects (about 230 instructions per call site), because the
old walkers expand a graph read at each site: 20 reads cost 90_validate
7.6k.

### Constant view (first consumer)

The dependency constant view (`dependencies/constant_view.slang`) is read by
materialization and by the canonical field walkers (02d, 02e, 03e, 03e1, 03k,
03k2, 14a, 01f2, 08 and their tests). It used to build a virtual overlay of
the dependency page node by node. It now reads canonical IDs:

- Dependency constant node `t` is `canonical_dependency_type[span + t]`. A
  constant parameter is its ID (a parameter reference above every source
  token, with slot and scalar in the ID); a value is `(1, CT_ROW_BASE + id)`
  and a cast is `(3, CT_ROW_BASE + id)`. `CanonicalConstantGraph<G>` decodes
  those with `ct_words` and `ct_arg`, and passes source rows and parameters
  through to `G`.
- A literal keeps its caller-owned source atom (checked against the
  record's value), so materialization can reuse it.
- Readers must run after their page was interned. In a job every consumer
  is recorded after the per-page dependency rounds. The boundary tests
  intern their fixture page first (`tests/canonical_type_boundary_intern`).
- Differences from the overlay: a projection of a concrete value is folded
  when interned, so its view root is a value (materialization publishes an
  atom, or reuses an equal one, instead of following the projection); a
  literal projection that does not fit its target is `CT_UNKNOWN` and fails
  as an invalid view (failure 4) rather than in the walker.

Materialization (`materialize_application.slang`) expands each constant and
identity walker once. Source constants and canonical constants share one
`materialize_checked_constant` site (through the canonical view's graph),
array lengths of new rows use the same site, and every lookup (the caller's
root rows, the checked index, then the lane's new rows) shares one equality
site per domain. Expansion (`expand_materialized_instance.slang`) passes its
visited rows as root candidates, so a field equal to a visited row resolves
to that row and the visited check is an ID comparison. 03e1 went from 474k
to 90k inlined instructions this way.

### Constant claims: typed and count identity

Call inference collects claims for each constant parameter slot
(`merge_inferred_constant_claim` in `type_checker/constant_constraints.slang`).
A claim is exact (`identity_mode` 0, from a constant argument) or a count
claim (`identity_mode` 1, from an array length matched against `[T; N]`).

- Two claims are compatible iff they have the same result scalar and equal
  identity: typed identity when both are exact, count identity when either
  is a count claim. In canonical IDs that is ID equality, or
  `cc_count_class` equality (a `CC_CAST` is transparent).
- The exact claim wins. A compatible exact claim replaces a retained count
  claim; between claims of the same mode the first one stays. The selected
  slot does not depend on the order of the claims.
- Merging discharges nothing. Every array actual keeps its own pending fit in
  its source graph, checked when the instance is normalized.

`tests/typed_constant_identity_requests` case 34 checks this: two array
claims of one symbolic count (`N as u8` retargeted to `u64`, then `N: u64`)
are admitted, then the exact claim `N: u64` is accepted and holds the slot. It used to expect
the exact claim to be rejected, which disagreed with the code.

### API (frozen for P3–P5)

The API lives in `shaders/type_checker/canonical/canonical_api.slang`. It is
not generic, and it imports `primitive_types` only.

| group | functions |
|---|---|
| classify | `ct_is_resolved`, `ct_is_record`, `ct_is_stored`, `ct_is_param`, `ct_is_type_param`, `ct_is_const_param`, `ct_is_dep_param`, `ct_is_constant`, `ct_type_param(token)`, `ct_const_param(token)`, `ct_dep_type_param(slot)`, `ct_dep_const_param(slot, scalar)`, `ct_dep_param_slot`, `ct_dep_param_scalar`, `ct_param_token` |
| read | `ct_kind`, `ct_arity`, `ct_type_slots`, `ct_words`, `ct_arg(id, i)`, `ct_named_decl_token`, `ct_named_constant_mask` |
| facts | `ct_facts` (height, flags, shash from one read), `ct_height`, `ct_flags`, `ct_shash`, `ct_closed`, `cc_count`, `cc_count_class` |
| map checked operands | `ct_ref(tag, payload)` (tag 1 scalar, 2 type parameter, 3 row or bridged `CT_ROW_BASE + id`, constant tags), `ct_row_ref(row)`, `ct_constant_ref(kind, payload)` |
| build and intern | `ct_key_begin`, `ct_key_reserve_args`, `ct_key_fold`, `ct_key_arg`, `ct_key_store`, `ct_intern(record, key)`, `ct_intern_spare(key, extra, spare)`, `ct_intern_small(kind, arity, words, args, extra, spare)`, `cc_intern_count(count, spare)`, `ct_intern_key(key)`, `ct_lookup(key)`, `ct_alloc_record`; `canonical_candidates.slang`: `canonical_build_candidate_key(candidate, final, key)` (intern its key with `ct_intern_key`) |
| hash | `ct_hash_mix`, `ct_hash_word`, `CT_HASH_SEED` |
| dependency nodes | `canonical_dependency_type[span + t]`, `ct_dependency_capacity`; `canonical_dependency.slang`: `ct_dependency_index(t)`, `ct_dependency_state(t)` for the resident page |
| bridge | `canonical_bridge.slang`: `CanonicalBridgeTypeGraph`, `ct_bridge_operand(ref)`, `ct_bridge_metadata(id, field)`, `CT_BRIDGE_TYPE_CAPACITY`; payload `CT_ROW_BASE + id` |
| constant keys | `canonical_constants.slang`: `ct_build_value(value, key)`, `ct_build_projection(target, child, param_scalar, fold, value, key)` |
| constant view | `dependencies/constant_view.slang`: `CanonicalConstantGraph<G>`, `CanonicalConstantEnvironment<G>`, `canonical_constant_view_reference`, `canonical_constant_view_ranges` (see Constant view) |

Producers in later phases (`ct_subst`, `CT_ENV`) build keys with the key
builder. They intern through `ct_intern_key` (a record only for a new
key), through `ct_intern_spare` with one lane-owned spare record, or through
`ct_intern` with a record they own.
