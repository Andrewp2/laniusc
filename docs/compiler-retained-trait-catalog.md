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
| Producer kernels | `shaders/type_checker/trait_solver/retained/entries/00_mark` … `06_fill_jobs`, `02a`–`02c` (binding sort), `09_fill_words` |
| Publication kernels | `retained/publish.slang`, entries `07_publish_routes`, `08_publish_finish` |
| Route ABI | `retained/route_abi.slang` |
| GPU consumer (test) | `shaders/tests/retained_route_query.slang` |
| Host driver | `crates/laniusc-compiler/src/compiler/gpu_compiler/trait_solver/dispatch/retained.rs` |
| Catalog layout from counts | `trait_solver/catalog/retained.rs` |
| Batch layout from counts | `trait_solver/packet/retained.rs` |
| Entry points | `GpuCompiler::retained_trait_check`, `GpuCompiler::retained_trait_publish` (doc-hidden) |
| Test | `tests/retained_trait_catalog.rs` |

## Boundary

1. The host reads `rt_counts` (96 words) and sizes seven lane regions:
   declarations, parameters, terms, directory entries, trait records, uses
   and committed jobs. One lane handles one retained record.
2. Pass `00_mark` reads each committed job's (library, unit) from `rt_jobs`,
   including jobs with no declarations, and checks directory ownership. It also
   counts each trait's required members and marks callers that own a
   selected use. Pass `01_units` indexes the jobs by (library, unit).
   Passes `02a`–`02c` sort the impl bindings (see "Binding ranks").
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
   run. The solver's wave readbacks carry only the proof directory, the
   batch receipt, the planner state and the demand counters. The context,
   call, result and evidence rows are read only with
   `RetainedTraitOptions::read_rows`, which a test sets.
9. Pass `07_publish_routes` and pass `08_publish_finish` write the
   publication (see "Publication") in one more submit with no readback.

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
| 4 | `PARAM_OWNER` | a parameter without a committed owner, or an invalid binder entry; a composed binder whose slots in either domain are not the parent owner's slots in order followed by the entry's own parameters |
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

Code 10 also covers two bindings of one required symbol and an impl
whose sorted binding segment does not hold exactly its recorded count.

### Goals and skipped uses

A use is a goal when it is a direct or method call between committed
store callables and the callee has at least one applicable predicate. The
producer counts the other direct and method uses in two report fields.
`unsupported_callees` counts uses whose callee is not a committed store
callable, such as an extern or a trait member. `plain_calls` counts calls
whose callee has no applicable predicate. Neither kind has a batch row.

A predicate subject may be a scalar, a type parameter or a structural
type term. The parser accepts only the first two in a where clause. The
test covers a structural subject by rewriting a store record.

Each check runs over its own record and point lookups. The trait's
required-member count comes from one `InterlockedAdd` per member in pass
`00_mark`.

### Binding ranks

The solver admits an impl's methods in strictly increasing required
symbol. Pass `02a_sort_init` keys every trait record as (impl entry,
symbol, record); other records sort last. `02b_sort_step` is a bitonic
compare-exchange over a power-of-two width P ≥ the trait record count. The
host dispatches it log2(P)·(log2(P)+1)/2 times, one lane per key, with
(k, j) from a 256-byte-strided stage buffer. `02c_sort_finish` writes each
binding's sorted position, which is its method row, and each impl's first
row. Equal (impl, symbol) neighbours fail with `BINDING_COVERAGE`.
`02_count` checks that each trait impl's segment has exactly its recorded
binding count; a missing segment also fails.

The work is P·log2(P)²/2 compares, independent of any impl's width. The
removed per-binding scan cost B² per impl. The test asserts the step
count, a width below twice the record count, and strictly increasing
symbols for a 40-method impl whose source lists the methods in another
order.

The use fill ranks each environment binding by counting the callee
parameters with a smaller `ParamId`: k² reads for k ≤ 64 parameters
(`LIMIT` bounds each domain at 32). That per-environment rank is bounded,
not a sort over the whole catalog.

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
  bytes are never read. The catalog-owned output regions and the test
  poison are written by `09_fill_words`; the host uploads no arena-sized
  data.

The empty-unit regression exports an import-only job between the library
and application jobs, with no directory entry for that middle job. Its
job arena starts with one row, so the second job rolls back and retries
after growth. The test checks the three exact unit identities, rebuilds
with a different empty-unit identity in the same allocations, and rejects
a stale job-record generation. Before durable job records, the same
import-only job failed with `SNAPSHOT` despite a ready export.

The integrated catalog, retention, substitution and legacy generic-impl
checks passed (11 tests) under the GPU lock with one test thread. Logs and
the empty-unit negative control are in
`target/retained-catalog-publication-evidence/` in the integration worktree.

## Publication

`retained_trait_publish` returns a `RetainedTraitPublication` when the
solver ran. It owns the solver catalog arena, the packet (batch input,
output and proof store) and the route arena. Their workspace slots stay
reserved until it is dropped, so a later check cannot reuse them. The
solver remains the only selector. The publish kernels copy its result
rows, proof rows and substitutions; they choose nothing.

`view(store)` returns the exact byte range of each buffer and the identity
(catalog epoch, batch arena id, serial, store generation). It fails when
`store` has another `rt_counts` buffer or another build generation.
`status()` reads header words 8-10; production consumers need not call it.

The route arena (`route_abi.slang`):

| Region | Words | Contents |
| --- | --- | --- |
| Header | 48 | magic `0x52545231`, version 1, epoch, arena id, serial, generation, status (0 building, 1 valid, 2 failed; written last), failures, first failure, counts, region offsets, catalog table offsets, proof table offsets and admitted rows |
| Use map | 4 per retained use | call row + 1 (0: not a goal), first route, route count, call status |
| Routes | 8 per obligation | state (1 impl, 2 assumption), predicate atom, impl row, method first, method count, proof binding first, binding count, proof row |
| Atom ids | 2 per catalog atom | kind (1 `DeclId`, 2 `ParamId`, 3 `TermId`, 0 none), id |

The producer writes the atom ids with the catalog and the use map with
the batch. Pass 07 writes the routes and call statuses, and fails a route
whose proof row, substitution or binding span is outside the proof store's
admitted rows, or whose proof impl differs from the result's impl. Pass 08
requires a valid catalog receipt, a valid batch receipt of this serial and
a proof store of this identity. It then writes the proof offsets and the
status. A batch with a refuted goal has no valid receipt, so its
publication is `FAILED` and a consumer reads no route of it.

A GPU consumer checks the header magic, version and status. It checks the
identity it was given and that `rt_counts` READY is 1 and GENERATION
equals the header's. It then reads, without host help:

1. use map, then route;
2. impl atom (impl row word 0), then `DeclId`;
3. method row by binary search on the required symbol over the method span,
   then the callable atom (word 2), then `DeclId`;
4. proof bindings `[substitution, parameter atom, tag, payload, …]`: the
   parameter's `ParamId`, and for tag 3 the proof term node, whose NAMED
   nominal atom gives a `DeclId`.

These bindings are the impl's environment, the one the selected method is
specialized with. `shaders/tests/retained_route_query.slang` is this
consumer. The test asserts its answers against store records for 47
requests. These cover private, generic, nested-bound and constant impls,
an assumption, and all 40 members of the wide trait. The test also covers
fail-closed answers: another identity, READY cleared, a fresh build, and
a second live publication.

## Costs

These figures come from the test fixture on the development GPU: 2 units,
218 catalog atoms, 10 calls and 10 obligations, with a 40-method impl.

| Item | Value |
| --- | --- |
| Producer dispatches | 6 count passes, log2(P)(log2(P)+1)/2 + 2 sort dispatches, 7 catalog fills, 2 batch fills and up to 5 word fills |
| Publication dispatches | 2, in one submit with no readback |
| Dispatches, `retained_trait_publish` | 320 |
| Host round trips, `retained_trait_publish` | 4: store counters, producer state, admission receipts, one solver wave readback |
| Producer readback bytes | 640 (store counters 384, producer state 96, two receipts and state 160) |
| Host readback wait | about 4.5 ms per check |
| Rejected by the producer | count and sort dispatches, 2 round trips |
| Rejected by admission | 64 dispatches, 4 round trips (with `read_rows`) |

The solver's wave readback holds no semantic rows unless `read_rows` is
set.

The largest producer kernel is `02_count`, at 12694 inlined
instructions. No producer kernel uses local arrays.

## What is not covered

- Production discovery and projection do not bind the publication yet.
  Only the test consumer does. Discovery-wave producers must read routes
  and intern the impl environment as a store ENV term on the GPU.
  Projection then needs that ENV's TermId, which the publication does not
  write. Bound-member routing must map a member use (receiver plan in
  `rt_uses` words 6-7) to a route; trait-member callees are not goals
  yet (`unsupported_callees`). Native finalization still uses replayed
  sources.
- Slot resolution: dependency slot leaves fail (`SLOT`), so a publication
  never contains them.
- The catalog holds every committed term, not only the closure of impl
  heads, predicates and selected environments. Restricting it needs a
  GPU reachability pass over the term graph.
- The export does not complete a struct literal of a const-generic struct
  (`Grid { value: v }` for `Grid<T, const N: u32>`), so the test passes
  a `Grid<Local, 4>` value only as a parameter.
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
