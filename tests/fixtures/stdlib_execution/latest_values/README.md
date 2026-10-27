# Latest-values real application checks

Status: all four direct model, bounds, reached-OOM and I/O campaigns pass on
native Linux x86_64. These direct oracle receipts are separate from
Rust-libtest execution.
The real [Lanius app](../../../../sample_programs/library/latest_values.lani)
uses canonical `TreeMap<String,String>` replacement and the shared
`try_replace_up_to`, with a bounded existing TrySink history collector.
Its [guide](../../../../docs/stdlib-latest-values.md) owns strict TSV/UTF-8,
output and resource contracts.

Root serializes compilation/native commands. The focused filters are:

```sh
timeout --kill-after=2s 100s cargo test --test stdlib_latest_values_execution latest_values_matches_independent_displaced_history_and_sorted_snapshot_models -- --exact --nocapture
timeout --kill-after=2s 100s cargo test --test stdlib_latest_values_execution latest_values_strict_tsv_utf8_limits_and_committed_history_failure_are_explicit -- --exact --nocapture
timeout --kill-after=2s 100s cargo test --test stdlib_latest_values_execution latest_values_reached_ooms_preserve_distinct_precommit_and_history_failure_owners -- --exact --nocapture
timeout --kill-after=2s 100s cargo test --test stdlib_latest_values_execution latest_values_io_failures_release_owners_and_report_actual_output_prefixes -- --exact --nocapture
```

Each oracle has a 70-second bound; each traced native child has five seconds.
A retained executable may be reused without recompilation:

```sh
timeout --kill-after=2s 70s python3 -B tests/fixtures/stdlib_execution/latest_values/oracle.py models /ABSOLUTE/COMPILED/ELF
```

Groups: `models`, `bounds`, `allocations`, `faults`. Models use eight authored
and 128 seeded cases (`0x48837130`), an independent strict byte/UTF-8 parser,
and dictionary histories of complete old keys/values plus a sorted snapshot.
Bounds cover all eight options, empty values, byte caps, malformed UTF-8/
records, exact/over history quotas and a causal postcommit delivery failure.

The causal case has independently owned old/new/pending values of 89/127/61
bytes. With history cap zero, it requires commit 2, displacement 1, remainder
1, complete old value and still-stored current new value in one actual-write
backed stderr record. Each unique source allocation binds by ordinal to one
original full-trace mmap with the exact instruction address, arguments and
result. It must precede the first actual positive diagnostic write and remain
live through the complete record, then be explicitly released. A text record
alone is not the owner-lifetime evidence.

OOM enumeration derives every actual source allocation ordinal from a passing
baseline. Exact instruction/request/prefix binding and reached ENOMEM are
mandatory. The baseline releases a unique 4,091-byte input owner before map/
history growth, then reserves a unique 4,093-byte output stage. Reached OOMs in
that interval distinguish precommit replacement failure from Undelivered
history failure; the latter's complete old/current fields and progress match
the independent update model. Output reservation denial is separate. No
historical allocation floor or guessed node layout determines coverage.

Faults include real closed-reader data/help EPIPE, EINTR and finite call caps,
invalid counts, actual 1,024-byte output prefixes, and diagnostic failure which
preserves the history-limit status and releases every owner. An injected
second-stdout EIO must bind a successful same-input baseline's exact IP, fd 1
and request; a failed stderr write cannot satisfy it.

The accepted flatten-sum oracle's exit-boundary resource functions and unchanged
raw-ELF allocator verifier are imported read-only. No scanner/ledger is forked.
Require full-width addresses, requested lengths, source instruction provenance,
no named fallback, exact releases and no source mapping remaining before the
traced exit syscall. This app has no ACK or live `/proc` barrier. Direct
replacement-owner fixtures' live checkpoints retain their separate scope.

## Initial composition admission

App source SHA-256:
`62fce749565c273421c242a9c79e4de366c29824f588d89004521ce08f7b6225`.
`replacement-latest-values-expression-arms.log` records successful corrected
compilation; `replacement-latest-values-admission-native-first.log` records two
direct native cases (normal four-row history/snapshot and quota-zero committed
replacement with one unconsumed row). ELF SHA-256:
`e5d70d1ec6118929526ab5c6a09e01127c9ee5f75689489c6b587710210b55e5`.
Logs are under `target/stdlib-work/`. This is Linux x86_64 CPU output of the GPU
compiler, not user GPU-kernel support. The two admission cases overlap the
later campaigns and are not added to their counts.

## Current direct oracle receipts

The retained ELF above passed these separate direct Python groups. No passing
four-libtest Rust invocation is claimed.

The registered app and ownership Rust drivers build together in 3.42 seconds
with `--no-run` (`replacement-app-owner-driver-build-first.log`). The app test
binary is `stdlib_latest_values_execution-63722699a9352599`; no libtest
execution is inferred from this build receipt.

| Group | Process invocations | Log under `target/stdlib-work/` |
| --- | --- | --- |
| Models | 136 (eight authored, 128 seeded) | `replacement-latest-values-models-first.log` |
| Bounds | 61 | `replacement-latest-values-bounds-live-order-retry.log` |
| Allocations | 34 (baseline plus all 33 reached source ENOMEM positions) | `replacement-latest-values-allocations-first.log` |
| Faults | 17 | `replacement-latest-values-faults-first.log` |

Total: 248 process group cases across separate invocations, with overlapping
baselines and behavior. The earlier 61-case bounds invocation is repeated
coverage and is not added again.

Independent review found that the original bounds witness checked release
after the record but omitted allocation before it. An owner allocated after
the record could therefore satisfy that original check. Oracle SHA-256
`2806ad3ac0b9bcc8b50e21854e71b2514f3d6bd6b9369c31bc22bf8be6c9caf3`
adds the exact original-event binding and both lifetime boundaries described
above. Only `bounds` uses the changed witness; its narrow native rerun passes
all 61 cases against the unchanged retained ELF. The earlier, weaker check is
recorded in `replacement-latest-values-bounds-first.log`. The other three
groups' paths and the app/ELF are unchanged. Process counts are not independent
properties or cumulative executions across retries.

The first draft failed before ELF emission because match arms contained block
expressions (`replacement-latest-values-admission-first.log`). Equivalent
helper-expression arms corrected application syntax without changing ownership
semantics or the compiler. No native failure is inferred from that attempt.

## One larger native observation

The same accepted ELF processes 4,096 input rows, 512 distinct keys, 3,584
displaced-history entries and 512 final snapshot entries. Exact byte counts
are 49,152 input and 65,536 output. One untraced process wall time is
0.087919031 seconds, including launch, stdin, validation, String allocation,
map replacement, history, staging and stdout capture. Exact expected output
was prepared before timing and checked after it.

Arguments: `--rows 4096 --history 4096 --input-bytes 2097152 --output-bytes
4194304`. Receipt: `target/stdlib-work/replacement-latest-values-scale-first.log`;
evidence: `/tmp/latest-values-scale-o1plx38m`. This single observation measures
no source allocation or RSS count, establishes no compiler benchmark or
general speed ratio, and adds no case to the 248-case campaign count.

CPU-only controls:

```sh
timeout --kill-after=2s 100s python3 -B tests/fixtures/stdlib_execution/latest_values/oracle.py controls
```

Current result: 26 controls pass, including strict grammar, update histories,
causal-record framing, injection reachability, synthetic-write rejection and
parsed trace controls rejecting premature release, allocation during/after
the diagnostic and allocation-ordinal identity mismatch. Only the new dedicated Rust driver
was formatted with `skip_children=true`; the fixture author runs no Cargo/GPU/
native program. The full library goal remains open.
