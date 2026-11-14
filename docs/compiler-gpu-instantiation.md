# GPU generic instantiation

This is the implementation contract for removing source replay from full
compilation. Replay elimination is partial. A program compiles as one unit
(see [One program, one unit](#one-program-one-unit)), and the original compile
lowers closed local instances itself (see [Execution rows](#execution-rows)).
The compiler still constructs source copies of every other generic body and
runs the frontend again for them.

The performance target is about 160 ms for a warm resident-daemon rebuild of
the settings application, with every unit compiled on every request. Reusing
GPU allocations and pipelines is allowed; reusing compiled units, generic
instances, or checked source between requests does not count. Instantiation,
substitution, layout, call selection, and lowering must run in GPU shaders.

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
| `0x105` call | Every call is routed: a call of a local generic body names its callee's table entry, and every other call keeps the template's callee and needs no type argument from the environment. Method, bound-member, dependency-generic and unresolved calls fail. |
| `0x106` fact | No index, iteration or array row and no function result changes to an array type. A member's receiver is a row of the body, and its layout under a changed receiver derives in `08a_exec_members`. A raw view's realized element has a native width, and a struct literal's realized struct has no application-typed field (`08a_exec_members`). |
| `0x107` block | Each side-table block of the body is contiguous. |
| `0x108` capacity | The rows, tokens and side-table rows fit. An entry that does not fit, and every later entry, replays. |

On the host, `ExecRoutes` in
[`body_specialization.rs`](../crates/laniusc-compiler/src/compiler/gpu_compiler/body_specialization.rs)
routes a selected entry to its copy only when the entry's closure origin
passes the same admission as a replay request. The origin must target this
unit, `checked_replay_environment` must close its environment, and the
copy's symbol must be defined in the unit's object. The copy is then
registered as that environment's specialization, with the origin's layout
witnesses, so no replay is requested for it. A call row inside a copy routes
through its callee entry's admitted origin. A routed call whose callee entry has
no admitted origin is a compile error, not a fallback. Selected entries that do
not route still replay. Their copies stay in the object as unreferenced
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

Decision: a program compiles as one unit. `whole_program_manifest` in
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
  instances still replay. Deleting replay requires an explicit compile error
  for this case.
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
instances), 279 call rejections and 59 fact rejections. Most call rejections
are method and bound-member calls inside a copy, such as `self.next()`.

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

Today, [`project.slang`](../shaders/codegen/lir/semantic/project.slang) assigns
one function identity per HIR row, and
[`function_scatter.slang`](../shaders/codegen/lir/semantic/function_scatter.slang)
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
   lowered as instances. Method calls, bound-member selection and dependency
   generics called from a copy still replay.
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
   `ValidatedReplayRequest`. Once the complete settings workload uses this
   path, remove its source-copy compiles and measure full warm rebuilds with
   all compiled-unit and instance reuse disabled.

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
