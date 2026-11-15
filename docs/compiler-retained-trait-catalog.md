# Retained trait catalog

The GPU builds the program trait catalog and its bound goals from the
retention store ([program retention](compiler-program-retention.md)). The
existing trait solver then admits, checks and solves them. No host
`FrozenCatalog::freeze` runs, and the host writes no catalog or batch row.

This path is an opt-in consumer of the store. General compilation still
replays sources, and this path does not remove that replay. The list under
"What is not covered" names what still blocks that removal.

| Part | Location |
| --- | --- |
| Producer passes | `shaders/type_checker/trait_solver/retained/producer.slang` |
| Producer kernels | `shaders/type_checker/trait_solver/retained/entries/00_mark` … `06_fill_jobs` |
| Host driver | `crates/laniusc-compiler/src/compiler/gpu_compiler/trait_solver/dispatch/retained.rs` |
| Catalog layout from counts | `trait_solver/catalog/retained.rs` |
| Batch layout from counts | `trait_solver/packet/retained.rs` |
| Entry point | `GpuCompiler::retained_trait_check` (doc-hidden) |
| Test | `tests/retained_trait_catalog.rs` |

## Boundary

1. The host reads `rt_counts` (96 words) and sizes seven lane regions:
   declarations, parameters, terms, directory entries, trait records, uses
   and committed jobs. One lane handles one retained record.
2. Pass `00_mark` records each committed job's (library, unit). It also
   counts each trait's required members and marks callers that own a
   selected use. Pass `01_units` indexes the jobs by (library, unit).
3. Pass `02_count` runs every producer check and counts the rows each lane
   owns in 16 counters, one per solver table. Passes `03`–`05` compute an
   exclusive scan of those counters.
4. The host reads the producer state: the failure count, the first failure
   and the 16 totals (96 bytes). Any failure stops the check at stage
   `Producer`.
5. The host places tables 0-10 from the totals (`FrozenCatalog::retained_layout`).
   The catalog arena is cleared, or poisoned in tests. The fill kernels
   write every row at its scanned rank. The solver's catalog admission,
   coherence and native-recipe kernels run in the same submit.
6. One readback returns the catalog receipt, the recipe receipt and the
   fill-fault count. A rejected catalog stops at stage `Admission`.
7. The host places batch tables 11-16 (`prepare_retained_submission`) and
   uploads only the directory header. The fill kernels of the directory and
   use regions write contexts, assumptions, calls, environments, bindings
   and obligations. Then the solver's batch admission and proof waves run.
8. Results stay in the solver's output arena. `accept_submission` does not
   run. A test may read rows back with `RetainedTraitOptions::read_rows`.

Fill has two phases (`RC_CFG_PHASE`), and each one writes only its own
arena. The catalog phase runs before admission. The batch phase runs after
the batch arena is placed. All atoms, nodes, edges and roots, including the
roots of call environments, are in the catalog, so batch tables reference
only catalog rows and earlier batch rows.

## Identities

| Solver row | Retained source |
| --- | --- |
| Snapshot (table 0) | committed job ordinal: `[library, unit, job, build generation]` |
| Public nominal atom | `[1, library, unit, local]` |
| Private nominal atom | `[2, snapshot, local & 0x7fffffff, 0]`; the snapshot is the declaring unit's job |
| Binder atom | `[4, snapshot, namespace, local]` of each committed entry |
| Parameter atom | `[5, binder atom, domain, ordinal]`, scalar in word 4 for constants |
| Impl atom | `[7, snapshot, local, 0]` of each trait impl |
| Callable atom | `[8, library, unit, local]` of each free function and method |
| Predicate atom | `[11, snapshot, owner local, namespace << 24 | ordinal]` |
| Literal atom | `[12, scalar, lo, hi]`; a count is `[12, u32, count, 0]` |

A unit's private identities agree across units because every reference to
a declaration uses its `DeclId`, and the atom is a function of that
declaration's key and job.

Owners follow the composed binder. Own parameters take slots after the
parent's in each domain, types before constants. The applicable predicates
of an owner are its own block followed by its parent's. Environment bindings
are sorted by parameter atom, and parameter atoms follow `ParamId` order.

## Producer checks

The producer fails closed. `rc_state[1]` holds the minimum `code << 24 |
lane`.

| Code | Name | Raised for |
| --- | --- | --- |
| 1 | `NOT_READY` | `rt_counts[READY] != 1`, or `rt_counts[GENERATION]` differs from the generation the host read under the store lock |
| 2 | `SNAPSHOT` | a job ordinal out of range, two units in one job, one unit in two jobs |
| 3 | `UNIT` | a private nominal whose unit has no committed job |
| 4 | `PARAM_OWNER` | a parameter without a committed owner, or an invalid binder entry |
| 5 | `NOMINAL` | a nominal local word over 2^29; a NAMED term over a non-nominal or uncommitted declaration; a nominal application whose arguments do not fill its defining binder (type count, constant count, constant scalars) |
| 6 | `TRAIT_IDENTITY` | a bound or impl header that is not NAMED over the record's committed TRAIT |
| 7 | `TRAIT_ARITY` | a trait application whose arguments do not fill the trait's binder minus `Self`, including constant parameters and their scalars |
| 8 | `REQUIRED_MEMBER` | a binding whose required member is not a committed REQUIRED_MEMBER of the impl's trait with the recorded symbol; a required member whose parent is not a TRAIT |
| 9 | `METHOD_OWNER` | a binding outside a trait impl, or whose method is not a committed METHOD of that impl |
| 10 | `BINDING_COVERAGE` | an impl's binding count differs from its trait's required-member count |
| 11 | `ENVIRONMENT` | a use environment that is not the callee's, or that is incomplete in either domain |
| 12 | `SLOT` | a dependency slot leaf, or a term that contains one |
| 13 | `TERM` | an untranslatable term argument |
| 14 | `OWNER` | a predicate owner that is not a function, method or impl; a parent that is not an owner |
| 15 | `LIMIT` | an environment with more than 32 parameters in one domain |

Each check runs over its own record and point lookups. Binding placement
currently calls `binding_rank`, which scans the impl's full binding block
for every binding: an impl with B methods takes O(B²) comparisons. This
must be replaced before relying on this path for large catalogs. Coverage
equality bounds the count, and the solver's method admission rejects two
bindings of one required symbol (strictly increasing symbols). The trait's
required-member count comes from one `InterlockedAdd` per member in pass
`00_mark`.

## Trait-item-owned predicates

- A required member's own bound (`fn m<U: B>()` in a trait) needs
  required-member substitution, which the solver does not admit. The
  producer counts these in `unsupported_member_bounds` and emits no row.
  The check reports the count; it does not label those bounds ready.
- A predicate owned by a trait itself fails the check with `OWNER`.
  Neither kind has a solver row yet.

## Capacity, freshness and reuse

- Row tables are sized from GPU counts, so the producer never overflows
  them. The (library, unit) table starts at twice the job count, or at
  `RetainedTraitOptions::unit_slots`. When it is full, the GPU sets
  `rc_state[4]`, and the host doubles the table and runs every count pass
  again from the store.
- The check holds the store lock for its whole run
  (`ProgramRetention::with_store_buffers`). It creates its bind groups in
  that run and keeps none across store growth. It reads no substitution
  result, so it does not use `sb_consumer.slang`.
- Each check uses a new catalog epoch and a single-use packet. Solver
  storage comes from the compiler's reusable workspace. The catalog arena
  is cleared before fill and batch growth clears its new range, so reused
  bytes are never read.

## Costs

These figures come from the test fixture: 2 units, 55 atoms, 7 calls and 5
obligations, on the development GPU.

| Item | Value |
| --- | --- |
| Producer dispatches | 6 count passes + 7 catalog fills + 2 batch fills |
| Solver dispatches | 26 catalog and recipe admission dispatches plus the batch and proof waves; 291 in total for a solved check |
| Host round trips (solved check) | 4: store counters, producer state, admission receipts, one solver wave readback |
| Producer readback bytes | 640 (store counters 384, producer state 96, two receipts and state 160) |
| Host readback wait | 6–26 ms per check |
| Rejected by the producer | 6 dispatches, 2 round trips |
| Rejected by admission | 39 dispatches, 3 round trips |

The largest producer kernel is `06_fill_terms`, at 11278 inlined
instructions. No producer kernel uses local arrays.

## What is not covered

- The check returns a host report, including the solver's evidence
  readback. It does not yet expose an owned GPU publication for discovery
  or projection to consume after the check returns. Selection itself runs
  on the GPU; the next integration must preserve the packet's lifetime
  and expose its buffers without reconstructing routes from the report.
- Bound-member routing, native finalization and projection do not consume
  the selected evidence yet. They still use replayed sources.
- Uses whose callee is outside the store, extern, or a trait member are not
  turned into goals. Only direct and inherent-method calls between store
  callables are.
- Dependency signature slot leaves fail the check (`SLOT`). They need the
  dependency's committed binder mapping.
- Required-member own bounds and trait-owned predicates have no solver rows
  (see "Trait-item-owned predicates").
- The caller environment of a generic caller is admitted as assumptions
  from its applicable predicates. Soft contexts (kind 1) and replay
  contexts are not produced.
- A retained packet submits once. Appending calls to it after the first
  check needs a GPU producer for the later rows.
