# Testing Strategy

This compiler is being built toward arbitrarily large source packs where the CPU
coordinates work and the GPU does the data-plane compilation. Tests should prove
that architecture with small, high-signal cases instead of relying on large
benchmarks or exact source-layout checks.

## Default Rule

Before adding, changing, or running tests, state the behavior contract, state
space, fault model, smallest useful test shape, and the plausible bug the test
would catch.

Prefer the narrowest test that exercises the relevant contract. Do not run broad
GPU suites, generated 10k/20k cases, Pareas comparisons, or whole-workspace tests
unless the changed surface requires that scope. The default generated and
capacity-gate size is 5k lines; 10k and 20k are explicit checkpoints, not normal
regression defaults.
The `readiness` tier intentionally rejects `--run`; it is a no-run inventory and
evidence-discipline gate, not a compile/test execution lane.

## Per-Change Test Charter

Every change should carry a short test charter before any verification command is
chosen. It can be one paragraph in a progress note, PR note, or final response,
but it must answer these points:

- **Contract:** What behavior, record invariant, persisted schema, or public
  boundary must keep working?
- **State space:** Which inputs, records, dependency graphs, page boundaries,
  resource limits, or generated cases matter for this change?
- **Fault model:** Which failures should this layer detect or tolerate, and
  which failures belong to another layer?
- **Smallest test shape:** What is the smallest CPU model, record invariant,
  GPU pass, generated case, or integration boundary that can expose the bug?
- **Plausible bug:** What realistic mistake would make this test fail?
- **Stop condition:** What evidence is enough, and what would justify moving to
  a broader lane?

Do not add a test that cannot answer the plausible-bug question. Rewrite or
delete tests whose main failure signal would be "the implementation changed"
rather than "the contract broke."

When a positive test bundles several language features, split the cases before
changing expectations. A supported case should still pass when run by itself.
If isolating a case exposes unsupported behavior, delete the misleading
positive or move it to an explicit future-work note instead of hiding it inside
a broad "accepts" test.

For stdlib and source-pack coverage, do not add parse/type-check-only seed
tests that merely include a library file. The test should exercise a public
module contract from a caller, such as an imported function, type alias, trait
obligation, method, constant, host ABI declaration, or a rejection at that
boundary.

## Behavior And Property Evidence

Readiness evidence should be stated as a behavior or property before it is named
as a test. Good evidence says what must stay true for callers, persisted
artifacts, GPU-owned records, diagnostics, or executed output. It should not say
which helper, file, pass spelling, loop form, private table, or intermediate
buffer happened to implement that behavior.

Prefer properties that remain true across harmless rewrites:

- Equivalent source shapes produce the same accepted/rejected behavior.
- Renamed identifiers, reordered independent inputs, or helper-like names do not
  change semantics.
- Persisted artifacts round trip through the public schema without losing
  meaning.
- GPU record arrays satisfy ownership, range, ordering, prefix-sum, and
  cross-record join invariants.
- Unsupported language, runtime, backend, or package shapes fail before any
  fallback path can claim support.

Example tests are still useful for regressions and clear diagnostics, but every
example promoted as readiness evidence should identify the broader property it
guards. Generated and property tests must be deterministic, bounded, and
replayable; record the seed or fixed case, print enough source/artifact context
to reproduce the failure, and keep the default case count small enough for the
lane.

## Fail-Closed GPU Limits

A fail-closed GPU limitation is readiness evidence only when it proves a stable
negative contract at a public boundary. The test should show that an unsupported
shape is rejected with a stable diagnostic, no partial executable artifact is
published as success, and the CPU does not parse, type-check, monomorphize,
rewrite, link, or patch program semantics as a production fallback.

Fail-closed tests should prefer one smallest unsupported shape per contract:
non-compact rows, malformed owner/range records, unsupported ABI/runtime calls,
missing link artifacts, unclaimable measurement rows, or source-pack/package
states that would otherwise be easy to treat as supported. The assertion should
name the rejected contract and observable boundary, not the internal branch that
decided to reject it. Passing fail-closed tests keep the row `bounded` or
blocked; they do not promote the feature to executable production support.

## Test Ladder

Use this order by default:

1. Pure CPU model or unit tests for bounded planning, page validation, range
   math, serialization, and deterministic schedulers.
2. Persisted round-trip tests for filesystem pages, manifests, shard indexes,
   work-queue progress, and descriptor artifacts.
3. Small GPU record-invariant tests with tens of rows, not thousands, for passes
   that consume and produce compiler records.
4. Fixed-seed generated semantic tests for name independence, equivalent source
   rewrites, and supported language slices.
5. Small architecture tripwires that prove durable behavior: name/shape
   independence, record-only handoffs between stages, fail-closed diagnostics for
   unsupported source shapes, and bounded artifact/page schemas. Do not prove
   these by grepping compiler, shader, or test source for helper names, function
   names, call structure, macro presence, or loop spellings.
6. Ignored or explicit opt-in scale/performance gates only when measuring
   capacity, latency, VRAM, or comparison against Pareas.

Escalate one rung at a time. If a focused test gives the required evidence, stop.

## Active Production-Readiness Gates

Use this small gate set before adding larger runs to the production-readiness
tracker. These are examples of the evidence shape the suite should keep growing:
property/model tests, runtime-invariant checks at public record boundaries,
fixed-seed generated behavior, and no-run measurement scaffolds.

- **No-run discipline gate:**
  `tools/compiler_acceptance.sh --tier readiness --check-plan`.
  This verifies that the focused, smoke, and properties inventories are
  concrete and that every named evidence filter resolves to an actual Rust test
  function. Stale or deleted filters do not count as readiness evidence, and
  duplicate references within the same lane are rejected instead of being
  counted as additional coverage. The production-readiness matrix snapshot must
  also match the gate's computed evidence, command, language-slice,
  source-scoped, performance-guard, and test-discipline counts before the gate
  passes. The discipline policy rejects compiler/shader source inspection as
  evidence, and the gate audits Rust integration tests for direct
  compiler/shader product-source reads or command-based inspection probes,
  reporting the current-tree Rust integration test file count instead of relying
  on a hand-maintained inventory number,
  including split `Command::new("rg")`, `Command::new("grep")`,
  `Command::new("cat")`, `Command::new("sed")`, `Command::new("awk")`,
  or `Command::new("python")`/`Command::new("python3")`
  invocations whose later arguments point at `src/` or `shaders/` product paths
  from top-level or nested integration-test modules,
  manifest-relative product-source paths built with either `Path::join` or
  incremental `PathBuf::push`,
  direct `include!`, `include_str!`, `include_bytes!`, `fs::read`,
  `fs::metadata`, `fs::read_dir`, `fs::canonicalize`, `File::open`,
  `Path::new`, or `PathBuf::from` probes of compiler/shader product paths,
  `Command::new("git")` plus `grep`, `show`, or `cat-file` invocations against
  product-source paths, and shell-wrapped source-inspection probes launched
  through `Command::new("sh")` or `Command::new("bash")`. Named evidence filters
  are checked for existence, and module-qualified integration-test filters must
  resolve to the matching Rust module file instead of only matching a leaf
  function name. Library and binary evidence scopes are
  accepted only for public-boundary,
  artifact-contract, execution-contract, or measurement-scaffold rows. Semantic,
  record, and fail-closed diagnostic claims should use integration evidence or a
  public CLI/library boundary instead of a private unit test under `src/`. The
  current source-inspection audit is not blanket coverage over every unit test
  under `src/`, so promote source-scoped rows only when the cited test itself
  proves public behavior, artifacts, execution, or measurement scaffolds rather than
  implementation text.
  Parser/type handoff rows that downstream passes are expected to consume, such
  as parser-published method owners, must remain behavior-facing record or
  semantic contracts in the language-slice inventory. Parser-owned
  method-signature status flags currently have a planned inventory hook; promote
  that hook only when a parser HIR record gate, semantic gate, or stable
  diagnostic gate proves the handoff without compiler or shader source inspection.
  The same check requires performance rows in the language-slice inventory to
  stay `measurement-scaffold`/`no-run` evidence with
  `measurement_evidence_policy=local-artifacts-only`,
  `paper_numbers_accepted=false`,
  `paper_baseline_policy=reference-only-not-local-performance-evidence`,
  `local_performance_claim_status=blocked`, `scaling_claim_status=blocked`, and
  `claim_readiness_status=not-claimable` until local artifacts and pass
  contracts actually become claimable. The no-run measurement plan and saved
  summary artifacts also emit
  `paper_baseline_claim_status=not-local-performance-evidence` so artifact
  readers do not treat paper baselines as local claim evidence. The language
  slice performance rows must also name the paper pass order, blocked
  paper-pass alignment status, non-empty alignment blockers, parallel
  pass-contract schema/order fields, blocked pass-contract loop/fallback/claim
  readiness fields, non-empty pass-contract blockers, and scaling blockers tied
  to both `paper_pass_alignment:blocked` and `pass_contracts:blocked`.
  Diagnostic registry, categories, explain, formats, formatter policy, and LSP
  capabilities rows are required as no-run CLI public-boundary or
  artifact-contract gates, including the unknown-code explain path, formatter
  token-preservation/no-run guard policy, and LSP claim-boundary metadata that
  keeps capabilities from being counted as latency, throughput, production
  editor, or local-performance evidence.
- **Control-plane model gate:**
  `cargo test -p laniusc source_pack_work_queue_progress_page_transitions_match_reference_model -j1 --lib -- --test-threads=1`.
  This is the preferred shape for source-pack scheduling and resume work: a
  bounded reference model over job readiness, claims, expiration, completion,
  and dependent counters.
- **Record-invariant gate:**
  `cargo test --test parser_hir_records parser_hir_generic_type_arguments_link_owner_and_argument_chain -j1 -- --test-threads=1`.
  Parser and semantic pass changes should add similarly small record contracts:
  owner ranges are contiguous, ordinals are stable, spans stay within owners,
  and invalid rows fail closed before later passes consume them.
  Direct readback-validator fixtures are useful only when they protect a durable
  record contract and are paired with at least one source-program or source-pack
  integration check. For example, the flat HIR source-address ordering invariant
  uses `parser_hir_source_address_records_keep_public_rows_in_flat_source_order`
  for the row-level fail-closed cases and
  `parser_hir_item_records_are_source_addressable_in_source_packs` for the real
  parser readback path.
  Method declaration handoffs should use the trait/inherent and trait-impl
  parser HIR record gates:
  `parser_hir_trait_and_impl_method_declaration_records_are_source_addressable_in_source_packs`
  and
  `parser_hir_trait_impl_method_declaration_records_are_source_addressable_in_source_packs`
  rather than tests that search for a consumer helper or shader name.
  Method-signature status handoffs, such as method-level generic and where
  markers, should use the same behavior-facing lane once direct evidence exists;
  until then the language-slice inventory should keep only the planned hook.
  Relation handoffs such as parser-published expression roots and contextual
  statement rows should use the same lane, for example
  `parser_hir_resident_readback_publishes_expression_roots_and_statement_contexts`,
  which asserts resident readback records rather than pass names or shader text.
- **GPU semantic contract gate:**
  `cargo test --test type_checker_semantics type_checker_rejects_duplicate_generic_parameter_names_before_inference_on_gpu -j1 -- --test-threads=1`.
  Generics, traits, module paths, and monomorphization should prefer accepted or
  rejected programs with stable diagnostics over tests that mention pass names,
  shader filenames, buffer names, or private helper functions.
- **Deterministic generated property gate:**
  `cargo test --test codegen_x86_properties generated_x86_programs_are_name_and_shape_independent -j1 -- --test-threads=1`.
  Generated behavior tests must use fixed seeds or fixed generated cases, print
  enough context to replay a failure, and vary names/shapes that would expose
  token-local or spelling-driven bugs.
- **Small scaling scaffold gate:**
  `tools/compiler_acceptance.sh --tier generated --check-env` and
  `tools/compiler_acceptance.sh --measurement-plan`.
  These are no-run checks for the 5k default inventory, opt-in 10k/20k
  checkpoint inventory, command timeouts, source seeds, artifact paths,
  VRAM/readback fields, and Pareas placeholders.
  The generated `--check-env` lane also runs the bounded x86 codegen shader-loop
  audit gate:
  `tools/shader_loop_audit.sh --root shaders/codegen --summary-only --fail-on-x86-codegen-review-required --fail-on-x86-codegen-large-fixed-bound`.
  That gate submits no GPU work and blocks new x86 codegen data-dependent,
  `while`, unknown-bound, or large fixed-bound shader loops while reporting the
  scoped x86 fixed-bound count separately. Existing WASM review debt stays
  visible as measurement-plan blockers.
  Execute a real generated/performance run only after these pass, and start with
  the 5k checkpoint unless the bug is only visible at 10k or 20k.

Do not promote a new gate into this set unless it has a clear property or
reference model, bounded runtime, deterministic reproduction path, and a
failure that would identify a production-readiness blocker rather than a
private implementation rewrite.

## Default Lanes

Most changes should use one of these lanes instead of inventing a broad run:

- **Focused compile:** `cargo check --lib -j1`
- **Focused unit/model test:** `cargo test -p laniusc <module>::<test_name> -j1 --lib -- --test-threads=1`
- **Focused integration test:** `cargo test --test <file> <test_name> -j1 -- --test-threads=1`
- **Formatting check:** `rustfmt --edition 2024 --check <touched Rust files>`
- **Diff hygiene:** `git diff --check -- <touched files>`

`tools/compiler_acceptance.sh` is dry-run by default and prints the explicit
commands it would run. Use `tools/compiler_acceptance.sh --tier focused --run`
for the small CPU-only checkpoint. Use `--tier generated`, `--tier properties`,
or `--tier pareas` only when the changed surface needs that evidence.
Use `tools/compiler_acceptance.sh --tier focused --check-plan` to verify that
the focused acceptance command inventory is syntactically concrete without
compiling or executing any test binary.
Use `tools/compiler_acceptance.sh --tier readiness --check-plan` when the task
is production-readiness tracking rather than execution. It verifies the named
focused, smoke, and properties evidence inventory, the language-slice evidence
map, and the no-run measurement scaffold without compiling tests, submitting
GPU work, running generated scale gates, or invoking Pareas. The named
inventory check confirms the referenced test functions still exist, so a
deleted or renamed test cannot remain as phantom readiness evidence. It also
audits Rust integration tests so they do not read or inspect compiler/shader
product source text for implementation strings. Source fixtures,
behavior-test names, expected diagnostics, record rows, descriptor artifacts,
and no-run tool metadata remain valid evidence when the assertion is about the
external contract rather than the implementation text that produced it. Treat
the reported Rust integration test file count as an inventory checksum for the
current checkout, not as a coverage metric. The gate does not automatically
source-probe every `lib:laniusc` or `bin:*` evidence body under `src/`; those
references are restricted to public/artifact/execution/scaffold contracts before
they count as production-readiness evidence. The `readiness` tier intentionally
rejects `--run`; execute `focused`, `properties`, or `smoke` separately when a
real test run is needed.
  `laniusc doctor` publishes the same no-run policy under
  `readiness.test_discipline`, so wrappers can discover that the readiness gate
  checks named filters and test-source discipline without compiling or running
  tests.
Use `tools/compiler_acceptance.sh --tier generated --check-env` before an
intentional generated, VRAM/perf, or Pareas run to validate `cargo`, `slangc`,
generated gate environment values, the canonical 5k default measurement
inventory plus any explicitly opted-in larger checkpoints, the bounded x86
codegen shader-loop audit,
`nvidia-smi` availability policy, and optional Pareas configuration without
compiling or executing any test binary. The check-env output includes
machine-readable per-checkpoint artifact and status-field notes so missing
Lanius, Pareas, VRAM, or readback evidence is visible before a run starts.
`nvidia-smi` and Pareas are optional by default; set
`LANIUS_REQUIRE_NVIDIA_SMI=1` or `LANIUS_REQUIRE_PAREAS=1` when a measurement
run must include those comparisons.
Use `tools/compiler_acceptance.sh --measurement-plan` to print the no-run
5k performance/VRAM/readback report scaffold, or
`tools/compiler_acceptance.sh --write-measurement-plan target/lanius-measurements/plan.txt`
to write it. The scaffold records the release benchmark build command and, for
the explicit checkpoint list, the intended Lanius benchmark command,
stdout path, Perfetto trace path, readback trace inspection command and summary
path with span-count, total-readback, and max-span metrics, generated source
replay command, source content hash command, benchmark
binary hash command, hardware identity command, command-environment schema,
required fields, hash, and output path,
command-status identity fields for timeout, source mode, phase, target,
line count, seed, iterations, artifact paths, and the
`lanius.command-status.v1` schema label,
machine-readable `rustc_version`, `cargo_version`, and `slangc_version`
fields in the command-environment artifact,
an explicit `measurement_evidence_policy=local-artifacts-only`,
`measurement_scaffold_evidence_status=no-run-plan-not-local-performance-evidence`,
`paper_numbers_accepted=false`,
`comparison_baseline_policy=local-pareas-artifacts-only`, and
`freshness_policy=hash-and-checkpoint-field-match`,
`measurement_timing_policy=compile-latency-claims-use-benchmark-best-ms-wall-time-is-provenance`,
`cold_start_policy=excluded-from-claimable-compile-latency-captured-as-wrapper-wall-time`,
`cold_gpu_pipeline_init_policy=cold-gpu-pipeline-init-is-provenance-only-excluded-from-steady-compile-and-readback-claims`,
`compile_latency_claim_source=benchmark-stdout-best-ms-local-run-only`,
`steady_compile_latency_claim_source=benchmark-stdout-best-ms-local-run-only-excludes-cold-gpu-pipeline-init`,
`steady_readback_claim_source=readback-summary-host-readback-spans-local-run-only-excludes-cold-gpu-pipeline-init`,
`runtime_validation_policy=validate-output-only-not-runtime-performance-claim`,
`workload_shape_policy=single-generated-workload-is-checkpoint-local-not-general-language-performance`,
`workload_shape_scope=line-count-source-phase-target-seed-binary-hardware-only`,
`workload_generalization_status=not-generalizable`,
`workload_generalization_blockers=multi-shape-local-artifacts-required,long-function-and-wide-tree-shape-coverage-required`,
`claim_provenance_schema=lanius.measurement-claim-provenance.v1`,
`baseline_separation_schema=lanius.measurement-baseline-separation.v1`,
`paper_baseline_policy=reference-only-not-local-performance-evidence`,
`paper_baseline_numbers_status=reference-only-not-ingested`,
`local_evidence_status_policy=claimable-only-from-fresh-local-artifacts`,
`local_performance_claim_policy=blocked-until-local-artifacts-link-artifacts-behavioral-pass-contracts-and-claim-boundaries-are-complete`,
`local_performance_claim_source=benchmark-stdout-best-ms-plus-local-artifact-freshness`,
`local_performance_claim_status=blocked`,
`local_performance_claim_blockers=local_artifacts_and_repeatability_must_be_complete,pass_contracts:blocked:...`,
`local_vram_claim_source=nvidia-smi-local-csv-plus-status-artifact`,
`local_pareas_claim_source=local-pareas-source-output-stdout-compiler-hash-provenance-only`,
`scaling_claim_policy=no-scaling-claims-without-local-artifacts-behavior-facing-pass-contracts-and-claimable-boundaries`,
`scaling_claim_source=multi-checkpoint-local-artifacts-plus-claimable-parallel-pass-contracts-and-paper-order`,
`scaling_claim_status=blocked`,
`scaling_claim_blockers=pass_contracts:blocked:...,paper_pass_alignment:blocked:...,multi_checkpoint_rollup_required`.
The plan must require `pass_contracts:blocked` as a top-level
`pass_contracts:blocked` scaling blocker rather than only as nested
paper-alignment context.
`paper_pass_order_schema=lanius.paper-pass-order.v1`,
`paper_pass_order=lexical_analysis,parsing,semantic_analysis,intermediate_code_generation,optimization,machine_code_generation`,
`paper_pass_alignment_status=blocked`,
and `timeout_provenance_schema=lanius.timeout-provenance.v1`,
`claim_readiness_schema=lanius.measurement-claim-readiness.v1`,
`claim_readiness_policy=complete-local-evidence-only`,
`claim_scope_policy=exact-local-checkpoint-hardware-source-binary-only`,
`source_control_policy=git-head-plus-status-in-command-environment-hash`,
`repeatability_policy=claimable-metrics-require-at-least-three-iterations`,
Lanius process resource-usage output path, a post-run responsiveness probe
command with a versioned artifact schema,
optional `nvidia-smi` sampling command, Pareas comparison source generation,
source-hash command, Pareas compiler-hash command, optional Pareas command,
wrapped commands that record exit status, timeout, line count, seed, iteration
metadata, responsiveness-probe status, and resource-usage
artifact status, readback timeout, VRAM sample interval, source, phase, target,
GPU timing env, output paths, a per-checkpoint summary TSV command and path, the
`lanius.measurement-plan.v1` and
`lanius.measurement-summary.v1` schema labels, required status and summary
fields, Lanius wall-clock elapsed time, optional Pareas wall-clock/status
fields, command-environment hash, optional Pareas comparison artifacts including
the generated Pareas source hash, Pareas compiler binary hash, and Pareas VRAM
CSV status, the `lanius.measurement-evidence-freshness.v1` freshness fields,
and the required checkpoint artifact inventory.
The per-checkpoint `lanius.measurement-summary.v1` rollup must carry both the
generated source SHA-256 and the measured benchmark binary SHA-256 with their
artifact paths, so a published timing can be tied back to the exact input and
exact `target/release/gpu_compile_bench` binary used for the run. It also
carries the hardware-identity artifact hash and command-environment hash so a
claim cannot silently move across machines or run environments. When the
optional Pareas comparison is used, the rollup must also carry the generated
Pareas input SHA-256 and Pareas compiler binary SHA-256 so the comparison input
and comparison compiler both have local artifact provenance rather than
paper-number or path-only provenance. It must also record
`evidence_provenance=local-run`,
the timing/cold-start policy fields, and timeout provenance fields
(`timeout_scope`, `timeout_source`, `timeout_enforced_by`, timeout exit code,
and whether that exit code means timed out), so wrapper wall-clock/cold-start
time is not confused with the benchmark stdout `best_ms` compile-latency
source and a timeout is traceable to the configured command guardrail rather
than treated as a performance result.
Cold GPU pipeline creation has its own policy field and may only be treated as
wrapper/provenance context. Steady compile and readback claims must cite the
explicit steady-source fields, not pipeline creation, process startup, or the
no-run plan itself.
The runtime surface in this scaffold is validation only:
`runtime_validation_policy=validate-output-only-not-runtime-performance-claim`.
Do not publish runtime-performance claims from these artifacts without a
separate runtime benchmark artifact and local provenance.
The workload surface is checkpoint-local only. The scaffold and saved artifacts
must preserve `workload_shape_policy`, `workload_shape_scope`,
`workload_generalization_status`, and `workload_generalization_blockers` so a
single generated source mode, line count, seed, binary, and machine cannot be
reported as general Lanius performance across arbitrary source shapes.
The claim-provenance fields are required on both the command-environment
artifact and the per-checkpoint summary. Paper baselines can be cited only as
reference context; they are never accepted as local performance, VRAM, scaling,
or Pareas comparison evidence.
The no-run scaffold's `measurement_scaffold_evidence_status` must remain
`no-run-plan-not-local-performance-evidence`; it is a plan/inventory boundary,
not local performance evidence and not Pareas comparison evidence.
`required_artifacts_complete`, and `missing_required_artifacts` so paper
numbers, manual estimates, or partial local artifacts cannot be mistaken for a
complete production-readiness measurement. It also carries
`measurement_evidence_policy=local-artifacts-only`,
`paper_numbers_accepted=false`,
`comparison_baseline_policy=local-pareas-artifacts-only`, and
`freshness_policy=hash-and-checkpoint-field-match`, so Pareas comparisons must
be backed by local Pareas source, output, stdout, and compiler-hash artifacts
plus stale-artifact checks rather than paper tables or remembered numbers. It
also emits a versioned
`lanius.measurement-evidence-status.v1` row with local performance, readback,
VRAM, and Pareas evidence statuses plus
`production_readiness_evidence_complete`; that field remains false until all of
those local evidence classes are complete.
It also emits a versioned claim-readiness row. `claim_readiness_status` remains
`not-claimable`, `claimable_measurement_claims` remains `none`, and
`claim_readiness_blockers` repeats the missing evidence classes until the local
Lanius, readback, local VRAM, Pareas, Pareas VRAM, responsiveness, resource-usage,
source-control, and freshness checks are all complete and the checkpoint used
at least the declared
`minimum_iterations_for_claim`. It also remains blocked while
`local_performance_claim_status` is not `claimable`, while
`pass_contract_readiness_status` is not `claimable`, or while
`scaling_claim_status` is not `claimable`. That lets the scaffold record local
artifact evidence without turning paper baselines, bounded loops, fail-closed
fallbacks, or a single checkpoint into performance/scaling claims. The local
performance blocker explicitly names missing local artifacts and repeatability
separately from pass-contract blockers, so a blocked pass contract cannot hide
missing measurement evidence. The same row must also publish
`claim_readiness_required_evidence_classes` and
`claim_readiness_required_statuses`, including the requirement that
`local_pareas_vram_evidence_status` is complete for Pareas comparison claims,
`source_control_state` is known as `clean` or `dirty`, that
`source_control_revision` is a commit-shaped revision that resolves in the
captured local Git checkout, and the
pass-contract requirement that loop status is claimable and fallback status is
absent rather than merely fail-closed. The default one-iteration plan is still
useful for local smoke evidence, but its summary must carry
`repeatability_status=insufficient` and remain non-claimable. This is the
no-run boundary between "the measurement was planned" and "a
performance/scaling claim may be made".
When evidence becomes claimable, the summary still scopes the claim to the
exact local checkpoint, hardware environment, generated source hash, and
benchmark binary hash through `claim_scope_policy` and `claim_scope_key`.
The same claim scope carries local VRAM and Pareas VRAM evidence statuses, so a
future timing or Pareas ratio row cannot be separated from the GPU memory
evidence that made the comparison claimable.
The summary also carries `source_control_state` and
`source_control_revision`, derived from the captured `git_head` and
`git status --short` block in the command-environment artifact, so dirty
worktree measurements are clearly local checkpoint evidence rather than clean
release evidence. Missing source-control snapshots, unavailable revisions,
non-commit-shaped placeholders, or commit-shaped hashes that do not resolve in
the captured checkout keep measurement claims non-claimable.
The command-environment artifact also carries machine-readable Rust/Cargo/Slang
version fields, and missing tool-version fields keep freshness incomplete, so
measurements cannot silently move across compiler toolchains.
It also carries the `lanius.parallel-pass-contracts.v1` evidence-class set for the
checkpoint. A scale claim must stay tied to behavior-facing record, semantic,
execution, and measurement-scaffold evidence classes over GPU-owned record
boundaries; timing and VRAM evidence must carry the same ordered evidence-class
sequence instead of exact private pass names.
The measurement scaffold also carries the paper pass order
`lexical_analysis,parsing,semantic_analysis,intermediate_code_generation,optimization,machine_code_generation`
from the checked-in GPU compilation papers and keeps
`paper_pass_alignment_status=blocked` while a pass-order stage such as
optimization is covered only by a narrow, non-claimable local pass contract.
That status is a first-class claim-readiness blocker, not just descriptive
metadata, so pass-contract and artifact evidence cannot become a generalized
performance/scaling claim while the paper-stage sequence is still incomplete.
The same artifacts carry `lanius.parallel-pass-contract-status.v1` fields:
`pass_contract_loop_status`, `pass_contract_fallback_status`,
`pass_contract_claim_status`, `pass_contract_claim_blockers`, and
`pass_contract_readiness_status`.
The no-run scaffold also records `tools/shader_loop_audit.sh` output as a
shader-loop inventory summary. That audit is not a correctness proof and is not
a substitute for behavior tests. It counts fixed-cap loops with data-dependent
early exits separately as `fixed-bound-guard`, while data-dependent, `while`, or
unknown-bound shader loops keep pass-contract readiness blocked until the loops
are replaced by prefix/sort/scatter/record passes or explicitly reclassified
with stronger evidence. The current raw audit reports `total=71`,
`paper-pass-blocker=0`, `review-required=0`,
`paper-pass-local-review=71`, and `source-sized-symbolic-cap=0`.
The claimable evidence-role split is stricter: `proof=21` is only pass-shape
proof, while `blocker=0` and `local-review=50` are claim blockers or review
debt. The audit also emits
`performance-scaling-or-pareas-parity-audit-debt=50`, split into blocker `0`
and local-review `50`, so zero paper-pass blockers cannot be read as a
performance/scaling or Pareas-parity claim.
The summary also
breaks out `paper-pass-blocker`, `paper-pass-local-review`,
`record-map-prefix-scan-scatter`, `source-record-partition-prefix-scan`,
`codegen-review-required`, `wasm-codegen-review-required`,
`x86-codegen-review-required`, `parser-review-required`,
`type-checker-review-required`, `wasm-codegen-fixed-bound`,
`x86-codegen-fixed-bound`, `parser-fixed-bound`, and
`type-checker-fixed-bound`, plus `source-sized-symbolic-cap`, so fixed-bound
loops are not reported as the same risk class as paper/Pareas rewrite blockers
or backend/front-end review blockers.
The measurement scaffold also publishes `top-component-paper-pass-blocker`,
`paper-pass-blocker-by-component`, `paper-pass-blocker-by-rewrite`, and
`paper-pass-blocker-by-component-route` as routing metadata for subsystem and
Pareas-style rewrite planning; they are not performance metrics and cannot make
the pass contract claimable by themselves. The component-route field is the
blocker-only work queue because it names both the owning shader area and the
concrete primitive route such as
`publish-records-map-prefix-sum-scatter`.
It also publishes `paper-pass-local-review-by-component` and
`paper-pass-local-review-by-component-route` so bounded helper-loop
justification debt stays routed by subsystem and route even when the
paper-pass/review blocker queue is empty.
The compact summary must carry `audit-evidence-proof`,
`audit-evidence-blocker`, `audit-evidence-local-review`, and the matching
claim-blocker fields for performance/scaling or Pareas parity. The acceptance
gate reconciles those fields with the raw total so blocker/local-review debt
cannot be hidden behind pass-shape proof rows.
The derived `shader_loop_audit_blocker` field is also emitted directly in the
measurement plan and generated check-env notes. It must remain `none` when the
audit has no paper-pass or review-required loop debt; bounded-local helper
review is reported separately as `paper-pass-local-review`. When paper-pass or
review-required debt reappears, this field carries the current
`shader_loop_audit_paper_pass_blocker_N` or
`shader_loop_audit_review_required_N` blocker without weakening the underlying
summary. The pass-contract blocker list separately carries
`shader_loop_audit_local_review_N` while bounded-local review remains nonzero,
so local-helper review cannot be promoted into a claimable pass contract just
because the paper-pass/review-required blocker pointer is `none`.
It also carries `source-sized-loop-rewrite-route` in the compact shader-loop
summary, derived from `reason-rewrite-route`, so source/dispatch-sized loop debt
has an explicit `partition-source-records-prefix-sum-scatter` rewrite route.
The companion `source-sized-loop-rewrite-route-by-component` field is derived
from `component-reason-rewrite-route` rows, so the no-run plan can assign that
same rewrite class to the owning subsystem without treating it as a performance
measurement.
The raw audit also emits `component-paper-pass-blocker` rows for the same
subsystem/rewrite pairs after bounded-local review rows are removed, making the
summary-only audit usable as the assignment queue for non-local pass rewrites.
It also emits `component-rewrite-route-blocker` rows for the concrete
primitive-route queue used by the measurement summary.
The matching `component-paper-pass-local-review` and
`component-rewrite-route-local-review` rows are local-helper justification
queues; they keep bounded-local work visible without changing the blocker
count.
The readiness verifier checks that these audit summaries are internally
consistent before accepting them into the measurement plan: classification,
risk, component, component/risk, reason, paper-pass, rewrite-route,
reason/rewrite-route, component/reason/rewrite-route, and component/paper-pass
totals must all match
the scanned loop total; blocker totals and the dedicated
`component-paper-pass-blocker` and `component-rewrite-route-blocker` assignment
rows must match their component and rewrite rollups; local-review assignment
rows must match the local-review total; review-required totals must match the
data-dependent/unknown/while classifications; and source-sized rewrite routes
must match the
`source-record-partition-prefix-scan` count. This is a no-run evidence-contract
check, not a source-code grep or performance claim.
Generated command-environment and measurement-summary artifacts must also carry
the shader-loop audit command, policy, and compact summary so local performance
rows remain scoped to the no-run pass-contract audit that made them
non-claimable or claimable.
Use `--fail-on-x86-codegen-review-required` together with
`--fail-on-x86-codegen-large-fixed-bound` for the current generated check-env
guard. The check-env notes must publish the scoped x86 review-required,
fixed-bound, and large-fixed-bound counts, so bounded x86 helper loops remain
visible without weakening the review blocker. Use
`--fail-on-wasm-codegen-review-required` when working Wasm backend debt
explicitly. The current Wasm body emitter is fail-closed and does not contribute
source-sized cap rows, but Wasm remains non-executable until rebuilt from
record/count/prefix-sum/scatter passes.
Use `--fail-on-parser-review-required` and
`--fail-on-type-checker-review-required` before promoting parser/HIR or semantic
GPU passes into readiness evidence. Those scoped gates catch front-end
data-dependent, `while`, or unknown-bound loops without conflating them with
codegen debt, while bounded parser/type-checker helper loops remain separately
visible for justification or replacement.
The current no-run boundary classifies the pass contracts as
`pass_contract_loop_status=bounded`,
`pass_contract_fallback_status=fail-closed`, and
`pass_contract_claim_status=blocked`, which derives
`pass_contract_readiness_status=blocked`, so the summary cannot become
claimable even if timing, VRAM, readback, and local comparison artifacts are
later filled in without reclassifying those pass contracts.
That order is a readiness contract for the paper-derived GPU compilation
architecture, not a permission to use paper timing numbers as local evidence.
The language-slice tracker must classify the bounded no-run pass-order evidence
separately from planned link/pass-order gaps such as GPU link/object emission
and the object-link pipeline. Planned rows cannot cite or count production
evidence; moving one to bounded requires a behavior, record, artifact,
execution, or measurement-scaffold contract that proves the ordered GPU record
boundary, not a source grep or private pass-name list.
Timing and VRAM
numbers alone are not evidence that the compiler architecture scales.
Do not generalize one checkpoint to other hardware, other generated sources,
other compiler binaries, or arbitrary codebases without separate matching local
artifacts.
The local performance evidence status cannot become `complete` unless the
resource-usage artifact status is successful and the summary carries user CPU
seconds, system CPU seconds, max RSS, and a locally derived
`throughput_lines_per_second` value computed from the checkpoint line count and
the benchmark stdout `best_ms`. Quantitative summary fields such as
`best_ms`, wrapper wall time, readback span counts/total/max timing, VRAM
bytes, resource usage, and Pareas wall ratio must parse as numbers before
freshness or evidence status can complete, so throughput claims are paired with
a bounded CPU/memory signal and cannot be supplied as prose, paper numbers, or
copied labels. Readback freshness also requires internally consistent span
metrics: a zero-span summary cannot carry nonzero timing, and a maximum span
cannot exceed total readback time.
The source replay artifact is also counted, and a summary is stale when the
replayed source has fewer lines than the checkpoint claims. This keeps a copied
small fixture plus a fresh hash from masquerading as 5k/10k/20k evidence.
The rollup also emits a `lanius.measurement-evidence-freshness.v1` row with a
freshness status and named stale-artifact checks, so reused source hashes,
benchmark binary hashes, Pareas compiler hashes, command-status schemas/status files,
command-environment metadata, readback summaries, readback span metrics,
responsiveness probes, or hardware identity artifacts stay visible as blockers.
VRAM and Pareas evidence
also require matching local status metadata for the same checkpoint paths and
line count, and VRAM CSVs must expose the expected normalized `nvidia-smi`
columns, so copied CSVs or comparison outputs cannot become claimable by
themselves.
Each checkpoint also has an `evidence_artifact` manifest that maps the artifact
name to its canonical path, producer command, status field, and evidence claim,
including the optional Pareas input source and compiler hash rather than only
the Pareas compiler invocation. Each manifest row must also carry `claim_source` as
`local_artifact`, `derived_local_artifacts`, or
`optional_local_comparison_artifact`, so paper-number or manual-estimate
provenance cannot satisfy the artifact inventory. Each row must also carry
`claim_boundary`; optional Pareas rows use
`claim_boundary=optional-local-comparison-provenance-not-pareas-claim`, so a
Pareas source/stdout/output/hash/VRAM artifact remains comparison provenance
rather than a Pareas performance claim. The manifest itself has a versioned
`lanius.measurement-artifacts.v1` schema and required manifest-field inventory,
so missing artifact-to-producer/status fields are visible before any checkpoint
is run.
The no-run scaffold publishes the same parallel-pass evidence classes on each
checkpoint: record invariants, semantic contracts, execution contracts, and the
measurement scaffold. Each row records `loop_status` and `fallback_status`;
those values are artifact claim metadata, not source-code greps or proof that a
private helper was called.
It still does not build, run Lanius, run Pareas, query hardware, or sample the
GPU.
Scale/performance lanes require a second opt-in before execution:
`tools/compiler_acceptance.sh --tier generated --run --allow-scale` or
`LANIUS_ACCEPTANCE_ALLOW_SCALE=1`. This applies to `generated`, `pareas`, and
`all`; dry-runs and `--list-tests` remain safe without the opt-in.

All scripted Cargo test commands should use `-j1` and `-- --test-threads=1`
unless the task is explicitly about test parallelism.

Generated and Pareas subprocesses must have explicit command timeouts. The
default generated-gate subprocess timeout is
`LANIUS_GENERATED_GATE_COMMAND_TIMEOUT_MS=120000`; raise it only for intentional
capacity or performance measurement. Generated x86 readback defaults to
`LANIUS_X86_READBACK_TIMEOUT_MS=60000` inside generated gates unless the caller
sets a different value.
The no-run VRAM/perf planning gate uses
`LANIUS_PERF_CHECKPOINT_LINES=5000`, `LANIUS_PERF_LINES=5000`,
`LANIUS_PERF_SEED=3235798765`, `LANIUS_PERF_ITERS=1`,
`LANIUS_PERF_COMMAND_TIMEOUT_MS=120000`,
`LANIUS_X86_READBACK_TIMEOUT_MS=60000`,
`LANIUS_VRAM_SAMPLE_INTERVAL_MS=250`, and
`LANIUS_RESPONSIVENESS_PROBE_TIMEOUT_MS=2000` by default. Checkpoints above 5k
lines or more than three measured iterations require
`LANIUS_ALLOW_LARGE_GENERATED_TESTS=1`. Checkpoint values are parsed as decimal
line counts, emitted with canonical labels and artifact paths, and must be
strictly ascending so saved measurement artifacts have a reproducible order.
`LANIUS_PERF_LINES` must also match one of the planned checkpoint line counts,
so the primary artifact paths cannot point at a workload that the no-run plan
does not execute.
The focused no-run generated gate
`compiler_acceptance_measurement_plan_rejects_large_workloads_without_opt_in`
keeps this boundary executable without submitting GPU work: a 100k checkpoint
or more than three measurement iterations must fail before a plan is printed
unless the caller explicitly sets `LANIUS_ALLOW_LARGE_GENERATED_TESTS=1`.
The default plan paths live under `target/lanius-measurements/` and can be
overridden with `LANIUS_PERF_OUTPUT_PATH`, `LANIUS_PERFETTO_TRACE`,
`LANIUS_READBACK_SUMMARY_OUTPUT_PATH`, `LANIUS_VRAM_OUTPUT_PATH`,
`LANIUS_SOURCE_REPLAY_OUTPUT_PATH`, `LANIUS_SOURCE_SHA256_OUTPUT_PATH`,
`LANIUS_BENCH_SHA256_OUTPUT_PATH`, `LANIUS_HARDWARE_OUTPUT_PATH`,
`LANIUS_COMMAND_ENV_OUTPUT_PATH`,
`LANIUS_COMMAND_STATUS_OUTPUT_PATH`, `LANIUS_RESPONSIVENESS_OUTPUT_PATH`,
`LANIUS_RESOURCE_USAGE_OUTPUT_PATH`,
`LANIUS_MEASUREMENT_SUMMARY_OUTPUT_PATH`, `LANIUS_PAREAS_SOURCE_PATH`,
`LANIUS_PAREAS_SOURCE_SHA256_OUTPUT_PATH`, `LANIUS_PAREAS_OUTPUT_PATH`, and
`LANIUS_PAREAS_STDOUT_PATH`.

Do not append to `TEST_RUN_LOG.md`; it is historical only. Summarize current
verification in the final response or in the relevant PR/change note.

## Lane Boundaries

Keep the lane boundary explicit:

- **CPU/model lane:** bounded schedulers, range math, manifest/page schemas,
  work-queue progress, command-line guards, and artifact/diagnostic contracts.
  This is the default lane for compiler control-plane work.
- **Small GPU record lane:** shader or binding changes where the contract is a
  GPU-produced record array. Use tens of records and assert record invariants,
  not large end-to-end behavior.
- **Generated semantic lane:** fixed-seed name/shape/rewriting cases that prove
  source spelling and helper names are not controlling behavior. Keep defaults
  small and print enough seed/source context to replay failures.
- **Scale/performance lane:** generated 10k/20k gates, VRAM observations,
  Pareas comparison, and capacity sweeps. These are measurements or capacity
  checkpoints, not ordinary regression tests. Use 5k first when a generated
  case is needed to reproduce or classify a bug.

Escalation must cross only one boundary at a time. A CPU/model failure should be
fixed or classified before running GPU tests. A small GPU record failure should
be fixed or classified before running generated or Pareas gates.

Do not use `--tier all` for normal development. It is a checkpoint command for
an explicitly requested scale/performance pass and must be run with
`--allow-scale` or `LANIUS_ACCEPTANCE_ALLOW_SCALE=1`.

## Production Readiness Inventory

The no-run readiness inventory is a contract map, not a correctness proof. Its
job is to catch stale acceptance documentation quickly and make the current
evidence for the production objective inspectable without heavy work.

Run these before claiming the production-readiness tracker is current:

- `tools/compiler_acceptance.sh --tier readiness --check-plan`
- `tools/compiler_acceptance.sh --tier generated --check-env`
- `tools/compiler_acceptance.sh --measurement-plan`

The measurement plan is only evidence that the run is well specified. Actual
performance evidence needs saved outputs for each executed checkpoint:
benchmark stdout, generated source replay and SHA-256 hash, benchmark binary
SHA-256 hash, Perfetto trace, readback trace summary, resource usage, VRAM CSV,
hardware identity, command environment, command status/timeout metadata,
responsiveness-probe artifact,
the per-checkpoint
`lanius.measurement-summary.v1` TSV rollup with source and benchmark binary
hash fields, the command-environment hash, the source-control revision, the
parallel-pass contract policy,
and whether the 5k, 10k, and 20k checkpoints completed without readback
timeouts or responsiveness issues. The
rollup must also state local artifact provenance and whether every required
artifact was present. If Pareas was available, the same rollup must include
Pareas source hash, Pareas compiler binary hash, exit status,
wall-clock elapsed time, artifact paths, and a Lanius/Pareas wall-time ratio;
otherwise those fields must be present and marked `not-run`. The same rollup
must publish the evidence-status and freshness rows plus completion blockers,
so missing local performance, readback, VRAM, Pareas, or fresh artifact evidence
cannot be read as completion.
The readiness `--check-plan` gate also validates that the measurement scaffold
still contains the generated source replay command, source hash command,
benchmark binary hash command, generated benchmark command, wrapped
status-capturing benchmark command, readback summary, resource-usage capture,
VRAM sampling and wrapped sampler command, hardware identity, command
environment schema and capture, responsiveness-probe schema, command, status
field, and artifact path, measurement summary command,
optional Pareas source generation, source hash, compiler binary hash, and run placeholders, and the
artifact-to-producer evidence manifest for every checkpoint. It also validates
each checkpoint block has explicit line count, seed, iteration, timeout,
timing policy, cold-start policy, compile-latency claim source, runtime
validation policy, parallel-pass contract schema/groups/fields, timeout
provenance schema/fields, claim-provenance schema/source policies,
readback timeout, VRAM sample interval, target, GPU timing fields, required and
optional status fields, required summary fields, hardware-identity schema and
field inventory, optional Pareas comparison artifacts, the versioned required
artifact inventory, the versioned evidence-status schema and completion fields,
the versioned evidence-freshness schema and stale-artifact fields, and the
`lanius.measurement-artifacts.v1` manifest field inventory, including
per-artifact `claim_source` provenance. It also validates the
`lanius.measurement-claim-readiness.v1` schema, policy, required fields, and
summary command placeholders, plus the exact-local-checkpoint claim-scope policy
and scope key placeholders for source-control revision, repeated checkpoint
identity, and paper-order pass-contract execution, the required
evidence-class/status predicate fields, repeatability policy, minimum iteration
threshold, repeatability blocker, paper-pass alignment blocker, and
top-level `pass_contracts:blocked` scaling blocker plus pass-contract
loop/fallback status blockers, so
scaffold-only, bounded/fail-closed pass evidence, or single-sample evidence
cannot silently become a claimable or generalized measurement. The stale-artifact
inventory includes command-status schema and checkpoint matching plus
command-environment/checkpoint/provenance/pass-contract status matching, so a reused status or environment file
from another line count, source, phase, target, seed, iteration count, timeout,
readback timeout, VRAM sample interval, responsiveness timeout, VRAM output
path, Pareas compiler path, Pareas input path, Pareas output path, or Pareas stdout path does not
look fresh. Resource-usage artifacts are freshness checked against the recorded
command line from `/usr/bin/time -v`, so copied CPU/RSS measurements from
another checkpoint cannot satisfy local performance evidence. Quantitative
artifact fields are also freshness checked for numeric shape, so a stale or
hand-written summary cannot replace `best_ms`, readback timing, VRAM bytes,
CPU seconds, RSS, or Pareas ratio with arbitrary text and remain claimable.
VRAM freshness also checks the CSV header against the planned sampler columns
after normalizing spaces and unit suffixes, so a numeric CSV-like file from a
different source is not accepted as local GPU memory evidence.
It also verifies `tools/compiler_acceptance.sh` is directly executable, so the
published gate does not silently degrade into a shell-only snippet. The no-run
gate validates acceptance inventory shape instead of source-code strings: the
focused, smoke, and properties lanes must publish concrete evidence references,
and the properties lane must include public-boundary, record-invariant,
execution/codegen, and semantic evidence categories. The language-slice TSV
must also classify each supported or bounded row with one behavior-facing
`evidence_contract`: `public-boundary`, `artifact-contract`,
`record-invariant`, `semantic-contract`, `execution-contract`,
`fail-closed-diagnostic`, or `measurement-scaffold`. It does not grep
compiler or shader source for helper names, function names, loop spellings, or
implementation vocabulary. The explicit test-discipline audit only scans Rust
integration tests for product-source reads or command-based source-inspection
probes against `src/` and `shaders/`, including split command builders that add
those paths in later `.arg(...)` or `.args(...)` calls, Python-backed source
inspection helpers, shell-wrapped command strings, and direct Rust filesystem
metadata/listing/open/include probes of compiler or shader product paths. Its
current-tree file
count is useful for spotting inventory drift but is not a substitute for
behavior-facing evidence; ordinary readiness evidence must still come from
behavior, artifacts, diagnostics, or record rows rather than source-text
matches. Evidence scopes that resolve through library or binary tests are not
covered by that product-source-read audit today; keep their notes and promoted
rows narrow enough that named-filter existence is not mistaken for a
source-grep discipline proof.
Performance rows in the language-slice TSV have an additional guard: they must
cite the generated measurement scaffold, remain no-run, and carry blocked
local-performance, scaling, and claim-readiness statuses. A row that claims
paper-backed numbers or claimable local performance before the scaffold is
claimable fails the readiness check-plan. Scaling blockers must also keep
`multi_checkpoint_rollup_required` and a top-level `pass_contracts:blocked`
scaling blocker, and structured Pareas status fields such as
`pareas_claim_status=claimable` or `pareas_parity_claim_status=claimable` are
rejected while the scaffold remains not claimable.
Pass-order readiness is checked at the language-slice row level: the bounded
paper-derived row must point at the parallel pass-contract measurement
scaffold, WASM record lowering must carry behavior-facing artifact evidence,
and the planned GPU link/object pass-order and object-link-pipeline rows must
have no evidence fields until promoted with behavior, record, artifact,
execution, or measurement-scaffold evidence. Tests should not separately parse
the TSV notes column and assert prose fragments.
The no-run readiness gate also checks `docs/PAREAS_PASS_CONTRACT.md` for the
checked-in paper translation anchors, the local `~/code/pareas` comparison
section, the pass primitives that matter for this compiler shape
(`exclusive prefix sum`, `radix_sort`, `segmented_scan`, and `scatter`), the
shader-loop audit blocker command, the
`performance-scaling-or-pareas-parity-audit-debt` and
`zero-paper-pass-blocker-not-pass-contract-proof` claim-boundary markers, and
the no-local-performance-evidence measurement boundary. That check keeps the
Pareas comparison and paper-derived pass order attached to concrete documents
and behavior-facing pass concepts without treating exact Pareas source filenames
as readiness evidence.
The compact shader-loop summary must also carry the `evidence-policy` rows
`behavior-facing-pass-evidence`,
`rewrite-routes-not-source-grep-evidence`, and
`rust-product-source-inspection-not-pass-evidence`,
`audit-proof-is-pass-shape-only`,
`audit-blockers-and-local-review-are-not-performance-evidence`,
`audit-debt-blocks-performance-and-pareas-parity-claims`,
`zero-paper-pass-blocker-not-pass-contract-proof`,
`no-run-not-performance-evidence`, and
`no-run-not-pareas-claim-evidence`. Measurement plans must preserve those rows
before using audit counts as pass-contract evidence, so a clean route summary
cannot be mistaken for implementation-string coverage, local performance
evidence, or a Pareas comparison claim.
Generic-parameter validation and import-cycle validation tests belong in this
same discipline: assert accepted/rejected programs, diagnostics, records, or
artifact boundaries, not compiler source strings, helper names, or whether a
particular internal function was used.
For persisted artifacts such as lockfiles or descriptor JSON, parse the
artifact and assert semantic fields; do not search pretty-printed JSON strings
or materialized source text when ordering or formatting is not the contract.
The language-slice TSV uses `bounded` to mean exactly the evidence named in the
row, not general production support. If an evidence test only covers one slice
of a larger feature, write the note narrowly and add a separate `planned` row
for the missing production behavior.
The production-readiness matrix snapshot is cross-checked against the TSV at
both the global and area levels: package/import, parser-HIR, stdlib, and
linking row counts in `docs/PRODUCTION_READINESS.md` must match the computed
language-slice inventory. Updating the TSV without updating the blocker matrix
is therefore a readiness failure, not an acceptable stale summary.
The readiness gate also requires at least one public-boundary,
artifact-contract, record-invariant, semantic-contract, execution-contract,
fail-closed-diagnostic, and measurement-scaffold row, so the TSV cannot drift
into a single evidence style while still reporting success.
For externally usable language surfaces, the same gate now requires named
language-slice rows for the stable diagnostic code registry, diagnostic
registry/categories/explain/formats/formatter/command-discovery CLIs,
diagnostic-format routing on no-run diagnostics subcommands, formatter
idempotence plus `fmt --check` JSON diagnostics, LSP
capability/stdio/document-diagnostic paths, package manifest and lockfile CLI
compilation, package lock generation, and package metadata JSON diagnostics.
The compact diagnostic code-index gate compares `laniusc diagnostics codes`
against `laniusc diagnostics registry` at the public CLI boundary, so it catches
missing or phantom code rows without source inspection.
These are still behavior-facing inventory requirements; they do not inspect
compiler or shader source text. A required external diagnostics/tooling/package
row must also be present in the focused, smoke, or properties acceptance
inventory; an existing test function that is not scheduled as non-scale
readiness evidence no longer satisfies the row.
It also requires parser/typechecker relation evidence for array-literal local
context, struct-literal field-selection context, and generic enum-constructor
call context rows. Those rows must point at behavior tests that exercise
type-check outcomes and diagnostics, not compiler/shader source text, pass
names, or helper names.
The Pareas lane is provenance-only in this repo state. Its ignored gate checks
that the no-run measurement scaffold names local Pareas input/output/stdout and
compiler-hash artifacts; it must not run Lanius, run Pareas, or assert a
wall-time ratio. Ratios belong in `lanius.measurement-summary.v1` only after
fresh local artifacts, repeatability, source-control, pass-contract readiness,
and paper-pass alignment all become claimable.

`tools/shader_loop_audit.sh --summary-only` is the current no-run Slang loop
inventory for paper/Pareas alignment review; `--fail-on-paper-pass-blocker` and
`--fail-on-data-dependent` are blocker checks over that inventory. Use
`--fail-on-source-sized-symbolic-cap` when a lane needs to fail closed on
uppercase caps that look source, tree, record, or program-structure sized until
they are justified as bounded local work or rewritten. Treat these as audit
inputs for pass-contract classification, not as performance evidence and not as
a substitute for behavior, record, artifact, or diagnostic gates. The current
raw audit has zero paper-pass blockers, zero review-required rows, zero
source-sized symbolic-cap rows, and 50 bounded-local helper-review rows, so
guard-capped and fixed-bound loops remain visible without being counted as
claimable performance or Pareas-parity evidence.

The current `readiness` inventory expands to these non-scale evidence groups:

- **Focused:** crate compilation, diagnostic renderer shape, descriptor
  contract-file emission and descriptor validation, package-manifest and
  lockfile CLI guards, descriptor source-root/package rejection, formatter CLI
  behavior, language-edition CLI enforcement, version output, portable Cargo
  config, formatter idempotence, lockfile input-identity/import-graph/schema
  rejection, source-pack behavior, and source-pack work-queue reference-model
  transitions.
- **Smoke:** generated gate discovery, no-run measurement-plan write behavior,
  readiness inventory status, and the ignored x86 capacity-estimate test that
  computes compile allocation bounds without GPU submission.
- **Properties:** source-root and stdlib-root boundary diagnostics, package
  identity versus GPU module identity, literal-preserving formatting,
  source-pack target boundaries, small x86 execution/fail-closed boundaries including
  direct recursion and over-wide aggregate-copy rejection, generated x86
  name/shape independence, module visibility, parser-owned HIR record
  invariants, source-pack boundary separation, source-spanned type and syntax
  diagnostics including imported source-root files and direct source packs, GPU
  module/import diagnostics, stdlib runtime contracts, method/generic/enum
  semantic slices, and qualified trait-bound resolution by declaration identity.

Adding a production-readiness claim should usually add one named focused or
properties entry before adding any generated or Pareas gate. If the right
evidence is a measurement, add it to the no-run measurement scaffold first and
execute it only under the scale/performance lane.

## Scalable Compiler Contracts

For source-pack control-plane changes, prove these contracts with small fixtures:

- Files are partitioned into bounded library, frontend, codegen, and link jobs.
- Persisted pages retain bounded inline records and spill larger inputs to pages.
- Job dependency ranges resolve without materializing every source, artifact, or
  dependency.
- Work-queue readiness follows a simple reference model: a job becomes ready
  only after all dependencies complete, claims expire deterministically, and
  completion updates dependents exactly once.
- Reopening persisted state preserves counts, first-ready pointers, claims,
  dependency counters, and final output keys.

Preferred test shapes for this lane are model-based tests against a small
reference scheduler, round trips through persisted pages, and boundary cases at
page/range limits. Avoid asserting private helper names or the exact in-memory
layout unless that layout is the serialized contract.

For GPU data-plane changes, prove record invariants:

- Lexing produces token records.
- Parsing produces parse-tree and HIR records.
- Semantic passes consume HIR, resolver, type-instance, literal, and visibility
  records rather than source text or token spelling.
- Backend lowering consumes attributed HIR records only.
- Instruction counts are per node, instruction locations are prefix sums over
  those counts, and instruction generation writes virtual instruction records.
- Register allocation consumes virtual instruction and virtual register records.
- Byte emission consumes allocated instruction and relocation records.

Runtime assertions are part of this contract, not just local debugging aids.
Put assertions close to the record producer or consumer for impossible owner
ranges, unsorted keys, duplicate keys after sort/dedup, prefix-sum overflow,
out-of-bounds scatter destinations, invalid row tags, non-monotonic page ranges,
and resource limits. Tests should reach those assertions through public
compiler, record, artifact, or diagnostic boundaries. Do not add a test that
only checks whether an assertion string, helper name, pass name, or shader file
exists.

For linking, tests should make it hard to accidentally move massive work back to
the CPU:

- CPU tests may inspect descriptor pages, counts, ranges, and persisted paths.
- GPU or record-level tests should cover symbol table rows, section/object
  offsets, relocation records, emitted byte pages, and prefix-sum derived layout.
- CPU code must not concatenate, relocate, patch, or semantically rewrite object
  contents at scale.

For arbitrarily large source packs, tests should prefer counts, ranges, pages,
and job descriptors over materialized per-source or per-artifact vectors. A test
that requires thousands of records to prove this is usually testing capacity
instead of architecture; first write the small boundary case that would fail if a
range were expanded.

## Architecture Tests

Architecture tests are allowed, but they should be small and durable.

Good architecture tests:

- Check public record contracts, persisted schema boundaries, and banned classes.
- Assert that large inputs are represented by counts, ranges, pages, or records.
- For source-root/package loading, combine durable manifest/path assertions with
  parser/type-check behavior instead of asserting the exact materialized source
  strings inside a source pack.
- Exercise name/shape independence through compiled programs rather than
  scanning source files for forbidden vocabulary.
- Exercise performance-sensitive shader work through bounded generated programs,
  timeout behavior, and measurement runs rather than tests that grep shader
  source for specific loop spellings.
- Assert public behavior, emitted records/artifacts, diagnostics, lockfiles, or
  executed output. Do not read or inspect `src/compiler*`, Rust source files, or
  `shaders/*.slang` from a test to prove an implementation choice.
- For unsupported GPU paths, assert the externally visible fail-closed result:
  diagnostic code/category, no success artifact, no fallback support claim, and
  the relevant record/artifact boundary. Do not assert the private validator,
  shader helper, command string, or buffer name that produced the rejection.

Suspicious architecture tests:

- Depend on exact function order, exact formatting, or specific line placement.
- Assert helper names, private enum variants, private row builders, shader file
  names, buffer names, or source snippets when the durable contract is public
  behavior, a record invariant, a diagnostic, or a persisted artifact.
- Require editing after harmless module extraction.
- Mirror implementation details so closely that they would preserve the same
  bug.

Do not extend inherited marker-inventory architecture tests. When touching a
subsystem covered by a long list of exact helper names, either leave unrelated
markers alone or replace the touched expectation with a higher-signal contract:
a public API behavior, persisted schema round trip, record invariant, bounded
range/page assertion, or broad forbidden-class audit. A new exact marker is
acceptable only when that marker is itself a serialized format, public command,
public env var, or intentionally stable boundary.

## Generated Tests

Generated tests must be deterministic by default:

- Use fixed seeds and include the seed in failure output.
- Keep default case counts small.
- Bias generators toward meaningful compiler states: renamed identifiers,
  helper-like names, let-bound returns, nested blocks, if/else, calls, reused
  locals, equivalent rewrites, and boundary page sizes.
- Save or print a replayable minimized input when a generated case fails.

Generator design matters more than case count. Bias toward states that have
broken or could plausibly break the architecture: renamed stdlib-like
identifiers, helper-like names, equivalent expression rewrites, let-bound
returns, nested blocks, calls through locals, reused locals, multi-library
dependency boundaries, and page-size edges. Uniform random source generation is
not enough by itself.

Large generated tests are opt-in. `tests/generated_10k_gates.rs`, large size
sweeps, Pareas comparisons, and capacity stress tests should stay ignored or
environment-gated unless the task is explicitly about scale or performance.

For benchmark planning logic, prefer small CPU-only scaling properties before
running generated GPU workloads. For example, generated capacity snapshots can
check that token capacity, projected parser tree capacity, x86 instruction
capacity, and total allocation floor are monotonic across small fixed
checkpoints such as 64/128/256 lines. That catches broken planning math without
asserting source text or submitting GPU work.

Default generated cases should use 5k lines. A 10k generated case is an explicit
checkpoint, and a 20k generated case is a capacity checkpoint, not a normal
regression test. Anything above 5k must require
`LANIUS_ALLOW_LARGE_GENERATED_TESTS=1`, `--allow-large`, or an equally obvious
opt-in. The default measurement iteration count is one; more than three
iterations is measurement work and requires the same explicit opt-in.

Pareas comparison planning uses the measurement scaffold's checkpoint and
iteration fields. More iterations are a measurement choice, not a
regression-test default; use `LANIUS_PERF_ITERS` explicitly and keep claimable
metrics at or above the declared repeatability threshold without turning the
Pareas lane itself into an executable regression test.

## Test Selection By Change

- Pure helper, validator, or range function: run its focused unit test.
- Source-pack record/page schema: run the specific round-trip or validation test
  plus `cargo check --lib -j1`.
- Work queue, claims, or progress: run the focused model/state-machine test for
  the changed transition.
- GPU shader or pass binding: run the smallest GPU test for that pass and a
  record-invariant test if available.
- Backend lowering or register allocation: run a small record-level test before
  any executable-codegen test.
- Public CLI or artifact format: run one focused integration test at that public
  boundary.
- Broad serialization, public API, or cross-module refactor: run `cargo check
  --lib -j1` and only the focused tests that cover moved or changed boundaries.

## Failure Classification

Classify failures before editing:

- Real regression: fix product code.
- Correct new behavior, stale expectation: update the test to the new contract.
- Incidental implementation detail: delete or replace with a property check.
- Flake: make it deterministic or remove it from gating until it has signal.
- Unrelated failure: report it separately and do not reshape the current change
  around it.

Do not appease a bad test by making the compiler architecture worse.

## Reporting

Every verification summary should say:

- What behavior or state space was exercised.
- Why the selected tests were the right scope.
- Whether any failure was a regression, stale expectation, brittle test, flake,
  or unrelated failure.
- What meaningful gap remains.
