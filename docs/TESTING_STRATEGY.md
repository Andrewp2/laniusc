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
  function. Stale or deleted filters do not count as readiness evidence. The
  discipline policy rejects compiler/shader source greps as evidence, and the
  gate audits Rust integration tests for direct compiler/shader product-source
  reads or `rg`/`grep` probes.
  Parser/type handoff rows that downstream passes are expected to consume, such
  as parser-published method owners, must remain behavior-facing record or
  semantic contracts in the language-slice inventory. Parser-owned
  method-signature status flags currently have a planned inventory hook; promote
  that hook only when a parser HIR record gate, semantic gate, or stable
  diagnostic gate proves the handoff without compiler or shader source greps.
  The same check requires performance rows in the language-slice inventory to
  stay `measurement-scaffold`/`no-run` evidence with
  `local_performance_claim_status=blocked`, `scaling_claim_status=blocked`, and
  `claim_readiness_status=not-claimable` until local artifacts and pass
  contracts actually become claimable. Diagnostic registry, categories,
  explain, and formats rows are required as no-run CLI public-boundary or
  artifact-contract gates, including the unknown-code explain path.
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
  These are no-run checks for the 5k/10k/20k inventory, command timeouts,
  source seeds, artifact paths, VRAM/readback fields, and Pareas placeholders.
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
audits Rust integration tests so they do not read or grep compiler/shader
product source text for implementation strings. Source fixtures,
behavior-test names, expected diagnostics, record rows, descriptor artifacts,
and no-run tool metadata remain valid evidence when the assertion is about the
external contract rather than the implementation text that produced it. The
`readiness` tier intentionally rejects `--run`; execute `focused`, `properties`,
or `smoke` separately when a real test run is needed.
Use `tools/compiler_acceptance.sh --tier generated --check-env` before an
intentional generated, VRAM/perf, or Pareas run to validate `cargo`, `slangc`,
generated gate environment values, the canonical 5k/10k/20k measurement
inventory, `nvidia-smi` availability policy, and optional Pareas configuration
without compiling or executing any test binary. The check-env output includes
machine-readable per-checkpoint artifact and status-field notes so missing
Lanius, Pareas, VRAM, or readback evidence is visible before a run starts.
`nvidia-smi` and Pareas are optional by default; set
`LANIUS_REQUIRE_NVIDIA_SMI=1` or `LANIUS_REQUIRE_PAREAS=1` when a measurement
run must include those comparisons.
Use `tools/compiler_acceptance.sh --measurement-plan` to print the no-run
performance/VRAM/readback report scaffold, or
`tools/compiler_acceptance.sh --write-measurement-plan target/lanius-measurements/plan.txt`
to write it. The scaffold records the release benchmark build command and, for
the explicit 5k/10k/20k checkpoints, the intended Lanius benchmark command,
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
`paper_numbers_accepted=false`,
`comparison_baseline_policy=local-pareas-artifacts-only`, and
`freshness_policy=hash-and-checkpoint-field-match`,
`measurement_timing_policy=compile-latency-claims-use-benchmark-best-ms-wall-time-is-provenance`,
`cold_start_policy=excluded-from-claimable-compile-latency-captured-as-wrapper-wall-time`,
`compile_latency_claim_source=benchmark-stdout-best-ms-local-run-only`,
`runtime_validation_policy=validate-output-only-not-runtime-performance-claim`,
`claim_provenance_schema=lanius.measurement-claim-provenance.v1`,
`baseline_separation_schema=lanius.measurement-baseline-separation.v1`,
`paper_baseline_policy=reference-only-not-local-performance-evidence`,
`paper_baseline_numbers_status=reference-only-not-ingested`,
`local_evidence_status_policy=claimable-only-from-fresh-local-artifacts`,
`local_performance_claim_policy=blocked-until-pass-contracts-claimable-and-local-artifacts-complete`,
`local_performance_claim_source=benchmark-stdout-best-ms-plus-local-artifact-freshness`,
`local_performance_claim_status=blocked`,
`local_performance_claim_blockers=pass_contracts:blocked:...`,
`local_vram_claim_source=nvidia-smi-local-csv-plus-status-artifact`,
`local_pareas_claim_source=local-pareas-source-output-stdout-compiler-hash`,
`scaling_claim_policy=no-scaling-claims-while-pass-contracts-or-paper-alignment-blocked`,
`scaling_claim_source=multi-checkpoint-local-artifacts-plus-claimable-parallel-pass-contracts-and-paper-order`,
`scaling_claim_status=blocked`,
`scaling_claim_blockers=pass_contracts:blocked:...,paper_pass_alignment:blocked:...,multi_checkpoint_rollup_required`,
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
the generated Pareas source hash and Pareas compiler binary hash, the `lanius.measurement-evidence-freshness.v1`
freshness fields, and the required checkpoint artifact inventory.
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
The runtime surface in this scaffold is validation only:
`runtime_validation_policy=validate-output-only-not-runtime-performance-claim`.
Do not publish runtime-performance claims from these artifacts without a
separate runtime benchmark artifact and local provenance.
The claim-provenance fields are required on both the command-environment
artifact and the per-checkpoint summary. Paper baselines can be cited only as
reference context; they are never accepted as local performance, VRAM, scaling,
or Pareas comparison evidence.
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
Lanius, readback, VRAM, Pareas, responsiveness, resource-usage,
source-control, and freshness checks are all complete and the checkpoint used
at least the declared
`minimum_iterations_for_claim`. It also remains blocked while
`local_performance_claim_status` is not `claimable`, while
`pass_contract_readiness_status` is not `claimable`, or while
`scaling_claim_status` is not `claimable`. That lets the scaffold record local
artifact evidence without turning paper baselines, bounded loops, fail-closed
fallbacks, or a single checkpoint into performance/scaling claims. The same row
must also publish
`claim_readiness_required_evidence_classes` and
`claim_readiness_required_statuses`, including the requirement that
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
separately from planned pass-order gaps such as WASM record lowering and GPU
link/object emission. Moving a planned pass-order gap to bounded requires a
behavior, record, artifact, or measurement-scaffold contract that proves the
ordered GPU record boundary, not a source grep or private pass-name list.
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
provenance cannot satisfy the artifact inventory. The manifest itself has a
versioned
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
`LANIUS_PERF_CHECKPOINT_LINES=5000,10000,20000`, `LANIUS_PERF_LINES=5000`,
`LANIUS_PERF_SEED=3235798765`, `LANIUS_PERF_ITERS=1`,
`LANIUS_PERF_COMMAND_TIMEOUT_MS=120000`,
`LANIUS_X86_READBACK_TIMEOUT_MS=60000`,
`LANIUS_VRAM_SAMPLE_INTERVAL_MS=250`, and
`LANIUS_RESPONSIVENESS_PROBE_TIMEOUT_MS=2000` by default. Checkpoints above 20k
lines or more than three measured iterations require
`LANIUS_ALLOW_LARGE_GENERATED_TESTS=1`. Checkpoint values are parsed as decimal
line counts, emitted with canonical labels and artifact paths, and must be
strictly ascending so saved measurement artifacts have a reproducible order.
`LANIUS_PERF_LINES` must also match one of the planned checkpoint line counts,
so the primary artifact paths cannot point at a workload that the no-run plan
does not execute.
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
pass-contract loop/fallback status blockers, so
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
integration tests for product-source reads or `rg`/`grep` probes against
`src/` and `shaders/`; ordinary readiness evidence must still come from
behavior, artifacts, diagnostics, or record rows rather than source-text
matches.
Performance rows in the language-slice TSV have an additional guard: they must
cite the generated measurement scaffold, remain no-run, and carry blocked
local-performance, scaling, and claim-readiness statuses. A row that claims
paper-backed numbers or claimable local performance before the scaffold is
claimable fails the readiness check-plan.
Pass-order readiness is checked at the language-slice row level: the bounded
paper-derived row must point at the parallel pass-contract measurement
scaffold, and the WASM and GPU link/object rows must remain planned gaps until
they have behavior, record, artifact, or measurement-scaffold evidence. Tests
should not separately parse the TSV notes column and assert prose fragments.
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
The readiness gate also requires at least one public-boundary,
artifact-contract, record-invariant, semantic-contract, execution-contract,
fail-closed-diagnostic, and measurement-scaffold row, so the TSV cannot drift
into a single evidence style while still reporting success.
For externally usable language surfaces, the same gate now requires named
language-slice rows for the stable diagnostic code registry, diagnostic
registry/categories/explain/formats CLIs, formatter idempotence plus
`fmt --check` JSON diagnostics, LSP
capability/stdio/document-diagnostic paths, package manifest and lockfile CLI
compilation, package lock generation, and package metadata JSON diagnostics.
These are still behavior-facing inventory requirements; they do not inspect
compiler or shader source text.
It also requires parser/typechecker relation evidence for array-literal local
context, struct-literal field-selection context, and generic enum-constructor
call context rows. Those rows must point at behavior tests that exercise
type-check outcomes and diagnostics, not compiler/shader source text, pass
names, or helper names.
The ignored Pareas comparison is not a performance assertion while
`pass_contract_readiness_status=blocked`; it may only assert a wall-time ratio
after pass contracts are reclassified as unbounded, fallback-free, and
claimable.

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
  source-pack WASM calls, small x86 execution/fail-closed boundaries including
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
  executed output. Do not read or grep `src/compiler*`, Rust source files, or
  `shaders/*.slang` from a test to prove an implementation choice.

Suspicious architecture tests:

- Depend on exact function order, exact formatting, or specific line placement.
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
regression test. Anything above 20k must require
`LANIUS_ALLOW_LARGE_GENERATED_TESTS=1`, `--allow-large`, or an equally obvious
opt-in.

Pareas comparisons default to one measured iteration. More iterations are a
measurement choice, not a regression-test default; use `LANIUS_PAREAS_COMPARE_ITERS`
explicitly and keep it at or below three unless also opting into large generated
gates.

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
