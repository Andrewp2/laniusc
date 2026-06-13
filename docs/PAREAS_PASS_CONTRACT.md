# Pareas Pass Contract

This note records the production-readiness contract used by the shader loop
audit. It is derived from the checked-in paper translations and the local
Pareas source comparison in `~/code/pareas`.

## Paper Shape

`docs/CompilationOnTheGPU.md` describes each compiler pass as individually
parallelized over array data, using map, reduction, scan, prefix sum, and
scatter primitives instead of recursive pointer-heavy compiler structures.
`docs/ParallelLexingParsingSemanticAnalysis.md` extends the same shape across
front-end passes: lexical facts, parser facts, and semantic facts are produced
as parallel relations that are compacted, prefix-summed, and scattered before a
consumer pass trusts them.
`docs/ParallelLLParsing.md` specifically treats parsing as a parallel summary
and combination problem: block-local parser summaries are reduced and applied
instead of replaying one serial parser over the full source stream.
`docs/ParallelCodeGeneration.md` makes that concrete for code generation:

- AST/HIR-like nodes live in arrays with node type, parent, depth, child index,
  data type, and node data fields.
- Instruction counts are computed per node from lookup tables and small
  correction records.
- Instruction locations are computed by exclusive prefix sum.
- Location corrections are scattered back into the instruction-location array.
- Instruction generation sorts node indices by depth, maps one tree layer at a
  time, and scatters instruction records plus child-to-parent result records.
- Register/spill layout uses virtual registers first, then per-function
  segmented scans and scatters for stack slots, prologue/epilogue records, and
  final instruction compaction.

## Pareas Source Check

The local Pareas implementation matches those paper sections:

- `src/compiler/codegen/instr_count.fut` computes node instruction counts with
  `map`, `scan`, and `scatter`.
- `src/compiler/codegen/instr.fut` sorts nodes by depth with `radix_sort`, maps
  each layer, and scatters generated instructions and parent result slots.
- `src/compiler/codegen/register.fut` uses `segmented_scan` and `scatter` for
  spill offsets and final instruction insertion.
- `src/compiler/passes/tokenize.fut` interns names with radix sort, scan, and
  scatter rather than per-use source rescans.

## Lanius Gate

Large fixed-bound shader loops are not automatically paper-aligned just because
the cap is literal. They are review blockers until the pass is expressed as
record publication plus scan/sort/join/scatter/reduction work, or until a narrow
bounded helper is justified as local constant work.

Use the shader loop audit as the no-run guard:

```sh
tools/shader_loop_audit.sh --summary-only
tools/shader_loop_audit.sh --summary-only --high-risk-only
tools/shader_loop_audit.sh --summary-only --fail-on-paper-pass-blocker
tools/shader_loop_audit.sh --summary-only --fail-on-large-fixed-bound
tools/shader_loop_audit.sh --summary-only --fail-on-source-sized-symbolic-cap
tools/shader_loop_audit.sh --root shaders/codegen --summary-only \
  --fail-on-x86-codegen-review-required \
  --fail-on-x86-codegen-large-fixed-bound
tools/shader_loop_audit.sh --root shaders --summary-only \
  --fail-on-parser-review-required \
  --fail-on-type-checker-review-required \
  --fail-on-parser-source-sized-symbolic-cap \
  --fail-on-type-checker-source-sized-symbolic-cap
```

For lightweight triage, use the `summary` rows with group `reason` as the
stable unit of work. Classes such as `source-or-dispatch-sized-loop`,
`subtree-or-parent-sized-loop`, and `large-fixed-cap-*` should be translated
into record publication plus scan/sort/join/scatter/reduction passes, not
accepted as source-sized shader loops.
Use `summary` rows with group `component` only to route the work to the owning
shader area. They do not justify a loop; the pass is aligned only when the
component's high-risk reason rows are replaced by the paper shape above or
explicitly documented as narrow local constant work.
Use `summary` rows with group `component-paper-pass` for assignment and status
rollups: the row name is `component:paper-pass`, so it shows both the shader
area and the rewrite family without requiring detail rows.
Use `component-paper-pass-blocker` for the assignment queue: it removes the
bounded-local review categories and leaves only subsystem/rewrite pairs that
must become non-local record, scan, sort, join, scatter, or convergence passes
before a pass-contract claim can be made.
Use `summary` rows with group `pass-shape` for the fastest no-run distinction
between acceptable pass-primitive loops and loop debt:

- `pareas-primitive-bounded-loop` means the loop is fixed-bound, not capped by a
  source-sized symbolic name, and appears in a prefix/scan/sort/reduce/scatter,
  radix, compact, histogram, bucket, partition, or join context. This is
  pass-structure evidence only; it can support a claim that the shader is shaped
  like a Pareas primitive, but it does not prove correctness, runtime scaling,
  throughput, VRAM use, or Pareas equivalence.
- `source-scale-or-nonlocal-loop` means the loop still maps to a non-local
  paper-pass blocker such as source/record/subtree traversal, large-cap
  splitting, guard-record publication, or convergence/worklist design.
- `bounded-source-sized-symbolic-cap` and
  `bounded-source-sized-legacy-fallback` mean the loop is syntactically bounded
  but the symbolic cap name still looks source-, tree-, record-, dispatch-, or
  program-sized. The legacy variant also matched `legacy`, `fallback`, or
  compatibility naming. These rows are bounded fallback debt, not acceptable
  Pareas-style primitive evidence.
- `bounded-legacy-fallback` means legacy/fallback/compatibility naming remains
  even though the cap did not match the source-sized symbolic-cap queue.
- `bounded-local-helper-review` means the loop is fixed and local-looking but
  not obviously one of the pass primitives above; it still needs a
  behavior-facing local invariant or a pass rewrite before it can support a
  pass-contract claim.
- `manual-review` is reserved for loops that do not fit the fixed-bound helper
  classes after the higher-priority blocker rules run.

Use `summary` rows with group `component-pass-shape` to assign those evidence
classes to a shader subsystem without opening detail rows. A readiness artifact
that includes timing or scaling data but omits these rows cannot show whether
its shader loops were primitive-shaped, source-scale, or bounded fallbacks.
Use `summary` rows with group `audit-evidence-role` as the claim-boundary rollup
for no-run loop evidence:

- `proof` means only that the audit recognized a bounded loop shaped like a
  pass primitive. It is proof of the audit predicate, not proof of shader
  correctness, runtime scaling, throughput, VRAM use, or Pareas equivalence.
- `blocker` means the loop remains source-scale, non-local, manual-review, or
  source-sized symbolic/fallback debt. These rows block pass-contract and
  scaling claims until the loop is rewritten or justified by a stronger
  behavior-facing contract.
- `local-review` means the loop looks bounded and local but still needs a local
  invariant or rewrite before it can support a pass-contract claim.

Use `audit-evidence` for the detailed reason within those roles, and
`component-audit-evidence-role`/`component-audit-evidence` to route the same
proof, blocker, and local-review split to shader subsystems. A performance or
scaling artifact that reports a clean blocker pointer but drops these rows is
missing the evidence needed to tell proof from blocker and local-review debt.
Use `summary` rows with group `claim-blocker` as the compact performance,
scaling, and Pareas-parity claim boundary. The
`performance-scaling-or-pareas-parity-audit-debt` row is the sum of
`audit-evidence-role=blocker` and `audit-evidence-role=local-review`; it must be
zero before loop-audit evidence can stop blocking such claims. The
`performance-scaling-or-pareas-parity-audit-blocker` and
`performance-scaling-or-pareas-parity-local-review` rows keep that total
diagnosable. A zero claim-blocker total is still only loop-shape evidence, not
correctness, throughput, VRAM, or Pareas-equivalence proof.
Use `summary` rows with group `paper-pass` as the review category:

- `record-map-prefix-scan-scatter` and
  `source-record-partition-prefix-scan` mean the shader should publish compact
  records, prefix-sum output locations, and scatter/gather results instead of
  walking source-sized or record-sized ranges in each invocation.
- `depth-sort-parent-join-scatter` means tree relationships should be expressed
  as parent/depth/key relations, sorted or range-indexed, then joined/scattered
  rather than rediscovered through subtree or ancestor loops.
- `publish-guard-records-scan-scatter` and
  `split-large-cap-into-record-scan` mean a fixed cap is not enough evidence;
  the data-dependent exits or large literal windows need an explicit relation
  and prefix-summed output shape.
- `bounded-local-scan-reduce-review` and `bounded-local-helper-review` are the
  only categories that can remain loops, and only when the bound is local
  constant work rather than source/program size.
- `fixed-point-or-worklist-review` needs a separate convergence/worklist
  design before it can be called paper-aligned.

`--fail-on-paper-pass-blocker` is the broad no-run readiness gate. It treats
every `paper-pass` category except `bounded-local-helper-review` and
`bounded-local-scan-reduce-review` as a blocker, because those categories imply
source-sized, record-sized, ancestor/subtree, large-cap, or convergence work
that must be converted to the paper/Pareas pass shape. The local-review
categories still need justification, but they are the only loop classes that can
remain as bounded helper work.
The measurement scaffold in `tools/compiler_acceptance.sh` must propagate the
same `paper-pass-blocker` count into pass-contract blockers; `review-required`
alone undercounts paper-alignment debt because fixed-cap data-dependent and
large-cap categories can still require non-local scan/scatter rewrites.
It also publishes `top-component-paper-pass-blocker` from the
`component-paper-pass` summary rows so no-run reports identify the largest
owning subsystem/rewrite-family pair without treating that count as a
performance number.
For broader planning it also publishes `paper-pass-blocker-by-component` and
`paper-pass-blocker-by-rewrite`, excluding bounded-local review rows, so the
same no-run measurement plan shows both where the blocker lives and which
Pareas-style primitive family should replace it.
It also publishes `paper-pass-blocker-by-component-route` from blocker-only
`component-rewrite-route-blocker` rows. That field is the concrete assignment
queue: each item names the shader subsystem, the prefix/sort/join/scatter route
that should replace the loop class, and the count.
It also publishes `paper-pass-local-review-by-component` and
`paper-pass-local-review-by-component-route` from local-review-only rows. Those
fields are the bounded-helper justification queue, not rewrite blockers or
performance numbers, and they must stay visible while `paper-pass-local-review`
is nonzero.
For source-sized symbolic caps, the measurement scaffold must also preserve
`source-sized-symbolic-cap-path-route`. Each entry names the component, symbolic
cap, shader path, Pareas-style primitive route, and count, so a no-run artifact
can assign the exact fallback loop without reopening the raw audit.
The raw audit also publishes `rewrite-route` and `reason-rewrite-route` summary
rows. Those join the loop reason to the concrete primitive sequence. For
example, `source-or-dispatch-sized-loop` must route to
`partition-source-records-prefix-sum-scatter`, not to another per-invocation
source walk.
The raw audit also publishes `evidence-policy` summary rows with stable
one-count markers: `behavior-facing-pass-evidence`,
`rewrite-routes-not-source-grep-evidence`,
`rust-product-source-inspection-not-pass-evidence`,
`audit-proof-is-pass-shape-only`,
`audit-blockers-and-local-review-are-not-performance-evidence`,
`audit-debt-blocks-performance-and-pareas-parity-claims`,
`zero-paper-pass-blocker-not-pass-contract-proof`,
`no-run-not-performance-evidence`, and
`no-run-not-pareas-claim-evidence`. The measurement scaffold treats those rows
as part of the pass-contract input, so a timing or VRAM plan cannot drop the
rule that rewrite routes are no-run behavior/pass evidence, Rust product-source
inspection is not pass evidence, audit proof is only pass-shape proof,
blocker/local-review rows are not performance evidence, audit debt blocks
performance/scaling and Pareas-parity claims, a zero paper-pass blocker queue
is not pass-contract proof while blocker or local-review audit-evidence rows
remain, and none of those rows are Pareas comparison claims.
Source-sized local aliases such as `n_hir_nodes`, `num_tokens`,
`total_hir_nodes`, `hir_node_count`, `module_count`, `n_records`, `n_decls`,
`field_count`, `method_count`, `edge_count`, `relation_count`, `field_len`,
`method_size`, `import_len`, `library_size`, `field_end`, `relation_limit`,
`segment_end`, `edge_capacity`, and similar `n_*`, `num_*`, `total_*`, or
source-record suffix count/length/size/limit/end/capacity variables are treated
the same as direct `gParams.*`, `source_len`, or token-count bounds; renaming a
source-sized bound must not make the loop look like bounded helper work.
Local helper budgets may use neutral budget names only when the API enforces the
local shape before the loop runs, such as one fixed stack frame set or one
already-published row block. Those loops still stay in the bounded local-review
inventory until a behavior-facing invariant or a pass rewrite justifies them;
the name only keeps them out of the source-sized symbolic-cap queue.
Uppercase symbolic caps are not exempt from that rule. A loop bounded by a
name such as `MAX_HIR_NODES`, `LEGACY_MODULE_HIR_SCAN_LIMIT`,
`MAX_BODY_STATEMENTS`, or `MAX_METHOD_CONTRACTS_PER_OWNER` is still review debt:
the raw audit keeps it in the fixed-bound/local-review inventory for backward
compatibility, but adds `source-sized-symbolic-cap` review rows and
`source-sized-symbolic-cap-candidate` detail flags. Use
`--fail-on-source-sized-symbolic-cap` when a lane wants to fail closed on new
symbolic caps until the helper bound is justified as truly local constant work
or replaced by a record/count/prefix-sum/scatter pass. The summary also
publishes `component-source-sized-symbolic-cap`,
`source-sized-symbolic-cap-name`, `source-sized-symbolic-cap-route`, and
`component-source-sized-symbolic-cap-route` rows. The name rows identify the
exact cap; the route rows state the primitive family that should replace or
justify it: source partition plus prefix/scatter, depth-parent sort/join/scatter,
record relation sort/reduce/scatter, or segmented regalloc scan/scatter. The
measurement scaffold carries `source-sized-symbolic-cap`,
`source-sized-symbolic-cap-by-component`, `source-sized-symbolic-cap-names`,
`source-sized-symbolic-cap-route`, and
`source-sized-symbolic-cap-route-by-component` into pass-contract blockers and
measurement-plan summaries, so symbolic source-sized caps remain visible and
assignable even when the broad paper-pass blocker queue is empty.
Literal cap extraction is tied to the `for` induction variable, not to every
comparison in the loop header. A bounded symbolic loop such as
`guard < ANGLE_CONTEXT_SCAN_LIMIT && pos > 0u` must not be counted as
`explicit-fixed-literal-cap-0`; the `pos > 0u` clause is a data-dependent guard,
and the pass must be routed as `publish-guard-records-prefix-sum-scatter` unless
the helper bound is proven local.
It also publishes `component-reason-rewrite-route` rows, which add the owning
subsystem to that reason/route pair. Summary-only audit output can therefore
assign source-sized rewrite work directly, such as
`codegen-wasm:source-or-dispatch-sized-loop:partition-source-records-prefix-sum-scatter`,
without opening detail rows or running generated performance cases.
The generated check-env gate uses the x86-scoped codegen audit with both
`--fail-on-x86-codegen-review-required` and
`--fail-on-x86-codegen-large-fixed-bound`. Its notes must report the scoped
x86 review-required, fixed-bound, and large-fixed-bound counts, so x86 bounded
helper loops stay visible without reclassifying review blockers away.
The same generated check-env path also publishes a repository-wide no-run
Pareas pass-structure gate as
`measurement_shader_loop_pareas_pass_gate_status=ok`. That gate is derived from
the compact `tools/shader_loop_audit.sh --summary-only` contract and fails if
the cached summary has any `paper-pass-blocker`, `review-required`,
`source-sized-symbolic-cap`, suspicious `[loop]`/`[unroll]`, or raw-for review
blocker count. It also publishes the `paper-pass-local-review`,
`record-map-prefix-scan-scatter`, and
`source-record-partition-prefix-scan` counts as public output, so local timing
or VRAM evidence cannot be separated from the Pareas-style pass-structure
inventory. The generated environment check must publish both
`measurement_shader_loop_pareas_pass_gate_status` and
`measurement_shader_loop_pareas_pass_gate_blockers` even when the gate is
blocked, so failed readiness artifacts carry the exact pass-structure reason
instead of requiring readers to infer it from broader scaling-claim blockers.
The same check-env output must also expose the symbolic-cap count by component,
the exact cap names, the replacement route rollup, and the component/route
rollup. Those are the assignment rows for removing source-, tree-, record-, or
program-sized shader helper loops, not performance measurements.
Parser and type-checker scoped gates exist for the same reason: they fail when
their own shader component has data-dependent, `while`, or unknown-bound loops,
and the scoped symbolic-cap gates fail when local helper loops are capped by
names that look source, tree, or record sized. Use those component gates before
promoting new parser/HIR or semantic passes into readiness evidence, so
source-sized front-end loops do not hide behind a clean codegen audit.
The generated command-environment and measurement-summary artifacts must carry
the same shader-loop audit command, policy, compact summary, Pareas pass-gate
status/blockers, and source-sized symbolic-cap route fields. A performance row
without that audit context is not enough to make or compare a pass-contract
claim, because it cannot show which source-sized loop classes were still
blocking the paper/Pareas pass shape.
The no-run measurement plan must also publish `checkpoint_execution_order` and
`checkpoint_run_policy`. A reduced 5k/10k plan is allowed, but its runbook must
refer to the actual checkpoint order rather than preserving stale 20k sequencing
text. This keeps small future checks reproducible without turning the plan into
scale evidence.
The optional Pareas artifacts in the measurement scaffold must also carry
`claim_boundary=optional-local-comparison-provenance-not-pareas-claim`. Their
source, source line count, stdout, output, compiler hash, and VRAM rows are
local comparison provenance only; the readiness verifier must not treat their
presence, or a clean shader-loop route summary, as a Pareas performance claim.
If a Pareas source artifact exists, its line count must cover the checkpoint
line count before a 5k/10k comparison row can be fresh. Smaller Pareas inputs
are stale provenance, not local comparison evidence.
The measurement plan must also keep
`measurement_scaffold_evidence_status=no-run-plan-not-local-performance-evidence`
and `paper_baseline_claim_status=not-local-performance-evidence`, and must
publish `cold_gpu_pipeline_init_policy` separately from
`steady_compile_latency_claim_source` and `steady_readback_claim_source`. Cold
GPU pipeline initialization is provenance context only; it cannot be folded into
steady compile or readback claims, and the no-run plan itself is never local
performance evidence.
Readback summaries are not standalone timing proof. A positive
`span_count`/`total_ms`/`max_span_ms` row must still point at a nonempty
Perfetto trace that records readback spans; otherwise the summary is stale
provenance and the local readback evidence remains incomplete.
Language-slice performance rows must carry the same boundary fields before they
count in readiness: `paper_pass_order_schema`, `paper_pass_order`,
`paper_pass_alignment_status=blocked`, non-empty
`paper_pass_alignment_blockers`, `parallel_pass_contract_schema`,
`parallel_pass_contract_order_policy`,
`parallel_pass_contract_execution_order`, `pass_contract_loop_status=bounded`,
`pass_contract_fallback_status=fail-closed`,
`pass_contract_claim_status=blocked`, non-empty
`pass_contract_claim_blockers`, `pass_contract_readiness_status=blocked`, and
`scaling_claim_blockers` that still name both `paper_pass_alignment:blocked` and
`pass_contracts:blocked`. The `pass_contracts:blocked` entry must remain a
top-level `pass_contracts:blocked` scaling blocker rather than only appearing
inside `paper_pass_alignment_blockers`, so a paper-alignment blocker cannot hide
bounded or fail-closed pass-contract debt.
It must also publish `workload_shape_policy`,
`workload_shape_scope`, `workload_generalization_status`, and
`workload_generalization_blockers`. Pareas' performance sections distinguish
wide/shallow source shapes from long-function or deeper-tree bottlenecks, so one
local generated checkpoint is only exact workload evidence and is not a general
compiler-performance claim.
The per-checkpoint measurement summary must carry that boundary into claim
readiness. While `workload_generalization_status=not-generalizable`, production
readiness blockers must include `workload_generalization:not-generalizable`,
and the claim-readiness requirements must demand
`workload_generalization_status=generalizable`. This prevents a complete local
timing/VRAM/Pareas artifact set for one generated source shape from being
promoted into a broad Pareas-comparable scaling claim.
The scaffold must also publish `link_artifact_evidence_policy`,
`link_artifact_evidence_schema`, `link_artifact_required_evidence_classes`,
`link_artifact_evidence_status`, and `link_artifact_claim_blockers` in the
measurement plan, command environment, command status, per-checkpoint summary,
evidence status, claim-readiness fields, and claim scope. The schema must be
`lanius.link-artifact-evidence.v1`, and the required classes are
`library_interface_artifacts`, `codegen_object_artifacts`,
`partial_link_artifacts`, and `linked_output_artifact`. Until the compiler emits
artifact-backed evidence for every named class, that status must remain
`not-artifact-backed`, and local performance or scaling claims must stay blocked
even if a whole-pack benchmark run, VRAM CSV, and Pareas comparison artifacts
exist.
The acceptance verifier also treats the compact shader-loop summary as a
self-consistent contract: classification totals, review-required totals,
component totals, component/risk totals, reason totals, paper-pass totals,
rewrite-route totals, reason/rewrite-route totals,
component/reason/rewrite-route totals, component/paper-pass totals, pass-shape
totals, component/pass-shape totals, paper-pass blocker/local-review totals,
component blocker totals, dedicated component-paper-pass blocker assignment
rows, component/rewrite-route blocker rows, dedicated local-review assignment
rows, and source-sized symbolic-cap name/route totals must agree before the
measurement plan can use the audit. The dedicated blocker rows must aggregate to
the same component, rewrite-family, and concrete-route rollups as the full
paper-pass rows after bounded-local review classes are removed, the local-review
rows must aggregate to the bounded-helper review count, pass-shape rows must
aggregate to the total scanned loop count, and source-sized symbolic-cap route
rows must aggregate to the `source-sized-symbolic-cap` review count. This keeps
routing metadata from drifting away from the pass-contract blocker count while
remaining a no-run evidence check.
The `audit-evidence-role` rows must also aggregate to the scanned loop total,
and the detailed `audit-evidence` rows must aggregate back to their role totals.
The `claim-blocker` audit-debt row must aggregate to the blocker plus
local-review role counts so saved no-run artifacts can fail closed on
performance/scaling or Pareas-parity claims without reinterpreting the detailed
role rows.
That rollup is intentionally separate from `paper-pass-blocker`: a zero
paper-pass blocker count can still have `blocker` rows when source-sized
symbolic caps or legacy fallbacks remain, and it can still have `local-review`
rows when bounded helpers lack a behavior-facing invariant. The audit publishes
`zero-paper-pass-blocker-not-pass-contract-proof` as a stable evidence-policy row
so summary-only artifacts carry that claim boundary without requiring readers to
infer it from the role counts.
The generated no-run scaffold, command-environment artifact, and
per-checkpoint measurement summary also publish `shader_loop_audit_blocker`
alongside the compact summary. That field is a derived pointer to the active
paper-pass/review blocker count, not a reclassification; it must be `none` when
the raw audit has `paper-pass-blocker=0` and `review-required=0`. Bounded-local
helper review remains visible as `paper-pass-local-review`; it is not a
production-readiness claim. The pass-contract blocker string must still carry
`shader_loop_audit_local_review_N` when that local-review count is nonzero, so a
zero paper-pass/review blocker pointer cannot be mistaken for a claimable
parallel-pass contract. Carrying both the derived blocker pointer and the
local-review blocker through saved artifacts prevents a local measurement from
dropping the paper/Pareas pass-contract boundary while still presenting timing,
VRAM, or Pareas provenance fields. The local-review-by-component and
local-review-by-route fields provide the same protection for bounded-helper
justification debt, so an empty paper-pass blocker queue cannot hide the
subsystems that still need local helper justification or replacement.

The x86 codegen gate is intentionally scoped. Wasm codegen is currently
fail-closed and should use the Wasm-specific gates only when that backend is
being rebuilt explicitly.
Generated scale evidence must stay small until the pass contract is claimable.
The no-run measurement scaffold defaults to the 5k checkpoint and rejects
checkpoints above 5k lines or more than three measurement iterations unless
`LANIUS_ALLOW_LARGE_GENERATED_TESTS=1` is set. That guard is verified by
`compiler_acceptance_measurement_plan_rejects_large_workloads_without_opt_in`
and exists so 5k-first artifact planning can test provenance, pass-order, and
Pareas-style loop boundaries without treating 10k, 20k, or 100k runs as routine
regression tests or local performance evidence.
Build-time shader bundling also rejects any single active SPIR-V artifact above
`LANIUS_SHADER_MAX_SPV_BYTES`, which defaults to 4 MiB and can be set to `0`
only for local investigation. This is a cold-pipeline guard, not pass-contract
evidence: a shader below the cap can still need record/count/scan/scatter/join
decomposition, but a shader above the cap is too monolithic to rely on for
routine production builds.
The build also publishes the active guard status, cap, shader artifact count,
largest artifact name, and largest artifact byte size through `laniusc
--version` and `laniusc doctor`, so local measurement artifacts can record
which guard was in force without re-scanning the build directory.

## Current No-Run Snapshot

As of 2026-06-01, `tools/shader_loop_audit.sh --summary-only` reports 71
scanned loops: 61 fixed-bound, 10 fixed-bound-guard, and zero data-dependent,
`while`, unknown-bound, high-risk, review-required, or large-fixed-bound rows.
The broad paper-pass blocker queue is empty, but the stricter audit-evidence
role split still has local-review rows, so the pass contract is not
claimable.

The same snapshot reports zero source-sized symbolic-cap candidates. The
remaining audit debt is bounded-helper local review, not a source-sized shader
loop blocker.

The `pass-shape` rows split the same 71 loops into:

- `pareas-primitive-bounded-loop`: 21
- `bounded-local-helper-review`: 50

The `audit-evidence-role` rows intentionally split the same 71 loops by claim
boundary:

- `proof`: 21
- `blocker`: 0
- `local-review`: 50

The `claim-blocker` rows publish the same boundary directly for performance,
scaling, and Pareas-parity artifacts:

- `performance-scaling-or-pareas-parity-audit-debt`: 50
- `performance-scaling-or-pareas-parity-audit-blocker`: 0
- `performance-scaling-or-pareas-parity-local-review`: 50

Those rows are no-run engineering evidence for assignment and review only. They
do not prove shader correctness, performance, Pareas equivalence, or production
readiness. The blocker rows are currently zero; local-review rows still block
performance and Pareas-parity claims until bounded helper loops are justified or
rewritten.
