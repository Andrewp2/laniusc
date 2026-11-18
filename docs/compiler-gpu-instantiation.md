# GPU generic instantiation

Native x86 and Wasm executable compilation use GPU monomorphization by default.
Each frontend unit is checked once and exports immutable typed templates into
one build store. Original objects contain nongeneric functions. The GPU finds
the closed generic instances, proves their obligations, substitutes their
terms, computes layouts, projects concrete bodies and lowers instance batches.
The GPU certifies calls and resolves provisional symbols before linking.

Source replay has been removed: there is no source-copy generator, replay
compiler request, host replay scheduler, replay input packet, source-blanking
path or replay object selection. A rejected instance reports its diagnostic;
it does not invoke another frontend. Allocation overflow grows the affected
buffers and retries from retained GPU data.

The implementation contracts are:

- [Program retention](compiler-program-retention.md): declaration and parameter
  identities, symbolic terms, schemas, use records and build lifetimes.
- [Trait catalog](compiler-retained-trait-catalog.md): GPU catalog production,
  coherence, obligation solving and guarded proof publications.
- [Substitution](compiler-retained-substitution.md): exact parameter binding,
  constant fits, memoized parallel evaluation and transactional capacity retry.
- [Projection and compilation](compiler-retained-projection.md): discovery
  routes, semantic checks, layouts, concrete lowering batches, caller ABI
  certification, native C linking, bounded output and Wasm.

The host allocates buffers, schedules submissions, observes status and capacity,
transfers opaque objects, and renders source diagnostics. It does not construct
instance source, select implementations, join instance environments or rename
instance symbols. Build generations invalidate retained semantic data; only
allocations and pipelines survive a fresh build.

## Verification checkpoint (2026-11-15)

After removing the source replay controller and shader inputs, 541 focused
compiler integration tests pass in one pinned run (320.06 s):
`compiler_generic_types_execution`, `compiler_instance_operator_execution`,
`retained_*` and `native_c_storage_execution`. They cover both default targets,
original `main`, cross-unit methods and traits, constants, records, arrays,
strings, matches, `?`, function values, C calls, ABI rejection, custom-device
compilation and rebuilding in reused storage.
Another 125 existing Wasm code-generation and bounded-entry tests pass
(14.72 s). Fifteen focused library tests pass (6.58 s), covering migrated
instance execution, solver workspace reuse, retained parameter metadata,
constant storage and option parsing. The first library run reported all tests
passing but stalled at process shutdown; its bounded rerun exited normally.
The frontend recording counter checks one recording per original unit plus
observed capacity retries. Projection and discovery tests check that they record
no frontend work. The old replay counter and its now-vacuous assertions have
been deleted with the path it measured.

The settings snapshot `212c54dce` has executed successfully through the public
default compilation path: two original units, 1,338 instances and 34,696
projected rows. Six consecutive builds each recorded exactly two frontend jobs
and produced one instance object. The last three full rebuilds took 360.910,
366.130 and 373.971 ms (median 366.130 ms). Each build resets the store; none
reuses compiled units or instances. The roughly 160 ms performance target is
not met.

Local receipts are in `target/retained-native-integration-evidence/`:
`settings-replay-removed.samples.json`, the corresponding compilation and
execution logs, `replay-pinned-tests.log` and
`pinned-replay-deletion/receipt.json`. The executable is
5,870,176 bytes with SHA-256
`93d566611dd8ede39229ea3a440f9a4df67acd5917300d101bad52510eec0c31`.
It runs `--frames 3 --scale 1` and exits 0.

## Historical prototype and architecture evidence

The checkpoints below describe the earlier selective-instantiation prototype
and the investigations used to replace it. Their replay paths and outstanding
integration work are historical, not the current compilation behavior.

## Architecture validation checkpoint (2026-11-14)

Independent code review found that the prototype's selective admission and
fallback machinery does not define a complete replacement. In particular,
job-local identities, template retention, implementation selection, symbolic
typing and capacity handling need explicit contracts. The replacement proceeds
through retained cross-unit interfaces and concrete semantic checks. Fewer replay bodies are not an
acceptance criterion for the complete replacement.

Three investigations now provide more specific evidence:

- **Cost:** a fresh trace of the integrated compiler at `3b38e1eb1`, with
  frozen settings sources at `212c54dce`, records one replay compile and
  5,073 GPU dispatches per measured build, 1,551 inside replay. Across three
  measured requests after three warmups, the replay compile's median wall
  duration is 35.756 ms. These are instrumented attribution measurements;
  replacement GPU work consumes some of that budget. All output bytes match
  the integrated baseline, and both compiled caches report zero hits.
- **Storage:** current projection helpers can relocate references inside a
  body, but preserve outside references because the copy shares its original
  job. Cross-unit projection also needs declaration, type, string-pool,
  nominal-layout, callee and diagnostic-file translations. Unit-qualified
  template segments with externalized references are the current proposal.
  Whole-build body residency is not an established requirement or a proven
  memory-safe assumption. Exact retained-template sizes remain unmeasured;
  source-token ratios are estimates, not memory bounds.
- **Types:** a diagnostic probe forces every settings instance-table entry
  through replay, then compares its realized types. It matches 1,331 replay
  copies, covering 127 functions and 34,528 rows. Five value-type differences
  identify a bound-member result in `core::function::enter_mapper`: the
  template retains the trait's `U` parameter, and slot-based substitution
  interprets it as the enclosing function's `T`. The producer fix below
  addresses this defect. The census identifies symbolic terms but does not
  validate ownership of every parameter leaf. The other two bare-parameter
  rows were subsequently identified as explicit `unwrap<T>` and `unwrap<U>`
  calls in `core::iter::eq_by`; both were already caller-scoped. One unresolved
  route remains unidentified.

The type probe does not establish complete template correctness: constant
generics, layout/ABI facts and negative diagnostics were not covered. Later
grammar inspection ruled out trait-provided bodies and nested definitions
as supported source forms. Its all-replay executable differs
from the integrated baseline and was not executed. No speed claim follows
from that probe.

The program GPU trait solver is the proposed single implementation selector.
Its current proof memo includes the call context in the key; equal closed
goals in different contexts do not automatically share proof work. Solver
term roots are also not canonical type identities: normalization allocates
fresh terms and equality compares their structure. A build-scoped type store
must establish exact interning independently. Any shared closed-goal proof
scope needs explicit admission and must preserve source ownership,
diagnostics and cycle rejection. Removing replay evidence transport is not
permission to remove those semantic checks.

Focused baseline hardware probes establish the existing replay-path behavior
for finite chains, recursion and deduplication. Chains of 17, 63 and 64 generic
functions execute correctly; 65 reports LNC0073 at the call requiring the
next body. A direct root call to the last instance lets that 65-function
chain compile, consistent with instance reuse. Mutual recursion executes;
growing `grow<T> -> grow<Wrap<T>>` reports LNC0073 at the recursive call with
a growing-type note. These probes do not establish depth behavior through
GPU-selected execution copies.

Local scripts, raw receipts and review qualifications are under
`target/instantiation-design-evidence/`. The symbolic-type probe and its
reverted diagnostic diff are under `target/e3-evidence/` in worktree
`t3-f221214e`. No production compiler change follows from these measurements
alone.

### Bound-member result scope corrected

`00_calls` now retains accepted bare-parameter call results, as it already did
for scalar and compound results. The preceding return-type materialization
had already substituted the bound correctly; semantic artifact projection
discarded that fact. The focused `Mapper<T,U>` fixture previously segfaulted
when instance-table lowering used the trait's slot as the caller's slot. With
the fix it executes successfully, and rigid-type and missing-implementation
diagnostics retain their existing codes and source calls.

A diagnostic-only settings comparison found all seven bare-parameter call
rows equal to their replay copies after the fix. This establishes the measured
defect's correction, not full template completeness. The producer change and
initial tests were committed as `266bebc49` and integrated as `eda69a6b0`.
The author ran 553 focused compiler tests and seven affected stdlib tests.

The new boundary guard checks bare parameter results only. Root review found
that repeating lexical name lookup rejected a valid inherited parameter under
method-parameter shadowing. A focused program succeeds before the guard and
fails with the initial guard. Validation now compares exact parameter identities
along the enclosing owner chain, and the fixture covers that case. Parameter
leaves nested in compound results still require a separate ownership audit.
On the integrated tree, six focused tests passed: the trait-return and generic
impl-forwarding modules, plus the existing inherited/shadowed method-bound
test. These include the new shadowing case and rejection diagnostics. All runs
used the shared GPU lock and one test thread; no broad suite was repeated.

### Concrete operator checks in selected copies

The discovery-input audit found missing value-row types and operator validation
in the selected-copy prototype. Baseline probes at `c1e85925f` reproduced them
in one job: `add<T>` at `f64` and `i32` exited 1, and mixed instances accepted
`bool` addition, an `i32` condition, `!` on `i32`, `str` equality and indexing
an `i32`. Forcing the same bodies into another unit invoked source replay,
which computed the result and rejected the invalid operands.

GPU passes now correct the selected path without demoting any body:

| Pass | Effect |
| --- | --- |
| [`03k1_project_literal_contexts`](../shaders/type_checker/calls/03k1_project_literal_contexts.slang) | A literal whose only context is a type parameter in its enclosing binder chain records that parameter as a symbolic context. |
| [`00_init`](../shaders/type_checker/semantic/expression_types/00_init.slang) | Such a literal has no template scalar, or its binding in an in-place or replayed body (published at the parameter's declaration token by `00f`). |
| [`01e_operator_refs`](../shaders/type_checker/semantic/artifact/01e_operator_refs.slang) | A symbolic literal row gets its parameter reference. An arithmetic, bitwise, negation or forwarding row gets the parameter reference of its first operand chain. The table substitutes both per instance, so a copy at `f64` lowers a floating-point add with an f64 literal. |
| [`06c_table_operands`](../shaders/type_checker/closure/06c_table_operands.slang) | One lane per virtual row checks the instance's realized types: literal kind, range and float status; binary operators, unary minus, `if`/`while` conditions, logical operands and indexing; returned, declared and assigned values. Errors are LNC0006, LNC0069 or LNC0070 at the template row's first token. |

`compact_expr` and `06c` use one rule set,
[`operator_operand_rules`](../shaders/type_checker/operator_operand_rules.slang),
which classifies a resolved struct, enum, array or slice operand instead of
treating it as unknown. This also rejects, outside generics, `-b` for a
`bool`, `ptr` or `char`, `s + s` and `-s` for a struct, `a + a` and `a == a`
for an array, a struct condition or `!s`, indexing a struct and a struct
index. Baseline compiled each of these; the struct and array arithmetic
crashed. A rule runs on an instance row only when an operand's type changed
under the environment. Focused tests are in
`compiler_instance_operator_execution`.

Probe results (selected copies, one unit):

| Program | `ba4a67c5e` | `e11330f16` alone | Now |
| --- | --- | --- | --- |
| `a+1` at `i64`, `u8`, `i32` | exit 42 | LNC0006 at `1` | exit 42 |
| `a+1.5` at `f64`, `f32` | exit 1 | LNC0006 at `1.5` | exit 42 |
| `a+1` at `f64` and `i32` | exit 1 | LNC0006 at `1` | LNC0006 at `1`, expected f64, found i32 |
| `2*a` at `i64` | exit 1 | LNC0006 | exit 42 |
| `-a` at `bool` beside `i32` | exit 42 | exit 42 | LNC0006 at `a` |
| `a+b` at a struct beside `i32` | exit 139 | exit 139 | LNC0006 at `a` |
| `return a*a` to `i32` at `f64` | exit 42 | exit 42 | LNC0006 at `a*a` |
| `a+1e39` at one `f64` instance (in place) | LNC0006, found f32 | not run | exit 42 |

An integer literal does not take a float context in a generic body, as
`x + 1` for `x: f64` does not outside one. A `LANIUS_TRACE=instance-table`
run of the first two programs shows every entry selected (3 of 3, 2 of 2) and
no replay. The design contract's "Operator and literal rows" section lists
the remaining gaps.

The follow-up pointer checks preserve integer literal types when the bound
context is `ptr`, including inherited operator results. Null comparisons and
pointer offsets therefore keep their ordinary rules and arithmetic widths.
The instance-operator tests cover both instance orders, nested arithmetic,
compound offsets, nonzero-null rejection, inferred struct/enum fields,
inherited impl parameters and sole-instance integer ranges. The scope guard
shares the exact-parameter lookup used for bound-member results; a different
declaration's same-named parameter cannot become a literal context.

Constant projection fits are another instance-time obligation. The local-call
fix in `2fbfb57fd` (integrated as `9bd027f52`) preserves a distinct failed-fit
status through GPU substitution. The mixed-projection overflow fixture now
reports LNC0006 at the inner argument whose length does not fit `u8`, including
through a forwarding generic. Uncalled, small and boundary-fitting cases
execute. A forced two-unit probe still reports the internal LNC0017 evidence
error for the overflow case; the retained cross-unit path must carry the
foreign source location to close that gap. See the
[constant fit contract](compiler-gpu-instantiation-design.md#constant-fit-status).

Root review found that looking back through the substitution memo could name
an earlier fitting projection: successful root substitutions are allowed to
miss the memo. A focused GPU probe reproduces that misidentification. The
failure now carries its exact projection directly from substitution, with
the caller retaining the slot and scalar. The GPU regression covers a missing
memo entry, a nested failed projection, and a successful substitution after a
failure. On the combined tree, all 14 constant integration tests and the two
focused canonical-identity and claim-publication GPU tests pass. The latter
fixture's missing slot-mask buffer was confirmed on the baseline and repaired
separately. These checks establish correctness, not a new timing result.

The proposed inherent-method reselection check was rejected after measurement:
a generic caller preserves its checked impl choice both in selected copies and
under forced cross-unit replay, even where a direct concrete call is ambiguous.
The replacement must preserve that template choice. Source grammar inspection
also removed nested definitions and trait default bodies from the required
surface; neither is currently supported.

Raw probes and qualified decisions are in `target/instantiation-design-evidence/`
(`semantic-probes`, `semantic-probes-followup`, `semantic-unit-probes` and
`discovery-parent-decisions.md`). They measured correctness, not compile speed.

### Sequential-job regression resolved

The replay prototype's larger allocations exposed an existing parser
initialization defect. Match-arm scatter initialized three match-payload
ownership columns only when debug rows were retained. An unowned pattern,
including a `let` binding, could retain a valid stale arm index and become a
bogus canonical match payload. Lowering then failed its function-block
contiguity check (reason 30).

`4f2545aee` initializes all three columns for every active node in either debug
mode. The author's alloc-vec/arena sequence passes with the fix and fails with
the old shader in the same build. The integrated focused GPU regression seeds
the columns with zero, a valid arm index and INVALID; it checks owned and
unowned patterns, both debug modes, direct/status-counted ranges and untouched
inactive storage. It fails on the old shader and passes on the fixed shader.
This repairs a parser invariant independently of the instantiation design.

## End-state architecture

The replacement is GPU monomorphization of typed intermediate code. Source
files enter the frontend to produce immutable templates for the current build.
Instantiating a template does not generate source text or invoke the frontend.

1. **Keep typed templates for the build.** Each definition has a unit-qualified
   identity and immutable HIR, side tables, symbolic type/constant references,
   definition contracts, and diagnostic source locations. Later units must not
   overwrite these buffers. A template is discarded when the build finishes.
2. **Discover the reachable instance graph on the GPU.** Root calls enqueue
   `(definition, canonical type arguments, constant arguments)` requests.
   Expanding an instance substitutes its environment into its calls and
   enqueues the callees. Structural equality deduplicates requests; selected
   implementation evidence accompanies the corresponding calls. Finite
   recursion reuses an existing instance. The worklist must finish or report
   an explicit semantic/resource failure; an arbitrary round limit cannot
   silently omit work or make a previously supported program invalid.
3. **Realize all type-dependent facts on the GPU.** Derive expression types,
   constant values, trait-method selections, receiver adjustments, native
   layouts, and parameter/result ABI facts under each environment. The GPU
   must check the obligations currently protected by replay admission.
4. **Build concrete execution rows on the GPU.** Counts and scans reserve
   disjoint ranges for each instance's HIR projection and side tables. Remap
   local references into those ranges; retain external declaration identities
   and original diagnostic locations. Root and nested calls target concrete
   instance identities. Concrete layout must precede LIR sizing and emission.
5. **Lower and publish the complete graph.** Lower ordinary functions and
   concrete instance rows through the existing GPU backend. Publish only when
   every emitted call has an admitted body, intrinsic, or external ABI target,
   and all required type, trait, and layout facts are complete. Remove the host
   source-copy builder, replay compilation loop, and semantic replay routing.

Compilation-unit boundaries do not bound this graph. The same instance key
and typed-template projection must work for a body in another unit. Combining
small programs into one unit is an optimization. Larger programs require
retained dependency templates and bounded batches of instance work; they must
not become unsupported merely because the one-unit optimization cannot apply.
The cross-unit template ownership and scheduling interfaces remain unfinished.

The host handles files, buffer allocation/transfers, GPU submission, requested
capacity growth, and artifact I/O. It must not select implementations, derive
layouts, or decide which generic bodies a call means. Capacity retries may
repeat GPU instantiation work, without manufacturing source or reparsing the
templates. Every new build reconstructs templates, instances, and evidence;
only allocation capacity and GPU pipelines may survive for reuse.

### Parallel execution contract

The instance graph exposes parallel work across both instances and the rows
inside each instance. Merely assigning one lane to a whole function is
insufficient: a large body or a wide call list would determine the dispatch's
completion time. The required scheduling shape is:

- **Discovery:** flatten each frontier into `(instance, template call edge)`
  tasks using edge counts and prefix scans. Resolve and enqueue independent
  edges in parallel, including edges from different compilation units.
- **Deduplication and ordering:** use GPU canonicalization with exact equality
  and scalable set/sort operations. Deterministic instance ordering and row
  offsets use parallel sorting and scans. An all-pairs instance ranking is not
  the final algorithm.
- **Semantic realization:** process ready `(instance, template row)` and
  type/layout tasks across the frontier. Shared type/layout facts are reused
  within this build. Unresolved dependencies produce further work; large
  variable-length relations expose element or field tasks instead of serial
  body-sized walks.
- **Allocation and projection:** compute per-instance counts in parallel,
  prefix-scan them into disjoint ranges, then scatter rows and side-table
  elements in parallel. A single lane may publish a fixed number of totals;
  it must not walk all instances to assign their ranges.
- **Control:** the GPU produces frontier counts, indirect dispatch sizes,
  completion state, and capacity requirements. Submission can operate in
  batches, with compact completion/capacity readback at batch boundaries.
  There must be no host round trip for each instance or call.
- **Bounded memory:** batch retained templates and instance rows without
  serializing independent work by source unit. Batch size limits temporary
  storage; it does not change definition identity or supported semantics.

Dependencies still impose sequential waves: a callee environment can depend
on its caller's substitution, and aggregate layout can depend on field
layouts. Available parallelism is the ready frontier within those waves.
The design does not promise unlimited parallelism or the timing target by
itself; dispatch overhead, memory traffic and the dependency critical path
must be measured.

Current migration code has explicit remaining bottlenecks:
`08b_exec_layout.slang` assigns ranges and propagates some failures on one
lane; `03_expand.slang` walks a function's call edges in one lane per
instance and its bound-member edges in a second lane, one wave apart.
`05b_table_rank.slang` splits each instance's key comparisons over eight
lanes. `06_table_rows`, `09_exec_rows` and
`09b_exec_tables` already expose row/element work. Performance validation must
include many small instances, a few very wide instances, and deep dependency
chains so one workload does not hide the others' scaling limits.

## Existing implementation

| Boundary | Current behavior | Source |
| --- | --- | --- |
| Reachable instances | GPU closure expands local generic calls and dependency summaries into closed environments. Overflow or unfinished depth leaves work for replay. | [`instance_closure.slang`](../shaders/type_checker/closure/instance_closure.slang), [`instance_closure_passes.rs`](../crates/laniusc-compiler/src/type_checker/instance_closure_passes.rs) |
| In-place instances | A private top-level function with one closed, direct environment can bind its existing rows. Calls requiring further generic replay prevent this selection. | [`04b_select_inplace.slang`](../shaders/type_checker/closure/04b_select_inplace.slang), [`01_mark.slang`](../shaders/type_checker/closure/01_mark.slang) |
| Multiple instances | The instance table realizes each local instance's expression types and resolves its callees. Execution rows copy the selected instances into the job's HIR, and native lowering emits them in the original compile. | [`instance_table.slang`](../shaders/type_checker/closure/instance_table.slang), [`table_rows.slang`](../shaders/type_checker/closure/table_rows.slang), [`07_table_calls.slang`](../shaders/type_checker/closure/07_table_calls.slang), [`instance_exec.slang`](../shaders/type_checker/closure/instance_exec.slang) |
| Replay | The host groups admitted environments, creates renamed source copies, and invokes another full compile. | [`body_specialization.rs`](../crates/laniusc-compiler/src/compiler/gpu_compiler/body_specialization.rs), [`instance_copies.rs`](../crates/laniusc-compiler/src/compiler/gpu_compiler/instance_copies.rs), [`typecheck.rs`](../crates/laniusc-compiler/src/compiler/gpu_compiler/typecheck.rs) |
| Publication | A private replay request checks definition provenance, selected implementation bindings, complete native layouts, call ownership, and fresh call admission before releasing its object. | `ValidatedReplayRequest` in [`native_session.rs`](../crates/laniusc-compiler/src/compiler/gpu_compiler/trait_solver/native_session.rs) |

`LANIUS_CHECK=instance-table` compares the table's expression types and call
routes with actual source-copy replays. It reports
entry coverage, failed rows, differing types, dependency calls, and unresolved
calls. These reports are diagnostic evidence, not a publication gate; agreement
does not establish complete native metadata. Such runs include extra GPU work
and readback and must stay outside timing samples.

### Settings diagnostic, 2026-11-13

One diagnostic compile used the baseline binary at the batch-16 checkpoint
(`2b9a1891c`, with temporary timing instrumentation) and settings sources at
`212c54dce7f70f644c774655307f3851bdec7df2`. Both compilation caches reported
zero entries and hits. The emitted ELF matched the ordinary baseline's SHA-256,
`9a79977bed5cdd50155021e24c6bb4dd1a7e9b145d7d185e884f70001a20e4d4`.

| Unit | Replay copies matched by table | Compared rows | Type differences | Unresolved calls | Dependency calls |
| --- | --- | --- | --- | --- | --- |
| Stdlib `0:0` | 191 / 1,154 | 5,816 | 8 | 192 | 0 |
| App `1:1` | 177 / 177 | 4,288 | 0 | 0 | 8 |

Neither table reported capacity flags or failed realizations. The eight stdlib
differences preserve the nominal identity and both type arguments, but the
table lacks a native-width witness that replay derives as two words. Another
20 stdlib return-row cache differences were reported separately. These findings
do not justify skipping native layout admission.

The app table covers every body in its replay, so it is a useful first native
lowering target. The stdlib table lacks 963 requested bodies; an original unit
cannot enumerate all environments that later callers require. Eliminating the
stdlib replay therefore also requires whole-program demand and retained typed
dependency templates. No timing claim follows from this diagnostic run.

## Execution rows

An original job with an instance closure builds the instance table and then
runs the execution-row passes at the end of type checking
([`instance_exec.slang`](../shaders/type_checker/closure/instance_exec.slang)).
Each selected table entry gets a copy of its template's HIR subtree:

| Copy | Placement |
| --- | --- |
| HIR rows | After the job's compact HIR rows |
| Tokens | After the job's token capacity, up to a quarter of it |
| Side-table rows | After each table's rows (call arguments, fields, match arms, match payloads, array elements, strings, parameters) |

A copied value that names a row, token or side-table row inside the template
names the copy's instead. Other values keep their original identity. The copy
has its own function row and source tokens, so lowering gives it its own
function, local, place, temporary and schedule identities and its own symbol
`(library, unit, 0x40000000 | token)`. The semantic columns of each copy hold
the instance's realized types: value types, scalar machine types, aggregate
declarations and widths, member offsets under a changed receiver, and the
function result. `09c_exec_counts` publishes the row counts lowering reads,
which include the copies.

Checked type rows are numbered after the type checker's token tables, and
lowering reads type rows and tokens in one id space. The type checker therefore
sizes its token tables for the job's tokens plus the copies' share, and
`08b_exec_layout` never places a copy's token at or past the first type row.

A method copy's receiver parameter has no written type. Its realized type is
the impl's self type under the environment, which the table stores at the
function row (`template_expr_ref` in `table_rows.slang`). Native lowering
reads it as the parameter type, so the copy's signature is closed and
`function_templates` emits it.

The table's realized types can name aggregates that no checked row names, such
as `Entry<i32, i32>` inside `Node<i32, i32>`. After the table rows are final,
`06b_table_expand_roots` pushes every closed realized aggregate into the field
closure that dependency summaries use (`ct_expand`). The closure creates rows
for its field types, so native widths derive for nested fields.

### Selection and fallback

`08_exec_select` admits an entry only when every rule holds. Any other entry
keeps its replay body, as before. The trace (`LANIUS_TRACE=instance-table`)
reports each entry's first failed rule.

| Status | Rule that failed |
| --- | --- |
| `0x100` table | The table and the closure are complete (no capacity, depth or closure flags) and the body is this job's. |
| `0x101` owner | The template is a file-level function or a method of an impl declared outside a trait or function, and is not instantiated in place. |
| `0x102` constants | The template has no constant parameters. |
| `0x103` syntax | The body declares no nested item or function. |
| `0x104` row | Every row's type realized under the environment. |
| `0x105` call | Every call is routed. A call of a local generic body, or a bound-member call whose receiver selects a generic method, names its callee's table entry. A method call's receiver dereferences under the environment as the template's did. Every other call keeps the template's callee and needs no type argument from the environment, as a variant constructor does. A call routed to a nongeneric method, a dependency-generic call and an unresolved call fail. |
| `0x106` fact | No index, iteration or array row and no function result changes to an array type. A member's receiver is a row of the body, and its layout under a changed receiver derives in `08a_exec_members`. A method call's callee member needs no layout. A raw view's realized element has a native width, and a struct literal's realized struct has no application-typed field (`08a_exec_members`). |
| `0x107` block | Each side-table block of the body is contiguous. |
| `0x108` capacity | The rows, tokens and side-table rows fit. An entry that does not fit, and every later entry, replays. |

On the host, `ExecRoutes` in
[`body_specialization.rs`](../crates/laniusc-compiler/src/compiler/gpu_compiler/body_specialization.rs)
routes a selected entry to its copy only when the entry's closure origin
passes the same admission as a replay request. The origin must target this
unit, `checked_replay_environment` must close its environment, and the
copy's symbol must be defined in the unit's object. The copy is then
registered as that environment's specialization, with the origin's layout
witnesses, so no replay is requested for it. A call row inside a copy calls a
selected callee entry's copy directly (`09_exec_rows`). An entry that calls a
rejected entry is rejected too (`08c_exec_callees`, and `08b_exec_layout` after
a capacity rejection), so a copy calls only copies. A call of a rejected entry
that the 17 rounds leave in a copy routes through that entry's admitted origin,
and an entry without one is a compile error, not a fallback. Selected entries
that do not route still replay. Their copies stay in the object as unreferenced
definitions.

Nothing in this path is retained between builds. The table, the copies and
their routes are rebuilt by every original job.

### Settings results, 2026-11-13

One profiled settings compile (`--profile`, `LANIUS_TRACE=instance-table`),
with every compiled-unit and library-instance cache cleared, as in the
benchmark. The baseline is commit `19c4be01c`.

| Unit | Table entries | Selected and routed | Replay bodies before | Replay bodies after |
| --- | --- | --- | --- | --- |
| Stdlib `0:0` | 191 | 114 | 1,154 | 1,040 |
| App `1:1` | 184 | 173 | 177 | 4 |

The build no longer replays 287 bodies. It still runs 2 replay compiles, one
for each unit, so no fixed frontend cost is saved yet. The settings ELF passes
the benchmark's x86-64 ELF check.

Timing used `tools/benchmark_settings_recompile.py` with 3 warmups and 7
measured requests, alternating the baseline and new binaries over two rounds.
Median wall times were 392.6 and 379.2 ms for the baseline and 367.5 and
410.0 ms for the new binary. The run-to-run spread exceeds the difference, so
these runs show no direction.

The app unit's 11 remaining entries are 7 owner rejections, mostly in-place
instances, and 4 call rejections. The 4 replayed bodies are
`ui_scene::reserve<T>`, which calls `v.try_reserve(count).is_err()`, and
`gpu::valid<T>`, which calls `core::mem::slice_len(view.values)`. Both call
dependency generics from a local template. To lower them, the closure must
expand dependency edges inside local generic bodies. `07_table_calls` must then
record the dependency instance, and the host must route `IT_CALL_DEPENDENCY`
calls in a copy through the library snapshot's closure origin. That removes
the app unit's replay compile.

## One program, one unit

Current optimization: a program compiles as one unit when it fits.
`whole_program_manifest` in
[`bounded_path_codegen.rs`](../crates/laniusc-compiler/src/compiler/gpu_compiler/bounded_path_codegen.rs)
merges the entry and every library it imports into one manifest when the
merged sources fit the resident limits. Type checking, the instance closure,
the instance table and the execution rows then see every generic body of the
program as local. A cross-unit instance becomes a local one. No typed
template, summary or instance is kept between builds or between units.

Reasons:

- The closure and the table already instantiate local bodies on the GPU.
  One unit gives them the library bodies without a second template format.
- A library unit cannot enumerate the environments its callers need
  ([Settings diagnostic](#settings-diagnostic-2026-11-13)). In one unit,
  every caller is in the same closure.
- Trait evidence and layout admission stay as they are. The host admits each
  copy through its closure origin, as before.
- Each replay compile runs the whole frontend again. Merging the units
  removes one replay compile from every multi-unit program.

Limits:

- A program above the resident limits stays multi-unit. Its cross-unit
  instances still replay. Deleting replay requires the dependency-template
  path described in the complete instance contract; rejecting a previously
  supported program is not an acceptable replacement.
- Library code is now checked through the local path. The local path had gaps
  that the dependency path did not have. This change fixes the ones the test
  suites reach:

| Gap | Fix |
| --- | --- |
| A bare match-arm variant that two imports provide, or that name lookup binds to another module's enum | `10m2` resolves it from the scrutinee's enum when that enum has a variant of the name. |
| A pattern variant of another local enum | `10m3` reports a mismatch. |
| A name that two module imports provide | `compact_calls` reports the ambiguity. |
| An unbound generic parameter of a bound call | `02_obligations` keeps the `03a7` report. |
| A payload-free variant argument ahead of the argument that binds its parameter | `03a1` drops a claim whose binding is a generic parameter out of scope at the call. |
| An entry file without a `module` line next to library modules | The semantic interface publishes an empty-path module for each unnamed module a declaration or implementation names (`interface_status` word 4, `01_identity_records`). |
| Two local implementations of one trait for one receiver, told apart by the trait's other arguments (`TryClone<i32,E>` for `i32`) | `09_route_bound_members` routes a replayed bound call to the one that the instance's evidence names. |
| A local struct literal with a missing or repeated field | `08_validate_aggregate_access` reports it (LNC0042), as `16_project_struct_literals` does for an imported record. |

Execution-row fixes found by the one-unit programs:

- A copy's token span ends at the next declaration's first token. Only a
  row's token end maps that boundary (`ex_token_end`). Before this, a call of
  the next declaration had no target.
- An incomplete closure (any `IC_FLAG_*`) flags the table (`IT_FLAG_CLOSURE`),
  so no entry is lowered from it. The closure runs 16 levels.
- `08a_exec_members` rejects a raw view whose realized element has no native
  width, and a struct literal whose realized struct has an application-typed
  field. Both replay.

### One program, one unit, 2026-11-15

The default native and Wasm path (`compile_retained_program` in
`retained_native.rs`) routes the manifest through `whole_program_manifest`. A
program that fits the resident unit limits compiles as one frontend unit,
whatever its libraries. A program above them keeps the bounded multi-unit plan.
Before, settings compiled as two units because the unit builder starts a new
unit at every library-id change (`UnitBuilder::should_flush_before`); capacity
did not split it (92 files, 1.8 MB, under the 5 MiB and 16,384-file limits).
Visibility is a module rule (`pub` or private), so one unit gives the same
diagnostics: a private library function called from the app reports the same
LNC0005 in one unit and in two
(`default_native_build_is_one_unit_and_keeps_library_visibility`).

One unit first measured slower (416 to 427 ms against 372 ms on `5cbc3456e`)
because the lowering workspace cache held one pipeline, and frontend and
instance lowering bind different input buffers. Each build reallocated the
workspace twice, and the reallocation grew with the merged unit's capacity:

| Reallocation | Per library ms | One unit ms |
| --- | --- | --- |
| frontend, wait for queued GPU work | 11 | 30 |
| frontend, allocation | 51 | 81 |
| instance lowering, allocation | 59 | 79 |

Instance lowering now runs as a variant over the frontend's resident arena
(docs/compiler-retained-projection.md, "Lowering workspace"), so neither
reallocation happens. Measured warm on settings, under the GPU lock, 9 builds
each after 3 warmups:

| Build | Units | Dispatches | Originals ms | Median ms | Tracked GPU buffers |
| --- | --- | --- | --- | --- | --- |
| per library, shared arena | 2 | 8,840 | 128 | 261 | 5.43 GB |
| one unit, shared arena | 1 | 6,864 | 89 | 212 | 9.48 GB |

Instances stay 1,338, and the executable links and starts. The tracked GPU
buffers grow by about 4 GB, because the frontend and lowering workspaces are
sized for the whole program rather than its largest library.

### One-unit results, 2026-11-13

Replay compiles and bodies, from `LANIUS_TRACE=instance-table`, with every
compiled-unit and library-instance cache cleared:

| Workload | Baseline `80f2f4908` | One unit |
| --- | --- | --- |
| Settings units | 2 | 1 |
| Settings replay compiles | 2 | 1 |
| Settings replay bodies | 1,044 | 964 |
| Settings dispatches | 10,853 | 6,285 |
| Language fixtures, replay compiles | 46 | 35 |
| Language fixtures, replay bodies | 273 | 203 |

On settings, 367 of 1,338 table entries are lowered in the job. The other 971
are 729 owner rejections (`0x101`, mostly methods), 191 call rejections and
51 fact rejections.

### Method instances, 2026-11-13

Methods of file-level impls are lowered as execution rows. Measured as above:

| Workload | One unit | Method instances |
| --- | --- | --- |
| Settings entries selected and routed | 367 | 993 |
| Settings replay compiles | 1 | 1 |
| Settings replay bodies | 964 | 338 |
| Language fixtures, replay compiles | 35 | 25 |
| Language fixtures, replay bodies | 203 | 104 |

On settings, the other 345 of 1,338 entries are 7 owner rejections (in-place
instances), 279 call rejections and 59 fact rejections. 268 of the call
rejections are calls of generic variant constructors, such as `Some(x)`.

### Calls inside copies, 2026-11-13

A copy's calls of generic methods and constructors are lowered with it:

- A generic variant constructor keeps its callee. Its value has the call's
  realized type.
- A call routed to a selected table entry targets that entry's copy: its
  virtual function row and first token. The template's target cannot be
  kept: a bound-member call's template names the trait's member, and a
  recursive call's target is inside the template's own tokens.
- An entry that calls a rejected entry is rejected too (`0x105`), since its
  copy would call a body that only a replay defines. `08c_exec_callees`
  moves these rejections one caller up per run and runs 17 times, one more
  than the closure's levels. `08b_exec_layout` repeats it after a capacity
  rejection.
- A method call's receiver parameter is the callee entry's realized
  receiver type. Its matched receiver is the copy's realized receiver after
  the template's dereferences.
- A call that the template leaves untyped, such as a method returning its
  impl's parameter, is typed by the callee's declared return type under the
  callee's instance environment (`untyped_call_result` in `table_rows.slang`).
- A method call's callee member names no field, so a changed receiver needs
  no member layout for it.

| Workload | Method instances | Calls inside copies |
| --- | --- | --- |
| Settings entries selected and routed | 993 | 1,136 |
| Settings replay compiles | 1 | 1 |
| Settings replay bodies | 338 | 195 |
| Language fixtures, replay compiles | 25 | 22 |
| Language fixtures, replay bodies | 104 | 104 |

On settings, the other 202 entries are 7 owner rejections (in-place
instances), 97 call rejections and 98 fact rejections. 85 of the fact
rejections are index rows whose element type the environment changes. 85 of
the call rejections are callers of a rejected entry. 10 are bound-member calls
routed to a nongeneric method. The fixtures lower more bodies than before but
replay as many, for the same reason.

## Complete instance contract

An instance identifies a stable template body, its ordered canonical type and
constant environment, and the implementation evidence required by that body.
Native widths are checked consequences, not parts of semantic identity. Equal
widths must never merge different nominal types, argument orders, or constants.

Retain immutable typed templates for the duration of **one build**. The input
includes compact HIR and its side tables, symbolic checked facts, type and
constant graphs, declaration identities, strings, and definition contracts.
`GpuHirView` and `OwnedGpuSemanticArtifact` describe much of this boundary, but
the current completed-unit record retains source and checked host facts rather
than a complete GPU template. Keeping buffer handles alone must not permit the
next unit to overwrite their contents. Release these templates when the build
finishes; reconstruct them on the next request.

GPU projection must produce the following facts for every emitted instance:

- Concrete parameter and result references, including implicit receivers;
  native widths, storage representation, array lengths and strides, struct
  field ranges, and enum payload ranges.
- Concrete expression references and constant values, retaining the defining
  declaration of every type and constant parameter.
- Complete checked call records: callee identity and environment, argument
  modes, result layout, receiver adjustment, matched and parameter types, and
  selected trait implementation evidence. A callee number alone is insufficient.
- Distinct local identities for parameters, mutable locals, temporary values,
  places, control-flow rows, and calls. Immutable nominal declarations and
  source locations retain their original identities.
- An admitted native symbol for each reachable instance, with relocations
  naming that exact environment. Every emitted call must have a body, intrinsic,
  or external ABI target authorized by its checked facts.

All required facts must close before publication. Unresolved substitutions,
missing implementation evidence, inconsistent native layout witnesses, growing
polymorphic recursion, and exhausted arenas must retain explicit failures.
The current closure's incomplete-table behavior is safe only because replay
finds the missing work; it cannot authorize partial native output.

## Native lowering boundary

The smallest useful change is a flat execution-row domain above semantic LIR:
ordinary executable rows plus `(instance, template HIR row)` pairs. Template
syntax stays immutable. Each execution row owns the current lowering columns
for function identity, LIR count and offset, value identity, and checked facts.
An intra-body HIR edge maps through its current instance; a global declaration
reference keeps its original unit-qualified identity.

An execution entry needs the source snapshot and template function range,
canonical environment, virtual-row base, declaration and parameter ranges,
schedule region, function ID, and qualified native symbol. GPU counts and scans
allocate these ranges. Keeping this schema in the design does not justify
adding unused runtime structs before the first executable consumer exists.

Today, [`project.slang`](../shaders/codegen/lir/semantics/instructions/project_semantic_values.slang) assigns
one function identity per HIR row, and
[`function_scatter.slang`](../shaders/codegen/lir/semantics/functions/scatter_semantic_functions.slang)
assigns one function per source token. Local/place identities also use source
tokens. Several instances of one template would overwrite these maps. Give
each instance disjoint parameter, local, place, and temporary ranges, and
project per-instance ranges for parameters, arguments, array elements, fields,
and match payloads.

Substitution and layout must finish **before** LIR counting: concrete aggregate
widths and receiver adjustments change how many rows an expression needs.
Cloning already emitted instructions cannot supply that information. Preserve
the existing lowering algorithms, but make their reads use the execution row
and its instantiated metadata.

Scheduling also needs an instance namespace. Its existing source-token regions
would interleave instances that share template tokens, breaking contiguous
function ranges. Either include function identity as the most significant
schedule component or assign each instance a disjoint region and translate its
template positions consistently. Keep the original source row in a separate
diagnostic column; backend ownership must use the execution row. String bytes
may be shared within a build, but each instance needs its own string-to-
instruction relation.

### Object symbol finalization, 2026-11-14

`GpuX86SymbolFinalizer` in
[`symbol_finalization.rs`](../crates/laniusc-compiler/src/codegen/x86/symbol_finalization.rs)
implements the native x86 finalization boundary from section 6 of the design.
General compilation does not call it yet.

| Item | Contract |
| --- | --- |
| Provisional identity | `(0xfffffffe, 0xffff0001, use ordinal)` |
| Instance identity | `(0xfffffffe, 0xffff0002, rank)` |
| Route row | `(library, namespace or unit, local, generation)`, dense by use ordinal, GPU buffer |
| Readiness row | `(generation, flags, instance count, use count)`, GPU buffer |
| Required flags | routes published (1) and caller/target ABI certified (2) |
| Host transfer | object-format symbol rows and identity bytes, from memory or a spilled object file |

Seven kernels in `shaders/codegen/x86/symbol_finalization/` run in one submission.
Each lane handles one object, route, symbol or identity word.
Identity lengths do not change, so no scan is needed.
The kernels reject a stale or unflagged readiness row and any missing route.
They also reject use-to-use routes, out-of-range ranks and uses, and provisional definitions.
Overlapping identity bytes are rejected too.
Each failure code keeps its minimum detail, so the reported failure does not depend on lane order.
Outputs are staged separately and sealed with the generation only after every check passes.
A small output capacity returns the demand; `finalize` grows staging and replays.
`GpuX86LinkInput` rejects any object that still names a provisional identity.

The transfer boundary checks that the route capacity fits its actual GPU
buffer and that readiness has a complete row before submitting. Installing
published columns checks every preserved symbol field and validates the new
columns before mutating the object, including for spilled objects. Two objects
with identical symbol layouts still require the caller to preserve their
association with the returned batch columns.

Tests: `codegen::x86::finalize::tests`, four hardware tests and one metadata test.
One links two finalized objects on the GPU and runs the program, which exits 42.
All five pass on the integrated retention/finalizer tree after the review fixes,
under the GPU validation lock with one test thread. They cover undersized route
and readiness buffers, mismatched symbol layouts and invalid replacement hashes
without modifying the original in-memory or spilled object.

Not covered yet:

- No producer emits provisional identities or writes the route and readiness rows.
- No GPU caller/target ABI comparison sets the ABI flag.
- The GPU library map does not yet keep ordinary libraries out of `0xfffffffe`.
  It must ship with the producer: manifests using that library ID remain valid,
  and their declarations need ordinary native identities after GPU remapping.
  Reserving that ID in source manifests is not an acceptable substitute.
- The admission-owned route constructor and a fresh generation per build are
  still required. The publication seal is observed only after the whole
  submission completes; a future GPU consumer must run after both emit passes.
- Wasm objects need the same stage over their symbol table.

## Executable milestones

Each milestone must execute programs through its new path and remove replay
work for the cases it claims. A new buffer or disabled pass without a consumer
does not complete a milestone.

1. **Establish table coverage.** Run the existing diagnostic comparison on the
   settings application and focused generic fixtures. Classify missing,
   differing, and unresolved facts before trusting the table. Include parameter
   and return contracts in the audit; their row-cache differences are currently
   reported separately.
2. **Lower local closed instances.** Implemented for file-level functions
   and methods of file-level impls without constant parameters (see
   [Execution rows](#execution-rows)).
   Introduce execution rows and complete the
   per-instance semantic projection. Start with local bodies whose calls and
   layouts close in the current unit. Emit two distinct environments of the
   same function, with separate symbols and storage, in the original unit
   compile. Compare execution and admitted facts against the existing replay
   path; do not bypass trait or layout admission.
3. **Close local instance graphs.** Calls between local function instances,
   including finite recursion, are routed. Methods of generic impls are
   lowered as instances, and so are method calls and bound-member calls
   that select a generic method. A bound-member call that selects a
   nongeneric method, and dependency generics called from a copy, still
   replay.
   Route calls between instances, including
   finite recursion, generic methods, and bound-member selection. Preserve
   implementation evidence and constant environments at every edge. Emit the
   complete reachable graph and remove its replay requests.
4. **Consume dependency templates.** Retain typed GPU templates until the
   whole-program catalog and implementation evidence are available. Expand
   instances of imported bodies using that catalog, including implementations
   declared in a different file or unit. Dependency summaries alone contain
   call edges, not bodies, so they cannot supply native lowering inputs.
5. **Replace replay publication.** Admit the instantiated call inventory and
   native layouts under the same definition and implementation contracts as
   `ValidatedReplayRequest`, with those semantic checks performed on the GPU.
   Once all supported instance paths use GPU templates, delete the source-copy
   builder and replay loop. Measure full warm settings rebuilds with all
   compiled-unit and instance reuse disabled.

The local milestones can reduce replay bodies before they eliminate an entire
replay submission. Report both quantities; fewer bodies alone do not establish
the saved fixed frontend cost needed for the target.

## Acceptance cases

- One function at two distinct scalar types; equal-width nominal types with
  different field order; nested arrays, slices, records, enums, and zero-sized
  values. Verify both computed results and independent mutable storage.
- Local and imported generic chains, repeated calls sharing one environment,
  finite recursion, and growing polymorphic recursion that fails explicitly.
- Method-owned and impl-owned parameters, explicit and implicit receivers,
  receiver borrows and dereferences, and const parameters owned by different
  lexical declarations.
- A caller, trait, self type, and selected generic implementation in separate
  files or units. Compare valid execution and rejection of missing or conflicting
  evidence with the replay route; native layout agreement does not substitute
  for trait evidence.
- Branches, loops, short circuiting, match payloads, early returns, and strings
  inside two instances of the same body. These expose ID and schedule collisions.
- Alternating full builds with different environments, rejected jobs, and arena
  growth. No typed template, instance, proof, or native definition may survive
  into the next build as compilation reuse.

Use the established `compiler`, `stdlib`, and `extended` test binaries and add
fixtures to their existing modules. Performance evidence must record the exact
source and compiler revisions, warmup and measured requests, cache settings,
replay count, and executable validation. The single-file benchmark does not
stand in for this cross-unit generic workload.
