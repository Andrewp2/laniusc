# Runtime formatting to byte writers

`core::format::write` renders the existing runtime format grammar through a
borrowed `core::io::Write` implementation, using caller-provided byte scratch.
It does not allocate a complete output buffer. The pattern, argument types,
precision rules and Unicode scalar alignment are those of
[runtime format strings](stdlib-format-strings.md).

Accepted on **2026-10-24** for x86_64 Linux native execution of ELFs built by
the GPU compiler. This does not establish execution in user GPU kernels or on
other targets. No compiler, runtime, shader, IR, ABI or proof source changed.

## API

```lani
pub struct WriteLimits {
    format: core::format::Limits,
    max_io_calls: u64
}
pub enum WriteError {
    Format(core::format::Error),
    Io(core::io::Error),
    IoLimit
}
pub struct WriteFailure { cause: WriteError, completed: i32 }

core::format::write<W>(
    pattern: core::text::Text,
    positional: core::slice::View<core::format::Argument>,
    named: core::slice::View<core::format::Named>,
    writer: &W,
    scratch: core::slice::View<u8>,
    limits: WriteLimits
) -> core::result::Result<i32, WriteFailure>
    where W: core::io::Write
```

All source views, writer state and scratch must remain live throughout the
call. The writer stays borrowed; no owner or descriptor is transferred.

## Validation and publication

Scratch must have positive length, nonnegative start and a nonoverflowing
logical end. Invalid scratch returns `Format(Bounds)` with `completed=0`,
before inspecting the format. As with other views, physical backing is a
caller precondition. A logical overclaim can trap when accessed.

The formatter then validates the complete pattern, argument names and selected
value controls and measures the complete output. Format, type, name, work and
output-limit failures make no writer call and leave scratch unchanged. This
includes errors appearing after valid fields and literal prefixes.

Preflight uses the existing format limits and error priority. Each render must
fit `floor(limits.format.max_work / 2)`, reserving preflight and deterministic
commit work. The output byte limit applies to the complete formatted result,
independently of scratch capacity. There is no new pattern grammar or truncated
successful result when a limit is exceeded.

After preflight, one commit render fills scratch and drains complete chunks;
the final partial chunk is drained at the end. Output can be much larger than
scratch. Positive scratch of one byte is valid, including for multibyte UTF-8
text and fill scalars. Individual writes can split a UTF-8 encoding; the stream
interface transfers bytes. The complete successful output remains the same
valid UTF-8 as the existing formatter.

Successful formatting returns the full accepted byte count. Empty valid output
returns zero without calling the writer, even when `max_io_calls` is zero.
Scratch contents after commit begins are temporary implementation storage and
are not a returned owned result.

## Short writes, failures and limits

`max_io_calls` counts direct calls to the supplied writer's `write` method.
Every attempt consumes one unit before the call, including attempts returning
Interrupted or another error. The limit is checked before each attempt;
exhaustion returns `IoLimit` without another call. A persistent Interrupted
writer therefore terminates when its explicit call allowance is exhausted.

| Writer outcome | Formatter behavior |
| --- | --- |
| Positive count within the request | Advance the scratch offset and confirmed byte count |
| Interrupted | Retry the same remaining bytes if the call budget permits |
| Zero progress | Return `Io(WriteZero)` |
| Negative count or count beyond the request | Return `Io(InvalidCount)` |
| Other error, including WouldBlock | Return that `Io` error immediately |

`WriteFailure.completed` is the prefix confirmed accepted by earlier valid
positive returns, including a prefix of the current chunk. An error, zero or
invalid count does not add unconfirmed progress. An invalid-count writer has
violated the underlying protocol; the formatter cannot infer its actual
effects from that return value.

The first failure stops rendering and draining. The formatter does not flush
the remaining scratch suffix after failure. Already accepted output cannot be
rolled back. A new call starts the format again; the API does not silently
resume or retry an already published prefix.

The call allowance does not bound the internal work, blocking time or nested
I/O performed inside an arbitrary writer method. Logical format work,
direct call attempts and elapsed time have separate meanings.

## Buffered writers and lifetimes

With [`alloc::buffered::Writer`](stdlib-buffered.md), accepted bytes can still
be pending in library-owned buffers. Both successful counts and failure
progress describe acceptance by that immediate writer. They do not certify
delivery through every nested layer, flushing, durability or descriptor close.
The caller separately finishes, retries, recovers pending parts or discards
that buffered owner under its own contract.

This function calls neither `flush` nor `close`, including for empty output or
errors. Host signal policy also remains the caller's responsibility; native
programs requiring cleanup after a closed stdout pipe select
[BrokenPipe Ignore](stdlib-signals.md) before publication.

Pattern bytes, argument records, names and selected Text storage must remain
immutable across both passes and all writer callbacks. They may overlap one
another as read-only sources. Scratch must be disjoint from those sources and
from writer-owned storage or mutable state. The writer must not retain scratch
references after its method returns. These are manual lifetime and alias
contracts; the language does not enforce them.

Scratch accesses and writer requests retain the native byte-slice descriptor,
including nonzero starts and strided stack storage. Existing descriptor
adapters perform their own packed staging at the Linux host boundary.

## Existing formatting interfaces

`format_into` retains complete-output buffer atomicity, and
`format_into_staged` retains its explicit alias-staging policy. `measure`
retains its logical work/output contract. Owned byte/String formatting still
uses those APIs and its existing allocation/cleanup policy.

Custom `Display<T>` remains the caller-backed `core::fmt` protocol. Runtime
writer formatting consumes the existing typed `Argument`/`Named` lists;
general Display-to-owned formatting has a separately recorded
[compiler dependency](library-dependencies.md).

## Verification

The accepted source base was `0b03990bfd7b658f0c419cf4ec2c32477ccb186e` plus
this writer implementation. Focused Rust drivers compile Lanius fixtures,
check the emitted executable, then execute native behavior; these are not
type-check-only gates. Rust supplies independent expected bytes and progress
models, not the library implementation.

| Gate | Accepted evidence | Elapsed |
| --- | --- | ---: |
| Plain consumer | Ordinary SliceWriter call with no caller projection of the new error types; exact bytes and sentinels | 5.73 s |
| Byte/chunk model | 960 commands, 36 grammar cases, scratch sizes 1/2/7/64, packed and strided storage, short writes, interruptions and budgets | 7.68 s |
| Nested buffers | Two layouts; exact leaf/inner/outer pending partitions, explicit finish only, exact four allocation generations | 6.61 s |
| Scripted failures | 40 modeled cases; exact prefixes, requests, calls, errors and budgets, including persistent interruption | 6.74 s |
| Preflight | 22 rejection cases; no writer calls or source/scratch mutation, exact-limit controls | Included below |
| Bounded abort | Maximum i32 padding width stops after zero or one accepted byte; two-second native timeout | Included below |
| Buffered allocation and finish faults | Baseline, reached constructor ENOMEM, and unreached denial control; retry preserves ownership and frees once | Included below |
| Writer bound rejection | A read-only type with matching inherent methods still fails the Write trait requirement with LNC0008 | Included below |
| Existing buffer-format contract | Existing atomicity, grammar, bounds and limits fixture | 6.22 s |
| Existing owned formatting and Display | Adjacent owned-output and user Display fixture | 6.63 s |
| Real CSV report | 81 native cases, including 23 reached allocation denials and exact 65,536-byte boundary | 9.19 s |
| One MiB output | Three native runs, 256-byte scratch, exact FNV-1a hash, 4,096 writes, no flush or allocation | 7.42 s |

The four preflight/abort/ownership/trait gates passed in a 15.16 s driver run.
That initial run also contained one **fixture compilation failure**, so it was
not an all-green suite: a nested wildcard match hit the already recorded
[compiler boundary](library-dependencies.md). Extracting a typed error-matching
helper in the fixture preserved every observation; the corrected scripted
gate then passed separately. Production code did not change for this issue.

The first byte-model comparison also exposed an oracle spelling difference:
Rust prints the alternate uppercase hexadecimal prefix as `0x`; Lanius's
documented grammar uses `0X`. The oracle now adapts that prefix while retaining
Rust's independent digit formatting. The original driver and both failed
attempt logs remain in the ignored local admission directory.

New fixture and driver sources are in
[`format_write`](../tests/fixtures/stdlib_foundation/format_write/),
[`format_write_failures`](../tests/fixtures/stdlib_foundation/format_write_failures/),
[`stdlib_format_write_execution.rs`](../tests/stdlib_format_write_execution.rs)
and [`stdlib_format_write_failures.rs`](../tests/stdlib_format_write_failures.rs).
The real program and its complete input, publication and cleanup contract are
documented in [the CSV report guide](stdlib-format-report.md).

Fresh driver builds took 1.31 s for execution, 1.18 s for failures and 1.21 s
for the report; rebuilding execution after adding the scale case took 1.35 s.
Every GPU gate was serialized with the library lock. For example, the scale
gate ran from the repository root as:

```sh
RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
  timeout --kill-after=2s 100s \
  flock -E75 -w35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s \
  target/stdlib-build/debug/deps/stdlib_format_write_execution-8c4a939deb3ea382 \
  single_mib_field_streams_in_constant_space_with_exact_hash_and_call_count \
  --exact --nocapture --test-threads=1
```

Logs are retained locally under the ignored
`target/stdlib-work/format-write-admission/` directory: `plain.log`,
`models.log`, `nested.log`, `failures-nested-match.log`, `scripted.log`,
`existing-contracts.log`, `existing-owned.log`, `report.log` and `scale.log`.
Driver hashes in the example command are build-specific.

The one-MiB native runs observed 237.216, 233.654 and 226.862 ms wall time.
These include process startup and FNV-1a hashing; the first also includes
strace. They are correctness/scale observations, not isolated formatter
throughput. The existing compiler performance harness comparison is recorded
in [foundation performance](library-foundation-performance.md#streaming-runtime-formatting).
