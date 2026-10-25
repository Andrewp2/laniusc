# Target capacity exposed by TLS record tests

Resolved on 2026-10-24 for native x86_64 Linux output from GPU compilation.
The original compiler accepted the ordinary TLS consumer and failed to compile
the larger protocol fixture. After a host capacity repair, the complete
unchanged fixture executes all 308 byte/state model commands. The original
failure evidence remains below.

## Observed failure

With `LANIUS_DEBUG_STAGE_ERRORS=1`, the exact failure gate reported:

```text
GPU lowering failed (flags=0x2, semantic row=4294967295,
OptIR row=4294967295, source HIR=4294967295,
target opcode=4294967295, required capacity=187055,
available capacity=135168, diagnostic reason=0,
diagnostic detail kind=0, diagnostic detail=4294967295)
```

The one-test invocation failed in 3.57 seconds. The earlier three-test
invocation took 5.98 seconds: the ordinary consumer passed and both protocol
groups failed to compile. Logs are retained locally in
`target/stdlib-work/tls-crypto-admission/tls-stage-error.log` and
`tls-record.log`.

Flag `0x2` denotes target-instruction capacity. These counts concern target
LIR rows, not records, input bytes, runtime stack size or GPU shader
instructions. The remaining locations are unset sentinels; this observation
does not identify an unsupported TLS operation or a source type error.
[x86 validation](../shaders/codegen/lir/x86/validate.slang#L26) compares the
measured target row total with the target arena and records the exact demand.
The public `LNC0057` erases the underlying phase detail unless the debug
environment variable is set.

## Failed sizing assumption

[LoweringCapacities::from_frontend_unit](../crates/laniusc-compiler/src/codegen/lowering_ir.rs#L1239)
originally claimed structural stream bounds and reserved eight target rows per
HIR row. The repaired source identifies output sizes as initial estimates.
The [x86 count pass](../shaders/codegen/lir/x86/count.slang#L310) instead expands
nonzero `[value; count]` aggregates to `1 + value_word_count` target rows.
A [local aggregate store](../shaders/codegen/lir/x86/count.slang#L267) can add a
full word copy, and a named aggregate copy also expands with its word count.
One repeat source expression can therefore require arbitrarily many target
rows without adding distinct source-tree element edges. The eight-per-HIR
claim does not bound this admitted source form.

The TLS fixture contains three nonzero 16,700-byte repeated arrays plus a
saved full-array copy. Their initialization/copy work is consistent with the
large target demand. No exact per-array attribution has been measured.

## Minimal reproduction and acceptance

[nonzero_array_repeat_target_capacity.lani](../tests/fixtures/stdlib_foundation/dependencies/nonzero_array_repeat_target_capacity.lani)
is self-contained: it imports no library module and uses no crypto or host
service. One 16,386-element nonzero array repeat is copied by value. Separate
source/copy mutations, both boundary cells and whole-array checksums make
incorrect initialization, aliasing or truncated copying observable. Correct
native execution returns zero.

The original compiler reproduced the capacity failure on this fixture:
`flags=0x2`, **49273 required target rows / 36864 available target rows**.
Semantic/OptIR/source/opcode locations were again unset, with reason zero and
no more specific diagnostic. The CLI was freshly built in 0.21 seconds. Root
then ran the following bounded command; its diagnostic is retained in
`target/stdlib-work/tls-crypto-admission/repeat-before.log`:

```bash
RUST_MIN_STACK=16777216 LANIUS_DEBUG_STAGE_ERRORS=1 \
timeout --kill-after=2s 100s \
  flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s \
  target/stdlib-build/debug/laniusc --emit x86_64 \
  tests/fixtures/stdlib_foundation/dependencies/nonzero_array_repeat_target_capacity.lani \
  -o target/stdlib-work/tls-crypto-admission/repeat-before.x86
```

The focused runtime regression in
[compiler_array_repeat_context_execution.rs](../tests/compiler_array_repeat_context_execution.rs)
uses the existing strict ELF writer and exit-status assertions. Its observable
checksums and guards are the acceptance contract; the incidental row counts
above record the original failure.

## Accepted repair

The repair is confined to host capacity orchestration. It uses measured target
and artifact output demand, preserves that requirement through per-job sizing
and reset checks, plans the replacement device graph before retiring the old
graph, and retries the complete compilation graph. Retries must increase
capacity monotonically and stop after at most three retries. Pure output
capacity failures are eligible; mixed or other failure domains retain their
errors. Numeric overflow and device planning/allocation failures remain
explicit. Semantic and side-table capacities are unchanged. No shader,
compiler IR record, ABI, formal proof, TLS production source or complete TLS
protocol fixture was changed for the accepted gates.

| Accepted gate | Result |
| --- | --- |
| `array_repeat_and_value_copy_grow_target_capacity_from_measured_demand` | Passed in 3.56 s; large and subsequent tiny native programs execute using the same compiler |
| Three `codegen::lowering_pipeline::tests` output policy tests | Passed in 0.00 s; target growth survives job clamping, ordinary small jobs remain small, artifact demand is typed, overflow/other failure domains reject |
| `lowering_output_retry_requires_progress_and_stops_at_its_bound` | Passed in 0.00 s; monotonic progress and retry bound |
| Complete TLS record driver | Three tests passed in 11.28 s: ordinary consumer, 96 failure/preflight commands and 212 size/type/state commands |

The native joint build took 38.82 seconds and freshly linked
`compiler_array_repeat_context_execution-c136bf8d4ce9f2f0` and
`extended_tls_record_execution-ece0ab2532f0d157` under
`target/stdlib-build/debug/deps/`. The fresh compiler unit-test build took
52.61 seconds and produced `laniusc_compiler-ed923a7149a8a821` in the same
directory. Local logs under `target/stdlib-work/tls-crypto-admission/` are
`build-capacity-native.log`, `repeat-after.log`, `build-capacity-unit.log`,
`capacity-policy-tests.log`, `capacity-retry-tests.log`, and
`tls-record-after-capacity.log`. The [TLS guide](extended-tls-record.md#admission)
records the exact accepted driver command and its two strict ELFs, three native
processes and empty allocation traces.

### Exact focused commands

The fresh builds used this environment:

```bash
export CARGO_TARGET_DIR=/home/andrew-peterson/code/laniusc/target/stdlib-build
export CARGO_INCREMENTAL=0
export CARGO_PROFILE_DEV_DEBUG=0
export CARGO_PROFILE_TEST_DEBUG=0
```

Compiler unit-test build:

```bash
timeout --kill-after=2s 100s \
  flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s \
  cargo test -p laniusc-compiler --lib --no-run \
  > target/stdlib-work/tls-crypto-admission/build-capacity-unit.log 2>&1
```

Joint native driver build:

```bash
timeout --kill-after=2s 110s \
  flock -E 75 -w 15 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 90s \
  cargo test --test compiler_array_repeat_context_execution \
  --test extended_tls_record_execution --no-run \
  > target/stdlib-work/tls-crypto-admission/build-capacity-native.log 2>&1
```

The four host policy tests require no GPU execution:

```bash
timeout --kill-after=2s 30s \
  target/stdlib-build/debug/deps/laniusc_compiler-ed923a7149a8a821 \
  output_demand --nocapture --test-threads=1 \
  > target/stdlib-work/tls-crypto-admission/capacity-policy-tests.log 2>&1

timeout --kill-after=2s 30s \
  target/stdlib-build/debug/deps/laniusc_compiler-ed923a7149a8a821 \
  lowering_output_retry_requires_progress_and_stops_at_its_bound \
  --nocapture --test-threads=1 \
  > target/stdlib-work/tls-crypto-admission/capacity-retry-tests.log 2>&1
```

The minimal native regression uses the standard serialized GPU command:

```bash
RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
LANIUS_DEBUG_STAGE_ERRORS=1 timeout --kill-after=2s 100s \
  flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s \
  target/stdlib-build/debug/deps/compiler_array_repeat_context_execution-c136bf8d4ce9f2f0 \
  --exact array_repeat_and_value_copy_grow_target_capacity_from_measured_demand \
  --nocapture --test-threads=1 \
  > target/stdlib-work/tls-crypto-admission/repeat-after.log 2>&1
```

### Performance scope

The [performance record](library-foundation-performance.md#authenticated-bytes-key-exchange-and-tls-records)
compares the same combined crypto/record consumer and existing 1 MB workload
before and after this host repair. Both binaries use one pinned shader set;
the run order is before/after/after/before, with six measured samples per
variant/workload. All 32 emitted programs passed, and no slowdown was observed.
Overlapping ranges and uncontrolled desktop conditions prevent a causal
speedup or cross-compiler ratio claim. The correctness and policy gates do not
establish constant-time crypto, full TLS support, GPU kernel execution or other
native targets.
