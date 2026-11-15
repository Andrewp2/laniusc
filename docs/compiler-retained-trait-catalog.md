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
| Producer kernels | `shaders/type_checker/trait_solver/retained/entries/00_mark` … `06_fill_jobs`, `02a`–`02c` and `02g` (binding sort), `09_fill_words` |
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
   Passes `02d`–`02f` mark the term closure (see "Term closure").
3. Pass `02_count` runs every producer check and counts the rows each lane
   owns in 16 counters, one per solver table. Passes `03`–`05` compute an
   exclusive scan of those counters.
4. The host reads the producer state: the failure count, the first failure,
   the 16 totals and the closure words (112 bytes). Any failure stops the check at stage
   `Producer`.
5. The host places tables 0-10 from the totals (`FrozenCatalog::retained_layout`).
   The catalog arena is cleared, or poisoned in tests. The fill kernels
   write every row at its scanned rank. The solver's catalog admission,
   coherence and native-recipe kernels run in the same submit.
6. No readback follows the admission submit. The solver's first wave
   readback returns the catalog receipt, the recipe receipt and the
   producer state after the fill (`admission_state`), and the catalog
   judges them before it accepts the solve: a fill fault stops the check at
   stage `Fill` and a rejected catalog at stage `Admission`. A solve that
   fails before that readback leaves them to one explicit admission
   readback.
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
symbol, record); other records sort last. The sort is a bitonic network
over a power-of-two width P ≥ the trait record count, with (k, j) from a
256-byte-strided stage buffer. Steps with j < 256 stay inside one 512-key
block: `02g_sort_block` runs them in shared memory, one workgroup per
block, with the same compare-exchange network. `02b_sort_step` runs each
step with j ≥ 512, one lane per key. The host records one block pass for
every stage up to 512, then per stage k one dispatch per step j ≥ 512 and
one block pass: 3 dispatches for P = 1024 (settings) instead of 55. `02c_sort_finish` writes each
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

### Term closure

The catalog's atom, node and edge rows cover only the stored terms that a
solver row references, and their descendants. The other stored terms are
not checked, counted or translated. These fill writes are the roots:

| Reader | Roots |
| --- | --- |
| impl head (`fill_dir`) | the self type, and each argument of the trait application |
| predicate (`fill_trait`, function, method and impl owners) | the subject, and each argument of the trait application |
| selected use (`fill_use`) | each argument of the call environment |
| node (`fill_term`) | each argument of a NAMED, ARRAY, SLICE, REF or CC_CAST term |
| constant atom (`reference`) | for a u32 CC_VALUE that shares a CC_COUNT's atom, that CC_COUNT |

The trait applications themselves and the environment terms are not
referenced as roots. `count_dir`, `count_trait` and `count_use` check them
directly. Owner, parameter, callable, snapshot and native-recipe rows
reference no term.

Pass `02d_closure_roots` runs one lane per directory, trait and use
record and marks its roots. A mark is a compare-exchange on `rc_reach`.
The first marker appends the term to `rc_front`, so every term enters the
frontier once.

Each wave is two dispatches. `02e_closure_wave` is one lane: it takes the
terms appended since the last wave and writes an indirect dispatch.
`02f_closure_expand` runs one lane per term of that wave and marks its
children. The work is one lane per closure term and one mark per closure
edge. Empty waves dispatch no workgroups.

The host records 16 waves by default
(`RetainedTraitOptions::closure_waves`). If terms remain unexpanded after
the last wave, pass `02_count` sets `rc_state[24]`. The host then doubles
the waves and runs every count pass again, as it does for a full unit
table. Every wave binds the same buffers, so the host creates one bind
group per closure pass and reuses it for all waves. The closed instance
producer does the same for its BFS rounds, and the method routes create
one bind group per (kernel, config slot) for their fixed-point rounds.
`02_count`, `06_fill_terms` and `reference` treat an unmarked term
as absent. A reference to one has no translation, so the check fails
closed.

A referenced malformed or SLOT term still rejects the check. The same
fault on an unrelated stored term leaves the check solved, with equal
selections. The test asserts both. It also checks the node and edge counts
against a host closure over the store records (assertion only), checks
that the shared Local term has one node, and checks that a forced
one-wave start retries to equal rows.

Records still read by every check, each once:

- `02_count`, `03`–`05` and the fill passes run one lane per store record
  in all seven regions. A term lane outside the closure reads its head and
  mark, then returns.
- `00_mark` and `01_units` run one lane per record. `02d` runs one lane per
  directory, trait and use record.
- The binding sort covers every trait record.

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
  again from the store. A term closure that needs more waves retries the
  same way (`rc_state[24]`). Each attempt clears the marks, the frontier
  and its cursor.
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

The solver's result classification and proof kind are separate fields. A
generic impl can prove a goal conditionally by using an assumption for one of
its own bounds. Publication compares the result with the proof's classification
(word 7), then reads implementation bindings when the proof kind (word 0) is
an impl. A conditional impl proof is valid source evidence; discovery still
solves every concrete instance without assumptions before selecting its methods.

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
The same readback returns the store's `rt_counts`. `take_store_counts`
hands them, once, to the next consumer: discovery sizes its root pass with
them instead of reading the counters again.
The route header occupies 64 words. Publication reduces hard-refuted calls
to the smallest retained use and copies its `rt_use_spans` record to words
48–51. `diagnostic_span()` reads that record on failure, allowing the compiler
to render LNC0008 without reading or selecting among semantic rows on the host.

The route arena (`route_abi.slang`):

| Region | Words | Contents |
| --- | --- | --- |
| Header | 48 | magic `0x52545231`, version 1, epoch, arena id, serial, generation, status (0 building, 1 valid, 2 failed; written last), failures, first failure, counts, region offsets, catalog table offsets, proof table offsets and admitted rows |
| Use map | 4 per retained use | call row + 1 (0: not a goal), first route, route count, call status |
| Routes | 8 per obligation | classification (1 closed, 2 conditional, 3 refuted), predicate atom, impl row (absent for assumption proofs), method first, method count, proof binding first, binding count, proof row |
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
220 catalog atoms, 10 calls and 10 obligations, with a 40-method impl.
The closure holds 10 of 156 stored terms. Those are 8 of the 31 stored
node terms, with 8 edges. Three of the 16 waves had work.

| Item | Value |
| --- | --- |
| Producer dispatches | 6 count passes, log2(P)(log2(P)+1)/2 + 2 sort dispatches, 1 + 2·waves closure dispatches (33 by default), 7 catalog fills, 2 batch fills and up to 5 word fills |
| Publication dispatches | 2, in one submit with no readback |
| Dispatches, `retained_trait_publish` | 353 |
| Host round trips, `retained_trait_publish` | 3: store counters, producer state, one solver wave readback with the admission receipts |
| Producer readback bytes | 672 (store counters 384, producer state 112, two receipts and state 176) |
| Closure retry (one-wave start) | 3 attempts, 2 extra round trips |
| Host readback wait | about 4.5 ms per check |
| Rejected by the producer | count and sort dispatches, 2 round trips |
| Rejected by admission | 64 dispatches, 4 round trips (with `read_rows`) |

The solver's wave readback holds no semantic rows unless `read_rows` is
set.

The largest producer kernel is `02_count`, at 12845 inlined
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
- The catalog fixture passes `Grid<Local, 4>` only as a parameter.
  A separate retention readiness test covers const-generic struct literals,
  including an array field that fixes `N`. The earlier incomplete export
  came from the symbolic `N` syntax row in `Grid<T, N>`; the constructor's
  checked type was already correct. That row now retains its exact
  constant parameter identity.
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

### Direct-call discovery consumer

The native retained driver keeps the publication through discovery. Discovery
checks its identity and per-use proof status on the GPU, including proof under a
generic caller's declared assumptions. Header words 40–43 record the committed
source-store extent (directory entries, trait records, jobs and declarations),
so an export after catalog admission invalidates this consumer even within the
same generation. Appending substitution terms does not change that extent.
The publication is released after discovery completes. Bound-member method
selection still needs closed instance goals and concrete method routes.

## Closed discovery waves

`RetainedTraitPublication::solve_instances` reuses the admitted catalog for
new concrete instances. The kernels in `retained/closed/` read discovery's
`(DeclId, ENV, generation)` records, mark the closed binding terms, deduplicate
constant atoms, scan row counts and fill a fresh batch. The batch adds value
atoms, nodes, edges and roots (tables 1, 5, 6, 7), environments, calls and hard
obligations. It contains one closed context and no assumptions. The solver
checks all applicable predicates, including inherited impl predicates.

The host places storage from GPU totals and uploads directory headers. It
reads producer status and solver receipts, not goal or evidence rows. A
`ClosedTraitPublication` keeps the packet and proof arenas alive and requires
the original catalog publication when creating a view. Its route map is keyed
by discovery instance index, rather than the source publication's use index.
Multiple wave publications can coexist. A new build, changed source-store
extent, malformed ENV or stale instance rejects the wave.

Retained native discovery invokes this check before expanding each wave
that has new instances with closed predicates. Discovery's interner counts
those instances on the GPU, and a wave without one skips the producer and
the solver. Discovery passes the store counters from its own status
readback, so the producer does not read them again. The publication
receipt, read once after publication, also carries the status words that
`ClosedTraitPublication::status` returns.
This supplies concrete implementation evidence for bound-member routing;
the method-routing bridge is still being connected. Direct bounded calls
continue to check their source proof as well.

The producer scans live term slots, walks the reached graph in bounded GPU
rounds, and scans eight counters per term or instance. Constant atoms share
the catalog's identity when present. The first batch records 8 rounds. The
count pass sets producer state word 5 when the frontier is still pending.
The host then records twice as many further rounds and repeats the
idempotent constant, count, scan and total passes, up to 65 rounds in all.
A frontier still pending after 65 rounds is failure code 7, as before. The
settings app needs one batch per wave. The whole-term scans remain.

The counter scan (`closed/07_scan`) is a block scan in three dispatches
for any lane count: each 256-lane workgroup scans its lanes' two `uint4`
counter blocks in shared memory and writes its totals to `cw_blocks`, one
workgroup turns the totals into exclusive prefixes, and a last pass adds
each block's prefix. The result is in `cw_scan_a` (config word 7 is 0).
The Hillis-Steele scan it replaces took one dispatch per power of two of
the lane count (13 to 14 for settings).

Focused validation includes seven concrete calls, generic impl bindings,
constant arguments, a 40-method impl, concurrent wave publications, stale
instances, and a fault changing a previously proven Local binding to an
unimplemented i32. The native bounded forwarding fixture executes through
three concrete discovery waves with zero replay.
