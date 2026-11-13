# GPU generic instantiation

This is the implementation contract for removing source replay from full
compilation. Replay elimination has **not** shipped. The current compiler still
constructs source copies of generic functions and runs the frontend again.

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
| Multiple instances | An experimental table assigns virtual rows to local function instances, substitutes expression types, and resolves some callees. Native lowering does not consume it. | [`instance_table.slang`](../shaders/type_checker/closure/instance_table.slang), [`table_rows.slang`](../shaders/type_checker/closure/table_rows.slang), [`07_table_calls.slang`](../shaders/type_checker/closure/07_table_calls.slang) |
| Replay | The host groups admitted environments, creates renamed source copies, and invokes another full compile. | [`body_specialization.rs`](../crates/laniusc-compiler/src/compiler/gpu_compiler/body_specialization.rs), [`instance_copies.rs`](../crates/laniusc-compiler/src/compiler/gpu_compiler/instance_copies.rs), [`typecheck.rs`](../crates/laniusc-compiler/src/compiler/gpu_compiler/typecheck.rs) |
| Publication | A private replay request checks definition provenance, selected implementation bindings, complete native layouts, call ownership, and fresh call admission before releasing its object. | `ValidatedReplayRequest` in [`native_session.rs`](../crates/laniusc-compiler/src/compiler/gpu_compiler/trait_solver/native_session.rs) |

`LANIUS_CHECK=instance-table` builds the experimental table and compares its
expression types and call routes with actual source-copy replays. It reports
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
2. **Lower local closed instances.** Introduce execution rows and complete the
   per-instance semantic projection. Start with local bodies whose calls and
   layouts close in the current unit. Emit two distinct environments of the
   same function, with separate symbols and storage, in the original unit
   compile. Compare execution and admitted facts against the existing replay
   path; do not bypass trait or layout admission.
3. **Close local instance graphs.** Route calls between instances, including
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
