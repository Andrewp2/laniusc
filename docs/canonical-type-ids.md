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
   and the facts (`ct_meta`, `ct_extra`). The record is either the lane's
   fixed candidate record or a lane-owned *spare*.
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

- **Candidates use fixed records.** Candidate `c` owns record `32 + c`, so
  rows, atoms and projections never allocate.
- **Dynamic records come from small keys.** Count classes (`cc_intern_count`)
  and other small keys use `ct_intern_small`. It looks the key up first and
  stores a record only on a miss.
- **Losers keep their record.** A lane that loses the race keeps its record as
  a `spare` and reuses it for its next key, so allocation is at most live
  records plus lanes.

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
| protocol (RTX 3070 laptop, NVIDIA 615.71) | 32 | 0 duplicates, 0 broken chains, 0 wrong facts, 0 unpublished | mean 9.9 ms, max 45 ms per 1M-lane run (submit to readback) |
| incoherent control | 16 | 8/16 runs with duplicates (up to 1.6M) or broken chains (up to 1.75M) | — |

**Decision:** the single-dispatch protocol is used, and the level-round
fallback (propose/claim/publish/resolve) is deleted. Rounds still exist, but
only because a candidate's children must be interned before it. Each round
interns every ready candidate in one dispatch.

To re-run the gate, use
`LANIUS_CANONICAL_STRESS_RUNS=N LANIUS_CANONICAL_STRESS_BASE=K cargo test -p laniusc-compiler --lib canonical_intern`
through the heavy lock.
