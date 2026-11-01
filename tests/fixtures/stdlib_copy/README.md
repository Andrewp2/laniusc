# Resumable copy contracts and schedule model

The authoritative behavior is
[`docs/library-stream-encoding-plan.md`](../../../docs/library-stream-encoding-plan.md).
These fixtures exercise the public `core::io::Copier` through its actual
`Read` and `Write` providers. Production remains Lanius.

## Registered gates

`tests/stdlib_copy_execution.rs` registers five groups:

- `resumable_copy_generic_read_write_execute_tiny_admission`: distinct
  Read-only and Write-only providers, a generic bounded helper, original
  scratch offsets, partial delivery, zero-read-quota draining, and observed
  then cached EOF. Construction and queries must leave providers untouched.
- `resumable_copy_progress_errors_budgets_and_abort_execute`: an exact
  12-attempt read/write transcript, interruption charging, both WouldBlock
  directions, short writes, WriteZero recovery, all eight ordinary terminal
  error variants from both provider directions, and explicit abort suffix
  recovery. Reaching the input length does not infer EOF. Provider
  `Err(InvalidCount)` remains resumable.
- `resumable_copy_metadata_faults_counter_headroom_and_strides_execute`:
  seven invalid constructor ranges reject without access; a valid logical
  endpoint near i32::MAX is used only with zero work. Four malformed success
  counts from each direction fault after prior confirmed progress, preserve
  tracked state, and suppress further provider calls. Consistent seeded
  counters near u64::MAX test clipping and stop precedence; only two actual
  bytes are transferred. Both actual negative native strides and positive
  packed strides preserve all source bytes and outside destination/scratch
  guards.
- `resumable_copy_requires_independent_read_and_write_capabilities`: two
  source-local LNC0008 rejections at the marked constructor calls. The tiny
  admission supplies executing positive controls for independent traits.
- `resumable_copy_matches_independent_fifo_payload_and_provider_schedule_model`:
  36 named schedules across two layouts, totaling 72 cases and 348 actions.
  A separate Python reference maintains a FIFO of pending bytes and a
  committed-output ledger. Every action compares result/error provenance,
  cumulative counters, direct attempts, active/EOF/fault state, pending
  location and actual pending-view bytes, full source/output/scratch storage,
  and every ordered provider
  request including original offsets, stride and write payload. Conservation
  and immutable guards are checked independently. Twelve deliberately altered
  observations must be rejected by the comparator, including corruption of a
  byte read through the actual pending view.

The finite corpus covers repeated one-call steps; input quotas with no EOF
probe; pending output with zero input budget; alternating direction-specific
blocking; interrupted attempts at both ends; ordinary errors and malformed
successes; abort and inactive precedence; and near-MAX arithmetic. It uses no
random seed or unbounded fuzzing. Seeded counters are arithmetic witnesses,
not claims of having transferred enormous inputs.

## Execution and target scope

All positive fixtures must pass strict Linux x86_64 ELF admission and the
shared in-function jump validator. The three pure fixtures execute under a
15-second child timeout with a full syscall trace containing exactly one
successful exec and exit, no other host effects, and empty stdout/stderr.

The model compiles once and uses a bounded binary stdin/stdout batch protocol
only for test transport. Its native child timeout is 30 seconds, within the
driver's 60-second host timeout. The protocol records observations; it is not
a library transport or a substitute implementation. Native compiler/test
commands run serially by root under the library lock and a 100-second outer
bound. This test owner runs only bounded host reference controls.

Acceptance is finite Linux x86_64 CPU execution through the GPU compiler, not
user-program GPU execution, formal verification, or support for other targets.
Provider-internal blocking/work is outside the direct-call budget. Physical
backing, endpoint/scratch disjointness, stable lifetime, no reentry and one
active state remain caller obligations. Malformed providers have unknowable
physical effects; these tests establish tracked progress and suppression of
further attempts, not safe replay of a faulty transfer.

Live allocated-owner evidence and JSON encoder/application composition have
separate drivers and receipts. No tests/common or compiler changes belong to
this fixture set.

## Receipts

- Initial tiny admission did not execute: 0/1 in 2.38 seconds, with LNC0005
  from an unqualified production enum variant; recorded in
  `target/stdlib-work/stream-encoding-copy-admission.log`.
- After the production owner qualified the variants, tiny admission passed
  1/1 in 5.45 seconds (separate Rust build 0.19 seconds), including the full
  pure syscall trace. Log:
  `target/stdlib-work/stream-encoding-copy-admission-qualified.log`.
- First remaining direct run: 1 passed, 2 failed in 4.69 seconds. The capability
  group passed; contracts and preflight failed compilation with LNC0006
  because their shared log parameter expected i64 while slice_stride returns
  isize. No runtime claim follows for those two fixtures from this run.
  Log: `target/stdlib-work/stream-encoding-copy-direct.log`.
- With the explicit signed-width logging cast, the corrected contracts and
  preflight fixtures passed 2/2 in 6.60 seconds (separate Rust build 1.68
  seconds), including both full pure syscall traces. Log:
  `target/stdlib-work/stream-encoding-copy-direct-revised.log`. This accepts
  all four direct/capability groups across the three runs.
- Independent direct source review passed. Two independent reviews also
  accepted the revised model's actual pending-view observation, complete
  byte/state/event comparison and finite corpus.
- Host-only reference check passed:
  `timeout 20s python3 -B tests/fixtures/stdlib_copy/oracle.py --self-test`.
  Exact result: `copy-model CPU cases=72 actions=348 layouts=2 corruption-controls=12`.
- The native model passed 1/1 in 6.62 seconds (separate Rust build 0.19
  seconds), with the exact expected summary:
  `copy-model cases=72 actions=348 layouts=2 corruption-controls=12`.
  Log: `target/stdlib-work/stream-encoding-copy-model.log`.
- All five registered groups are accepted: four execute native programs
  (three pure contracts and the independent model), and one checks the two
  capability rejections. Acceptance uses the frozen sources below; no source
  change or test rerun followed these receipts.

## Frozen sources

| Source | SHA-256 |
| --- | --- |
| `tests/stdlib_copy_execution.rs` | `c1b37de4b1d50a2f300595a2e33f0fc7e36e9500dd75a6605d758ca17437c6be` |
| `admission.lani` | `7ff5c06141e84bf92cc79b95f5da07417a956a5095e13c958e5e2356b736b522` |
| `contracts.lani` | `6df419678f9a68ac93c245ee8199dfa3227325397297b71b2e7b5f0874ff2012` |
| `preflight.lani` | `2b1abb2d928b836c15f4d10d4b085372dddefce3f78cb5c53371ef4574c514eb` |
| `negative_read.lani` | `55c1a223d89a74b7c92e1a521c2c55dbe0fd1f5c7583ecccd74659f4bc6a7e30` |
| `negative_write.lani` | `6bf6f1e9d849f964494a5954418b1188fde1f240da9fbf92eaf529ca9c17c3bd` |
| `model.lani` | `547a1e1cef9b00f7d32171acc96fba51f82867223bd15a89ca0532d8bd561cea` |
| `oracle.py` | `d81d1dada809a9e42be7077ca44135b15696485176fdbe50405d6d1c9ebe87dc` |
