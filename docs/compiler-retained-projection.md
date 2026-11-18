# Retained instance projection

Retained projection turns closed instances of retained generic templates
([program retention](compiler-program-retention.md)) into native x86 object
code. It substitutes each instance's row, signature and use terms with the
[retained substitution](compiler-retained-substitution.md) engine, realizes
layouts on the GPU, projects the rows into the existing lowering inputs and
runs the existing lowering pipeline. It never runs a frontend, never lexes or
parses instance text and never calls source replay. A retained native build
(see "Native compilation") uses it with discovery and the original objects.
Native x86 and Wasm executable entry points use it by default, including native C
linking and bounded file output. Both targets share discovery, substitution,
semantic checks, ABI certification and GPU symbol finalization; only lowering
and linking depend on the target.

This document is the boundary contract. Implementation status and test
receipts are at the end.

## Producer contract

Discovery (or a test producer) writes three GPU buffers and owns them. The
host never writes a row of them.

### Instance records, `pj_instances`

Two uint4 per instance, indexed by **rank**. Ranks are dense, `0..count`,
and are the final deterministic order (declaration keys, then structural
environment order). Rank is the native instance symbol:
`(NATIVE_RESERVED_LIBRARY, NATIVE_NS_INSTANCE, rank)`
(`codegen/x86/finalize.rs`).

| Word | Contents |
| --- | --- |
| q0 | `(callable DeclId, closed ENV TermId, generation, flags)` |
| q1 | `(first route row, route count, 0, 0)` |

- The instance identity is `(DeclId, ENV)`. The ENV is a stored, closed,
  normalized `ENV` term whose owner word is the DeclId, the form the
  substitution engine accepts and publishes. Two ranks with one identity are
  rejected (`DUPLICATE`).
- `generation` is the store build generation (`rt_counts[78]`).
- `flags`: bit 0 `ENTRY` marks the program entry instance. An entry has no
  parameters. This exists for tests whose program root is an instance.
  Production roots are original objects whose provisional use symbols the
  GPU finalizer rewrites.
- The callable must be a committed, complete `FREE_FN` or `METHOD` with a body segment.
  Only generic bodies have a segment
  ([program retention](compiler-program-retention.md), "Nongeneric bodies"),
  so the instances are generic instances. A use inside a nongeneric body
  whose environment is closed is a discovery root.
- Projection does not depend on the rank order. Errors are reported in
  (rank, row) order, so a producer with a deterministic rank order gives a
  deterministic first error.

### Routes, `pj_routes`

One uint4 per `(instance, use)`, at `q1.x + use ordinal`. The use ordinal is
the use's index in the callee's use block (`rt_dir` d2.w .. + d3.x), which is
also the body row's `r3.y`. `q1.y` must equal the block's use count.

`(library, namespace or unit, local, generation)`, the finalizer's route-row
format:

- an instance: `(NATIVE_RESERVED_LIBRARY, NATIVE_NS_INSTANCE, rank, gen)`;
- an ordinary `DeclNative` callee: `(library, unit, local symbol, gen)`,
  which must equal the callee's declaration key words `(x, y, w)`;
- a use that is not a call (record literal, constructor):
  `(0xffffffff, 0, 0, gen)`.

Projection validates every route of a call before publishing: generation,
range, and identity. An instance route must name a rank whose DeclId is the
use's callee and whose ENV equals the use's ENV substituted under the
caller's ENV (exact TermId). Each argument's substituted type must equal the
target's substituted parameter type, and the call row's type must equal the
target's result type. Exact closed types imply equal argument and result
ABI. Projection never chooses a target or a fallback. Bound-member uses need
a route from the trait solver's evidence; projection checks the route the
same way and does not select an implementation.

### Readiness, `pj_readiness`

One uint4 `(generation, flags, instance count, route count)`. Flags bit 0
routes published, bit 1 ABI certified by the producer. Projection requires
bit 0; bit 2 records discovery's bounded-direct-call proof admission. It checks the generation and the counts against the buffers, and
performs its own signature check (above) regardless of bit 1.

The GPU validates this header even when the instance count is zero. A
count larger than its buffer returns `INPUT_CAPACITY` before substitution
or lowering (detail 1 for instances, 2 for routes). The producer must grow
its buffers and rerun; projection never accepts a truncated prefix. A
current, ready header with zero instances produces no objects.

## Stages

All semantic work is GPU lane work. The host allocates, records, submits and
reads the plan totals, then the check status with the first error and batch
maxima, the batch table, the projection substitution's status words and the
schema rounds' status, all in one readback. It reads no instance, term, row
or route. The requests, the substitution, the schema rounds and the check
are recorded back to back after the plan readback; see "Schema rounds".

In a native build, discovery publishes without reading the status of its
ranking and publish passes (`RetainedDiscovery::defer_final_status`). Those
passes write the projection's and the roots' readiness only when nothing
failed, so the plan rejects the inputs of a failed discovery; the build then
reads discovery's status (`final_failure`) and reports discovery's error.
The plan readback is the first one after the last discovery wave.

| Kernel | Lanes | Work |
| --- | --- | --- |
| `00_plan` | one per rank | validate readiness, the record and the directory entry; insert the identity; write the rank plan and counts |
| `01_scan` | one workgroup | exclusive scan of rows, tokens, seven side tables and requests |
| `02_requests` | one per request | `(DeclId, ENV, term, tag)`: result, parameters, rows, use environments, use results, matched receivers and receiver parameters |
| substitution | engine | a chain of one run (`begin_chain`, `record_chained`); a run that does not publish runs again on the full path (`RetainedSubstitution::run`), where capacity overflow retries inside the engine |
| schema round, plan, scan × 3, size, requests, substitution, consume | one per new stored term or schema record | realize fields/payloads under the nominal's binder; repeat for newly created nominal types |
| `03a_layout_init`, `03_layout` × 32 | one per TermId | closed struct, array, slice and reference layouts and the lowering type tables, indexed by TermId |
| `03b_type_arguments` | one per TermId, up to 32 operands | publish nominal arguments and typed constant atoms for lowering |
| `04a_rows_init`, `04b_edges` | one per global row | clear row facts; expression parents |
| `04c_string_scan` | one per global row, logarithmic scan steps only when strings exist | exclusive decoded-word offsets in instance/row order |
| `05_check` | one per global row | forms, types, literal, operator and destination rules, record literals, members |
| `05c_calls` | one per global call row | accepted result, route, receiver plan and complete target signature |
| `05b_report` | 1 | first error in (rank, row) order, or CHECKED |
| `06_batch_plan` | one per batch | rank range, rows, tokens and side tables of each batch; maxima |
| `07_rows`, `08_side`, `09_batch_finish` | one per batch row / side row / 1 | lowering HIR and semantic columns, lowering counts |
| `08b_string_bytes` | one per decoded word | compact batch string pool; binary search of row offsets finds each source word |
| lowering | existing pipeline | `GpuCompiler::lower_projected_x86_batch`: semantic LIR, optimization, x86 object |

Every rank is checked before any batch is projected, so a rejected run
publishes no object. A batch holds the ranks whose first global row is in
`[b × batch_rows, (b + 1) × batch_rows)`. Instance rows are contiguous in
rank order behind one root row. Every call, also inside one batch, is a
dependency symbol call to the route's identity, so a call names the same
symbol in every batch, and the linker resolves calls across batches.

### Lowering behind the check

When the plan predicts one batch, the batch and its lowering are recorded
before the check is read back, so the GPU lowers while the host waits for the
check. The check's readback is mapped after its submission, the lowering's
submissions follow it, and the host waits for the map last. In a native build
the finalizer and the resident link plan are submitted behind that lowering
(`retained_native.rs`, `InstanceLowerer`).

- **Sizes.** The batch kernels and the lowering are sized from the plan's
  totals, which bound every batch: rows + 1, tokens + 1, and the largest side
  table total. The string pool uses the string column's capacity. The
  configuration words `PJ_CFG_ROW_CAP`, `PJ_CFG_TOKEN_CAP` and
  `PJ_CFG_SIDE_CAP` hold these sizes, and `08b_string_bytes` stops at the
  string column's length.
- **Gate.** `09_batch_finish` passes the batch only when the check reached
  `CHECKED` and the batch fits those sizes. Otherwise it publishes zero
  lowering counts, so the lowering recorded behind it finds no rows. It writes
  its verdict to status word 60 (`PJ_S_GATE`), which comes back in the check's
  readback.
- **Host.** After the check loop, the host keeps the lowering when the verdict
  passed, the check produced one batch and the batch's tokens fit. It then
  reads the lowering back as before (`BatchLowerer::finish`). If the check
  loop runs again (a substitution rerun, schema rounds resumed, layout or
  pattern rounds grown) or the gate failed, the host drops the lowering
  (`BatchLowerer::discard`). It then lowers the batch after the readback with
  the sizes the check reported, and grows the columns to them. A discarded
  native lowering also submits the finalizer again, because the finalizer may
  have read root readiness before the check certified it.
- **Tests.** `retained_native_early_lowering_retries_after_a_failed_gate` and
  `retained_native_early_lowering_retries_after_a_capacity_failure` force
  each failure in the first build (`ProjectionGateFault`). The executable
  still exits 42, and the second build keeps its early lowering.
  `ProjectionReport::early_lowerings` and `early_discarded` count both
  outcomes.

`LANIUS_PROJECTION_TRACE` turns the early lowering off, because it reads the
batch columns before lowering.

The host driver is `type_checker::program_retention::projection::RetainedProjection`.
`run(compiler, store, inputs, options)` returns `Objects { objects, report }`
or `Rejected { error, report }`. `ProjectionError` carries the code, detail,
rank, DeclId, body-relative row and token, file id and file-relative byte.

## Native compilation

`GpuCompiler::compile_path_manifest_to_x86_64_retained(manifest, build)`
compiles a path manifest with one or more libraries, scheduled into bounded frontend units. The `build` is a
`RetainedNativeBuild` that keeps the store, discovery, projection and
finalizer allocations across builds. Ordinary entry points are unchanged.
The build has seven steps.

1. **Units.** The ordinary resident source-pack executor runs one original
   job per unit with the store attached. A lexer-shape, parser-tree,
   synchronous type-check or output-capacity retry can rerecord that job;
   only its accepted attempt exports. It uses no unit cache and does not merge
   the libraries into one unit.
2. **Original objects.** `RetainedNativeBuild` creates a store in native
   projection mode. An export-only `ProgramRetention::new` store preserves
   the existing lowering selection. Native mode makes three changes to each
   unit's frontend job:
   - The template lowering selection is `ReplaySelection::RetainedOriginal`.
     `function_templates.slang` omits every function with a generic
     environment, including tag-only bodies.
   - Nongeneric bodies are lowered as before.
   - `record_exec` is off, so the frontend copies no instance. The counts
     are still published.
3. **Provisional calls.** Right behind the job's export and lowering,
   before the object is read, one kernel
   (`type_checker/retention/native/00_provisional`) rewrites the object's
   own GPU rows in place: one lane per undefined symbol of an x86 object
   (four-word rows and `call_hir_by_symbol`), or one lane per relocation
   row of a Wasm object (a symbol row carries its identity and call HIR).
   The lane count comes from the object's own total, copied on the GPU.
   The lane maps the symbol's call HIR to its retained use through
   `rt_x_flags[row].y`, `rt_x_scan[row].y` and
   `rt_x_counts[RT_X_BASE + RT_A_USES]`. Nothing runs unless the job's
   export committed (`RT_C_JOB_STATE`).
   - For a DIRECT or METHOD use whose callee is a generic template, the
     lane writes the identity `(NATIVE_RESERVED_LIBRARY, NATIVE_NS_USE,
     use)`. The host hashes identity words when it decodes the object, as
     for every symbol, so the object arrives with the rewritten symbols.
   - An x86 lane also writes the symbol's final identity words to
     `nc_identity`, which `ParkedSlot::record_identities` copies into the
     resident link's region 6 in the same submission.
   - It records the caller's ABI facts in `NativeCallTables`. `nc_use_abi`
     holds the accepted result, argument count, flags, generation and an
     argument-pool offset. `nc_use_args` holds `(term, passing mode)` pairs
     translated from each call's checked arguments. The pool is sized from
     the job's call-argument rows plus one row per object row, so it cannot
     overflow; the argument cursor (`nc_status` word 1) runs over the
     build.
   - The rewrite's status words come back in the object's own readback,
     with the export's counters (`compiler-program-retention.md`, "Native
     builds: no export readback"). There is no upload of symbol columns and
     no readback of rewritten columns.
4. **Catalog admission.** The existing GPU retained-catalog producer and
   solver check whole-program identities, implementation coverage and
   coherence before discovery. This includes unused impls from sibling
   libraries that no individual frontend job saw together. The driver reads
   compact receipts with `read_rows = false`; a missing or failed GPU
   publication rejects the build.
5. **Discovery** (`docs/compiler-retained-discovery.md`) publishes the
   instances, one root route per build-global use and the root readiness
   record with `READY_ROUTES`.
6. **Projection and certification.** `RetainedProjection::run_certified`
   first checks every instance edge as above. Then `10_certify` runs one
   lane per use whose `nc_use_abi` row belongs to this build. The use's root
   route must name one of two targets:
   - an instance of the use's callee at the use's ENV, with equal arity,
     substituted result and parameter types equal to the caller's facts;
   - the callee's own `DeclNative` identity, with an equal closed
     signature.

   Every compared type must have a complete layout. `10b_certify_finish`
   sets `READY_ABI` only when no use failed. A failure rejects the build
   with `ROOT_ABI` before any instance lowering. Its detail is the failure bits, and
   `row` is the lowest failing use.
7. **Finalize and link.** The GPU finalizer rewrites the provisional
   symbols to their routes. Then the x86 linker links the original and
   instance objects.

The route table may be sparse. `routes.slang` checks only the readiness
record. `classify.slang` checks the route row of each use that a
provisional symbol names: its generation, identity and rank. The finalizer
never reads a row that no symbol names.

The retained link publishes the GPU trait catalog proofs and binds them in
discovery. Bounded direct calls require a successful per-use proof, and projection
requires discovery's proof-admission flag before lowering a bounded template.
Implementation-method uses with a concrete declaration follow the same instance
route as free functions. Required trait members use a solver-selected
implementation. No step falls back to replay.

## Supported forms

Projection handles free functions and implementation methods whose bodies use: parameters, `let`, `return`,
`if`, `while`, `for`, `break`, `continue`, assignment, unary and binary operators,
integer, float, boolean and string literals, names of locals and parameters, member
reads of nominal structs, struct literals, plain array literals, indexing, direct calls
language intrinsic calls, enum construction, matches with nested patterns and `?` propagation.
Types include scalars, arrays, slices, references and closed nominal structs and enums
with compound generic fields and constant operands. Field terms are
instantiated under the nominal's own exact parameter identities. Arrays
keep exact element types and checked constant-atom length references.
Slices use the native three-word descriptor (data, length, signed stride).
References keep pointer storage while indexing follows the referent.

A checked argument mode 2 permits an array-to-slice borrow with equal
element types, in both projected calls and original-object ABI certification.
The original ABI record packs eight two-bit argument modes above its eight
flag bits. Every other argument requires exact type equality. A struct
literal's field value follows the same rule: a fixed array may fill a slice
field with an equal element type (`View { values: scratch }`), and every
other field requires exact type equality. Nongeneric
method calls from original bodies retain their frontend-checked native routes.

Every other form fails closed with its template location:

| Form | Error |
| --- | --- |
| named range objects | `FORM` or `TYPE` |
| a use whose recorded result is unresolved | `USE` (detail `0xfffe`) |

## Root obligations

| Obligation | State |
| --- | --- |
| Pattern rows are not constructor uses; enum instances are reached from signature, parameter, scrutinee and row terms | Schema realization reaches enum types from the stored type graph; pattern syntax creates no call use. |
| A nested pattern's matched type is the enclosing payload's schema-substituted type | Implemented by a lane per arm/payload, taking each nested payload type from its parent variant's realized schema. |
| Substitute u1.z/u1.w under the instance ENV and validate the adjustment | Implemented for calls naming an implementation method. The checked receiver plan is substituted and compared against the source after its dereference chain and against the target parameter. Receiver cases: `enter`/`read`/`peek` borrow mode 2, deref 1; by-value `(2, 0)`; twice borrowed `(2, 2)`; consuming self `(1, 0)`. |
| r3.y is a predicate ordinal only when r3.z is BOUND (4), a use index otherwise | Implemented in `05_check` and `07_rows`. |
| The accepted call result (u1.y, `67555902e`) | `05_check` requires u1.y to be resolved: a term, or a bare type parameter of the caller (the `T` of `keep(v)` in a body generic over T). Its substitution must equal the row type and the target's result. |

## Lowering workspace

A lowering pipeline binds one arena (`CompilerGraphWorkspace`) and one set of
HIR and semantic input buffers. Projection batches bind the projection's
columns; frontend units bind their type-check outputs. `GpuLoweringWorkspaceCache`
keeps one resident arena per target, owned by the frontend pipeline
(`ensure`). A projection batch gets a variant over that arena
(`ensure_projected`, `GpuLoweringPipeline::new_variant`): its own stages,
uniforms and bind groups, and no arena storage. The arena's type-check
upstream is dead while instances lower, so the variant may use the aliased
storage. The variant records with the batch's own bounds (rows and source
bytes), so the phase reset and the capacity-wide clears stay at the batch's
size, not the arena's.

The cache records the capacities projection batches asked for
(`projected_demand`). An object arena covers them, so the first warm build
grows the arena once and later builds rebuild nothing. A batch that does not
fit the current arena gets a standalone arena for that build only. A batch's
output-capacity retry raises the demand (`grow_projected_output`). Replacing,
growing or releasing the frontend arena drops the variant with it.

With a single pipeline slot, every warm settings build rebuilt the arena
twice: once for the instance batch and once for unit 0 after it, 52 to 62 ms
of host time each, while recording took about 2 ms and the object readback
about 5 ms. With the shared arena neither rebuilds: instance lowering went from
64 ms to 5.8 ms, unit 0's lowering recording from 54 to 65 ms to 1.4 to 1.8 ms,
and the warm build median from 394 ms to 261 ms. Tracked GPU buffers after a
build went from 6.12 GB to 5.43 GB, because the second arena is gone.

### Arena capacities

A new arena is built with one semantic row and two target rows per HIR row
(`LoweringCapacities::initial_for_frontend_unit`). The structural bound is
eight of each. Job bounds (`for_job`) keep the structural factors, so a job
in a grown arena is bounded by the arena.

A job with more semantic rows sets `LOWERING_STATUS_SEMANTIC_CAPACITY`. The
GPU counts every row (`semantic_lir_total`, read with the job totals), so the
host grows the arena to that count and replays the job, as it does for target
rows and artifact bytes (`LoweringOutputDemand`). The grown arena stays for
later jobs.

Settings, warm build, tracked GPU buffers after the build:

| | Semantic rows (capacity) | Target rows (capacity) | Arena slots | New lowering allocations | Tracked |
|---|---|---|---|---|---|
| Eight per HIR row | 171,710 (3,735,552) | 358,287 (3,735,552) | 2.12 GB | 839 MB | 9.476 GB |
| One and two per HIR row | 171,710 (466,944) | 358,287 (933,888) | 0.81 GB | 0 | 8.637 GB |

At 0.81 GB every slot fits in the 2.24 GB of dead type-check storage. The
instance batch emits 39,257 semantic and 71,004 target rows. The remaining
8.6 GB is the parser arena (4.0 GB), the type-check arena (2.2 GB), the
type-check interface buffers (0.47 GB) and smaller ones.

Lowering sizes its string pool from the job's source bytes, so a batch passes
at least its decoded string bytes (`string_words` × 4).

## Recording

A projection recording puts its dispatches in one compute pass and ends the
pass only before a copy or clear; wgpu orders the storage accesses between
dispatches. Repeated rounds of a kernel (layout rounds, pattern payload
rounds) bind the same buffers, so a recording creates one bind group per
kernel and extra-buffer set.

Both round counts grow on demand. A new projection records 16 layout rounds
and 4 pattern payload rounds, which the settings app needs (its pattern
payloads are all resolved by `04d_pattern_roots`). The host clears a status
word before the last round of each kernel (`PJ_S_LAYOUT_CHANGED`,
`PJ_S_PATTERN_CHANGED`); a round that still completes a layout or resolves a
payload sets it, and the check reruns from the plan's status with twice the
rounds of that kernel. The projection keeps the grown counts for its later
runs. The string scan's step configs are resident
buffers. In the settings app this took the check from 5.9 ms to 2.3 ms
(recording 1.45 to 0.55 ms, submission 1.6 to 0.85 ms).

## Gaps

- **Lowering retry.** `lower_projected_x86_batch` retries once at the
  lowering's output demand. No test forces that retry.

## Receipts

`cargo test --release --test compiler retained_native:: -- --test-threads=1`
under the GPU validation lock:

- `retained_native_build_executes_original_main_without_replay` writes a
  two-library path manifest and compiles it twice with one
  `RetainedNativeBuild`.
  - The original `main` in `app` calls `pack<bool>`, `pick<u8>` and
    `pick<i32>` in `lib`.
  - `pick` calls the generic `keep` and the nongeneric helper `bump`.
  - `pick` returns an `i32` and `pack` returns a two-field struct.
  - `DiscoveryCapacity::tiny()` and `batch_rows` 8 apply.
  - Each build shows 2 units, 5 instances, 5 instance objects and no replay
    lowering, and exits 13. Exactly two exports commit. Frontend recording
    counts equal the unit count plus the observed retries; they are not
    assumed to be exactly two when prior work changed allocation sizes.
  - Discovery takes 4 attempts in the first build and 1 in the second.
  - With every recorded caller argument rewritten to `bool`, the build
    fails with `root call ABI`. A clean build then exits 13.
- `retained_native_build_handles_one_library_and_no_instances` executes a
  single-library generic program, a program with no instances, then the
  generic program again in the same allocations. They exit 43, 9 and 43.
  It also compiles with an export-only store attached through the existing
  source-pack API, checking that native mode does not leak into that API.
- `retained_native_build_rejects_uncalled_conflicting_impls` puts two
  overlapping impls in sibling libraries with no calls to their methods.
  The GPU catalog rejects them with coherence status 5. With one impl
  changed to another type and a fresh manifest, the same build allocations
  produce a program that exits 17.
- The finalizer test `gpu_finalization_rejects_invalid_routes_and_retries_capacity`
  covers sparse tables. An unnamed missing row publishes, and a stale row
  that a symbol names fails with `RouteMissing`.

`cargo test --release --test compiler retained_projection:: -- --test-threads=1`
(5 tests) under the GPU validation lock:

- `retained_projection_executes_two_unit_program`: two units retained, the
  frontend released and its scratch poisoned. The test producer finds the
  root `start<u8>` and instances `swap<bool>`, `scale<i32>`, `keep<u32>` and
  `keep<i32>`. The program uses `PairA {i32, u32}` and `PairB {u32, i32}`, the
  private generic `keep` and private `Hidden<T>`, an f64 value, contextual
  literals and instance routes. It exits 7. The fallback counters
  (`compiler::fallback_counters`) show no frontend check and no replay
  lowering during projection and link.
- `retained_projection_batches_retries_reuse_and_staleness`: `batch_rows`
  16 gives 4 objects with cross-batch calls, and exits 7. A tiny substitution
  capacity takes 3 attempts with 2 growths. Identity mask 0 puts every
  identity on one chain. A new store build rejects the old records with
  `READINESS`. The same projection then lowers an unrelated program
  (exit 6).
- `retained_projection_rejects_instance_rule_violation`: the retained
  literal of `v + 37` in `bump<T>` is rewritten to 300. The run is rejected
  with `RULE` / `INTEGER_RANGE` at the byte of `37`, and no batch is lowered.
- `retained_projection_rejects_truncated_and_unready_inputs`: excess
  instance and route counts, missing readiness and stale empty inputs
  reject before substitution. A valid empty input returns no objects.
  With the old count clamp, the excess-instance case published the valid
  resident prefix and failed the test.
- `retained_projection_oracle_columns` captures the frontend's lowering
  columns for a matching program; it fixed the column defaults.

## Costs

The two-unit slice: 5 instances, 90 rows, 117 requests, 1 batch.

| Figure | Value |
| --- | --- |
| projection dispatches | 44 (plan 2, requests 1, layout 33, rows and check 5, batch 3) |
| substitution dispatches | 38 |
| host readbacks | 3, 560 bytes |
| allocations | 8, 1.8 MB (first run) |
| plan / substitution / check | 0.6 ms / 1.0 ms / 2.7 ms |
| lowering of the batch | 45 ms (the first lowering job of the process) |

Work is O(rows + requests + terms × layout rounds). The span is the
substitution's term height plus the layout rounds and two tree walks of at
most 256 steps per row. Memory is O(ranks + rows + TermIds) for the check
and O(largest batch) for the lowering columns.

### Array and borrowed-value execution

`retained_native_arrays_keep_element_layout_and_value_semantics` executes
cross-unit arrays of integers, floats, booleans, records and nested arrays
through multiple lowering batches. It checks copy semantics and exits 42.
`retained_native_borrowed_values_keep_aliases_stride_and_bounds` checks
one/two-level references, mutations, whole-array replacement, slice stride,
and array-to-slice arguments from original and projected callers. Its valid
program exits 42; negative and upper-bound accesses exit 101. All builds
assert zero source replay. These tests use real discovery, ABI certification,
projection, native finalization and linking.

### Constant parameters and repeated arrays

Constant parameter values use the same per-row substitution request as the
row's type. A symbolic constant requests its exact parameter leaf; its
closed `CC_VALUE` supplies both the declared scalar and the value words.
Projection checks the scalar against the retained row type before publishing
a concrete value. Type-annotation counts remain in the closed array type,
so annotation rows never retain executable symbolic-constant flags. This
adds no substitution requests to nonconstant bodies.

`retained_native_constant_values_and_array_extents_execute` exercises empty,
one-element and three-element arrays, nested generic forwarding, loops
using a `usize` constant parameter, bool and u8 constant values, and repeated
and zero-filled arrays. It executes across units and batches with zero replay.
Repeat counts follow the current parser rule: the count in `[value; count]`
is an integer literal. Constant parameters remain valid in array types.

The semantic artifact producer now applies name resolution only to name/path
expressions. A return statement's form word also equals 2; treating it as
a name gave `return N` a spurious binding on the return statement itself.
The value expression retains its exact constant parameter binding.

### String storage

String metadata keeps the decoded length and the retained byte-arena range.
Projection scans word lengths in instance/row order, then copies one decoded
word per GPU lane into the current lowering batch. Each string includes its
NUL and word padding. A lane finds its source by binary search over row offsets;
no lane walks the bytes of a long string. Native string values retain their
two-word pointer/length ABI. Original nongeneric extern calls keep their
frontend-checked targets and never enter monomorphization.

`retained_native_strings_keep_decoded_bytes_across_batches_and_rebuilds`
checks exact stdout for empty, escaped Unicode and long strings, multiple
strings per template, one shared batch and several batches, then shrinking
and growing the pools in the same build allocations. All three executions
exit 42 with zero source replay. The full `retained_` filter passes 21 tests.

### Intrinsics inside instances

Discovery keeps intrinsic uses as non-symbol routes. Projection validates
the retained tag, arity, accepted result and concrete operands, then writes
an intrinsic checked-call artifact for ordinary lowering. Print, length and
bit-cast argument rules share `intrinsic_operand_rules.slang` with the
frontend. View constructors require a complete element layout, a pointer
(or the allowed null spelling), and an integer count.

`retained_native_intrinsics_execute_inside_generic_bodies` executes slice
and string queries, typed views over scalar and record elements, storage
views, float bit casts, printing and an assertion trap in generic bodies.
It checks exact output and zero replay. The `retained_ intrinsic` test
filter passes 28 tests, including the existing intrinsic checks. The driver
printed `NVVM compilation failed: 3` after the passing test summary; no test
or dispatch failure was reported.

### For loops

Projection substitutes the checked loop-binding type and validates it against
the array/slice element or numeric range bounds. It restores the iterable
kind and array/slice length for lowering. Direct range wrappers are structural
syntax; bound expressions remain independent value roots, matching the
frontend expression forest and preserving their evaluation before loop entry.

`retained_native_for_loops_keep_binding_types_and_control_flow` executes
integer/float arrays, record slices, empty slices, nested ranges, break and
continue, omitted endpoints, and the inclusive i32 maximum. It runs with
small and combined lowering batches and asserts zero replay.
The `retained_ numeric_range x86_executes_for` filter passes 35 tests. The
driver printed the same post-summary NVVM message seen in the intrinsic run.

### Bounded direct calls

`retained_native_bounded_direct_calls_consume_gpu_proofs` compiles cross-unit
`outer → middle → keep` calls for a scalar, a private record, and a generic
wrapper whose impl has its own prerequisite. It checks nine instances, small
and combined lowering batches, a valid GPU proof publication, exit 42 and zero
replay. Bound-member dispatch remains a separate routing obligation.
The complete `retained_` filter passes 25 tests after proof integration.

### Compound nominal schemas

After body substitution, schema realization scans each newly appended term
frontier. A parallel prefix scan places one request per nominal schema record;
each request substitutes the declared field or payload under the closed nominal
application itself. A lane per result writes a closed field map. Newly created
nominal field types enter the next frontier. The host never constructs an
environment or a field type.

Struct layout, member access and initializer checks share that field map.
A failed substitution leaves the field unavailable, so a used type cannot get
a complete layout. The field map resets each run; growth preserves the already
realized prefix. Schema substitution has a separate engine allocation so the
body substitution publication stays current throughout projection.

### Schema rounds

The rounds run without a readback between them (`projection/schema.rs`).
The host records a chain of rounds after the projection substitution and
before the check; the check's readback returns `ps_status`. Each round is:

| Kernel | Lanes | Work |
| --- | --- | --- |
| `04_round` mode 0 | one | gate on the previous round's run, commit that round's fields, arm the terms the store gained since the last round |
| `00_plan` | round terms + 1, indirect | schema records per term |
| `01_scan` modes 0, 1, 2 | indirect, one workgroup, indirect | inclusive block scan for any round width |
| `05_size` | one | request count, request-lane dispatch, capacity check |
| `02_requests` | round requests, indirect | one request per schema record |
| substitution | engine | a chained run |
| `03_consume` | round requests, indirect | the field map |

A chain ends with `04_round` mode 1, which gates the last run and converges
when the store has no term past the last round. The round state (next first
term, field base, committed rounds) lives in `ps_status`; the armed round in
`ps_round`, which the wide passes read; their workgroups come from
`ps_indirect`. Every table is sized from the store's term capacity, which a
chained run never grows, and from the request and field capacities.

`ps_status` word 3 says how the chain ended:

| Stop | Meaning | Host |
| --- | --- | --- |
| 0 | every recorded round ran and the store gained terms | records twice the rounds (kept for later projections, at most 64) |
| 1 | converged: no new term, or new terms without schema records | done |
| 2 | a round's run did not publish (overflow, or not final after its first batch) | resumes the armed round: `05_size` mode 1, `02_requests`, the full substitution path, `03_consume`, `04_round` mode 1 |
| 3 | a round's requests or fields exceed their buffers | grows them to the demand (fields preserved), then resumes as for 2 |
| 4 | the store is not ready or a scan overflowed | fails the projection |

A stopped round dispatches no workgroups after the stop, and its fields are
not committed, so a retry never publishes a partial round. When the
projection substitution itself ran again on the full path, rounds that had
converged run again for the terms that path interned. The gate takes one
run's publication word. The trait solve's verdict needs no input here: it
is part of the source publication's status, which the roots readback
returns before the projection is recorded (see "Source publication status"
in the discovery guide).

`retained_native_schema_rounds_retry_with_grown_capacity` starts the
projection with a tiny substitution capacity and one schema row: the
chained projection run reruns on the full path, the first round stops for
capacity and a chained run overflows, and both builds exit 42.

`retained_native_compound_generic_fields_have_exact_layouts` executes nested
records with arrays of scalar and record elements, slice fields, and a
constant-generic array field, with small and combined batches. Both builds
exit 42 with zero replay. Enum payload terms use the same schema stage; enum layout is one discriminant word plus the widest variant payload.
The complete `retained_` filter passes 27 tests after schema realization.

## Enum construction and patterns

Constructors validate the accepted result's exact enum declaration, variant
ordinal, payload arity and every realized payload type before emitting the
existing checked constructor artifact. Unit variants carry an ordinal marker
without depending on a frontend variant table.

Match tables preserve canonical arm and payload order within each batch. Root
patterns take the scrutinee's referent type. Payload lanes take their types from
the parent variant's realized schema; the current implementation records 64
dependent dispatches when payloads exist. Pattern checks verify declaration,
ordinal, child count and any retained type before publishing lowering facts.
Borrowed enum matching reads the pattern's concrete type identity, avoiding a
collision between batch token indices and retained type indices. The lowering's
local-variable passes recognize the imported variant marker, so nested variants
are comparisons rather than declarations of nonexistent locals.

The two native enum tests execute integer, float, struct and array payloads,
unit variants, nested variants and literal subpatterns, scalar matches and
borrowed enum matches. They use both one-instance and combined lowering batches
and assert zero replay. A projection fault test changes a variant ordinal to
one with a different arity, then changes a payload's type; each must reject
before lowering, and a restored store must succeed with the same allocations.

Validation: 42 focused tests passed (`retained_`, compiler defect fixtures,
and the slice enum payload case); receipt:
`target/retained-native-integration-evidence/match-regression.log`.
The test process stayed alive during GPU teardown for more than five minutes
after the passing summary and was terminated (exit 143); the 42 test cases
had completed without failures.

### Success and error propagation

Projection publishes the closed nominal argument graph in the lowering's
argument-row arena, including typed constant arguments and interleaved domains.
Each term owns a disjoint argument range. The `?` check requires the operand
and function result to name the same enum and verifies the exact realized
success and error payload types. Lowering then uses its existing Option/Result
path, with complete native widths for both payloads.

`retained_native_try_preserves_success_and_error_payloads` compiles three
libraries with generic Result and Option helpers. It checks wide struct
success/error payloads, a string error, a changed success type and None,
with small and combined batches. Both executions exit 42 with zero replay.
The complete `retained_` filter passes 31 tests after argument-graph and `?` integration.

### Implementation methods

Discovery follows the accepted implementation method's exact declaration and
substitutes its ENV, including inherited impl parameters and method parameters.
Projection substitutes both receiver terms, verifies each reference dereference
and the value/borrow adjustment, and checks the resulting receiver against the
target's first parameter. Original-object ABI certification includes that first
parameter too. The checked call artifact retains the explicit argument count;
ordinary lowering adds the receiver once.

`retained_native_methods_preserve_receivers_and_inherited_binders` executes
borrowed reads, mutation through `&self`, consuming `self`, method-to-method
calls, and inherited and shadowing type parameters across units and batches.
Both builds exit 42 with zero replay.

Inherent calls retain the template's accepted method. A forced-replay probe
with both `impl<T> Wrap<T>` and `impl Wrap<[i32;2]>` defining `marker` accepts
the generic template's choice, as the existing GPU-copy path does. This differs
from a direct concrete receiver, for which the frontend reports LNC0027.
The replay result does not justify introducing a new closed-instance ambiguity
rejection. The probe and its forced-replay receipt are in
`target/retained-native-integration-evidence/ambiguity-forced-replay.log`.

Float rows retain both parser decode statuses alongside both rounded values.
Projection selects the status at the realized f32/f64 width with the same
helper as the frontend. `retained_projection_selects_float_status_at_the_instance_width`
checks that `1e39` succeeds at f64 despite f32 overflow, and that a failed
selected-width status rejects before any object is lowered.

### Required trait members

Discovery solves each instance's closed predicates, then converts the selected
implementation's proof bindings into retained terms and a complete method ENV
on the GPU. It publishes the selected declaration and ENV beside the call route.
Projection verifies this target's substituted signature, receiver plan and ABI;
the solver remains the implementation selector.

`retained_native_bound_members_use_concrete_solver_routes` crosses two units
and exercises scalar, nominal and generic impls, a nested bound call inside an
impl, trait type arguments, a wide struct result, an i64 binding, and consuming
`self`. Static calls such as `C::same(a,b)` retain the method selector's
accepted subject even when the trait never spells `Self` and its call ENV
omits that binding. The execution fixture uses different subject and argument
types, so recovering the subject from an argument cannot pass it. Small and
combined lowering batches both execute with zero replay.
Generic executable trait methods with their own parameters remain rejected by
the existing frontend (LNC0021).

### Native C and imported patterns

`RetainedNativeBuild::native_link` selects the existing native C linker. Original
units keep their source-checked foreign declaration inventory. Discovery routes
calls from generic bodies to those declarations; export retains their accepted
native ABI word and projection emits a C symbol call. Finalized original and
instance objects enter the existing native linker unchanged. No generic body is
recompiled to provide the link metadata.

`retained_native_generic_bodies_call_private_c_declarations` executes `abs`,
`labs` and `fabs` from two instances of a generic body in another unit. The
private declarations keep their defining unit identities, and both batch sizes
exit 42 without replay.

Imported variant patterns retain their accepted ordinal. Their instantiated
type comes from the scrutinee or enclosing variant payload, checked against
the retained enum schema. The Result/Option execution test also maps an
imported `Result<T,i32>` to `Result<T,Failure>`, covering both success and error
payloads across three units.

After native C and imported-pattern integration, the combined `retained_`
and `program_retention` filters pass 43 tests. The bound-member fixture also
passes after adding static calls and an impl proof whose child uses a caller
assumption. At that checkpoint settings passed discovery across its two original
frontend jobs, while projection still rejected an unsupported layout. The
subsequent settings and default-path receipts below supersede that limitation.

Zero-word struct layouts are complete, including structs containing only
zero-length arrays. The compound-field execution test covers empty records,
zero-length generic fields, generic returns of empty values, and offsets of
ordinary fields after empty ones. Folded named constants retain their exact
value and declaration; projection checks both the value and type against the
constant schema before native materialization.

Host calls retain their accepted service ID for both local and imported
declarations. Projection checks the closed extern signature and emits the
existing host call artifact, so native lowering selects the runtime service.
`retained_native_host_calls_keep_local_and_imported_service_ids` allocates,
stores and reads i64/f64 values, deallocates, and writes text from generic
bodies on both sides of a unit boundary. Both batch sizes exit 42 with the
expected output and zero replay.

The settings snapshot (`212c54dce`) compiles as two original units with 1,338
instances, 34,696 projected rows and one instance object. Both export jobs
are READY, the catalog and closed discovery proofs pass, and no source replay
runs. With the native libraries from the existing settings receipt, the
generated executable runs `--frames 3 --scale 1` and exits 0. This run proves
execution; its cold 1.58 s compile is not a warm rebuild measurement.

### File-backed native builds

`compile_path_manifest_to_x86_64_retained_to_file` writes through the existing
atomic output boundary. The manifest is scheduled into the ordinary bounded
frontend units. Large manifests, native C builds, and direct file output spill
each original object before compiling the next unit. Projection stores each
lowered batch before starting the next batch, so section vectors do not
accumulate across instances. The GPU finalizer rewrites the in-memory metadata
of spilled originals; their section files remain immutable. The raw GPU linker
reads those files in ranges with the finalized metadata.

`retained_native_large_pack_spills_instances_and_writes_atomically_without_replay`
uses the existing two-file, 6 MiB native C fixture. It produces two original
objects and two instance objects, all spilled, executes successfully, and
records zero replay. A second build exceeding the output limit leaves the
previous executable byte-for-byte unchanged. The original-main test also
executes file-backed GPU linking without native C, then verifies that an ABI
rejection preserves the executable. These two tests and the focused private-C
call test passed together (3 tests, 4.73 s).

### Function values across lowering batches

A retained `FN_REF` use resolves to the nongeneric free function's native
symbol. Projection checks its closed signature against the existing C-entry
contract (at most six integer/pointer register parameters and a scalar/unit
result). It emits checked callable kind 5 on the name/path row, with the native
identity and a six-bit parameter normalization mask. Original frontend jobs
clear that discriminator on every name/path row, so reused storage cannot
supply a stale projected function reference.

Semantic lowering preserves the identity as a symbol call and the mask in its
per-row layout word. Native lowering emits `FUNCTION_ADDRESS_SYMBOL`: the
existing inline C-entry stub with a symbol relocation for its inner call. The
referenced function stays in its original object. No function body is replayed
or copied into the instance batch merely to take its address.

`retained_native_function_values_call_originals_across_batches` exercises two
instances from another unit, private callback targets, 32-bit normalization
with nonzero upper input bits, pointer parameters, and both raw and native-C
linking. Separate and combined batches return 42 and write `RNRN`; replay
counters remain unchanged. The retained tests and existing qsort, bsearch,
pthread and generic-body callback tests passed together (42 tests, 43.49 s).

### Source replay deletion

Default native and Wasm builds now have one source-compilation path followed by
GPU monomorphization. The source-copy generator, host replay sessions and cache,
replay authority and type/layout input packets, source body spans and blanking,
and host object-symbol mutation helpers have been deleted. Original-object
lowering selects nongeneric definitions; instance lowering emits every projected
function. Both run the normal lowering validation passes.

Every retained stage uses the compiler's device and queue, including schema
substitution, discovery requests and provisional-call symbol production. The
provisional-call pipeline belongs to its store rather than a process-global
singleton. Reused allocations are reset by the build generation.

Compiler devices share one wgpu instance but have separate devices and queues.
wgpu 29 compares native handles by instance-local IDs; using separate instances
allowed a device to find another device's pipeline or bind-group layout in the
process caches. The custom-device regression compiles and executes native and
Wasm programs, then compiles on the global device in the same process.

The local GPU closure and operand checks still run before template export.
They preserve source diagnostics for constant fits and instance operands.
Original jobs select no in-place body and append no execution copies when
program monomorphization is attached. All emitted generic bodies come from
retained projection. Skipping the local checks exposed diagnostic parity gaps
in discovery and projection, so that optimization is not part of replay removal.
