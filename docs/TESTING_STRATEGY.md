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
5. Small architecture tripwires that deny forbidden classes of implementation:
   source-byte reads after lexeme extraction, token-spelling checks in late
   passes, helper-name matching, body-shape recognizers, CPU semantic rewrites,
   and unbounded shader loops.
6. Ignored or explicit opt-in scale/performance gates only when measuring
   capacity, latency, VRAM, or comparison against Pareas.

Escalate one rung at a time. If a focused test gives the required evidence, stop.

## Default Lanes

Most changes should use one of these lanes instead of inventing a broad run:

- **Focused compile:** `cargo check --lib -j1`
- **Focused unit/model test:** `cargo test -p laniusc <module>::<test_name> -j1 --lib -- --test-threads=1`
- **Focused integration test:** `cargo test --test <file> <test_name> -j1 -- --test-threads=1`
- **Architecture tripwire:** `cargo test --test architecture_contract <test_name> -j1 -- --test-threads=1`
- **Shader loop budget:** `cargo test --test shader_loop_budgets <test_name> -j1 -- --test-threads=1`
- **Formatting check:** `rustfmt --edition 2024 --check <touched Rust files>`
- **Diff hygiene:** `git diff --check -- <touched files>`

`tools/compiler_acceptance.sh` is dry-run by default and prints the explicit
commands it would run. Use `tools/compiler_acceptance.sh --tier focused --run`
for the small CPU-only checkpoint. Use `--tier generated`, `--tier properties`,
or `--tier pareas` only when the changed surface needs that evidence.
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

Do not append to `TEST_RUN_LOG.md`; it is historical only. Summarize current
verification in the final response or in the relevant PR/change note.

## Lane Boundaries

Keep the lane boundary explicit:

- **CPU/model lane:** bounded schedulers, range math, manifest/page schemas,
  work-queue progress, command-line guards, and architecture string audits. This
  is the default lane for compiler control-plane work.
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
- Deny source text, token spelling, helper names, function-body recognizers, and
  CPU data-plane fallbacks in the wrong stage.
- Track shader loop budgets as CPU-only tripwires when the contract is "do not
  add an unbounded or data-sized loop here."

Suspicious architecture tests:

- Depend on exact function order, exact formatting, or specific line placement.
- Require editing after harmless module extraction.
- Mirror implementation details so closely that they would preserve the same
  bug.

When a string audit is necessary, use broad markers for forbidden behavior and
read the smallest relevant file or module.

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
