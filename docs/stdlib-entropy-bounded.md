# Bounded nonblocking OS entropy

`std::entropy` adds an allocation-free, nonblocking Linux entropy API with
a caller-owned limit on syscall attempts. It uses the existing executable
`std::linux::call`/`syscall6` boundary, without a compiler, runtime or ABI
change. The existing `fill`, `OsRandom`, `secure_u64` and `seeded` contracts
remain as documented in [Randomness](stdlib-randomness.md#os-entropy): those
functions use flags zero and can wait for initialization.

```lanius
pub enum Error { Bounds, Host(i32), NoProgress, InvalidCount, CallLimit }
pub struct Failure { cause: Error, completed: i32 }
pub struct Budget { remaining_calls: u64 }
budget(calls: u64) -> Budget
Budget.borrow(&self) -> &Budget
Budget.remaining(&self) -> u64
read_some(calls: &Budget, bytes: [u8], offset: i32, count: i32)
    -> Result<i32, Error>
fill_bounded(calls: &Budget, bytes: [u8], offset: i32, count: i32)
    -> Result<i32, Failure>
```

Every new syscall is x86_64 Linux `getrandom` number 318, with flags exactly
`GRND_NONBLOCK` (1), using at most 256 bytes of packed stack staging. The
flag returns `EAGAIN` when initialization would require waiting. Linux's
[getrandom contract](https://man7.org/linux/man-pages/man2/getrandom.2.html)
also requires checking errors and returned counts. The
[kernel flags header](https://github.com/torvalds/linux/blob/master/include/uapi/linux/random.h)
defines the nonblocking flag, and the
[x86_64 syscall table](https://github.com/torvalds/linux/blob/master/arch/x86/entry/syscalls/syscall_64.tbl)
defines number 318. No insecure flag, fallback bytes or file descriptor is used.

## Single attempt and exact fill

`read_some` validates the full signed offset/count before truncating its
host request to 256. Negative metadata or an overflowing sum returns
`Bounds` without spending budget or accessing the host. A logically valid
zero count returns `Ok(0)`, even when the budget is exhausted; it does not
read or modify the budget or destination. An empty range at `i32::MAX`
is valid. Physical backing is required for every nonempty requested range,
including the destination's actual stride.

A nonempty call with no allowance returns `CallLimit`. Otherwise it spends
exactly one attempt immediately before the syscall. Errors, interruptions,
zero results and impossible counts all consume that attempt. It does not
retry `EINTR` or any other host result. On valid positive progress it copies
only that many staged bytes into the destination and returns the count.

`fill_bounded` has the same initial metadata and empty-range rules, then
uses `read_some` repeatedly through the same borrowed budget. Positive
short progress advances the copied prefix. Only `Host(4)` (`EINTR`)
retries; a subsequent exhausted check returns `CallLimit`. `Host(11)`
(`EAGAIN`) and all other errors return immediately. It returns `Ok(count)`
only after copying the exact requested count. On failure,
`Failure.completed` is the number of bytes already copied by this fill,
and bytes outside that completed prefix remain unchanged.

| Error | Meaning |
| --- | --- |
| `Bounds` | Negative offset/count or a sum above `i32::MAX`; no attempt consumed |
| `Host(errno)` | The positive raw Linux error number, including `EINTR`, `EAGAIN` and `ENOSYS` |
| `NoProgress` | A nonempty request returned zero; no staged bytes copied |
| `InvalidCount` | A returned count is negative outside the kernel errno interval, exceeds the requested chunk, or an internal syscall-packing invariant fails |
| `CallLimit` | A further nonempty attempt would exceed the shared allowance |

Host counts are checked as `i64` before narrowing to `i32` or copying.
The destination sees no bytes from a failed or invalid staging result,
even if the host changed its staging buffer before reporting an error.
This `Error` and `Failure` belong to `std::entropy`; the existing
`core::random` error and failure enums are unchanged.

## Sharing and limits

Keep one `Budget` value and pass its borrowed reference across operations
to enforce one shared allowance. `remaining()` reports the unused count.
The module only decrements it and never replenishes it after errors or
successful reads. Copying a `Budget` forks the counter into an independent
allowance; it does not share accounting with the original. Directly
rewriting its manual fields likewise changes the caller's allowance.

The destination must not alias the budget, and callers must not concurrently
mutate the counter or destination during an operation. This is a synchronous
API without atomic cross-thread accounting. The syscall-attempt limit and
256-byte staging bound constrain library work. They do not promise a wall
clock deadline: scheduling, syscall execution and tracing can still delay
completion. No blocking flags are exposed by the new API, and no deadline
claim is made for the older flags-zero API.

Neither API retains a destination slice. The physical pointer, backing size,
stride and lifetime remain manual caller preconditions; the API can check
logical metadata only. A copied prefix is OS-provided data after a real
successful syscall, rather than a fallback success fabricated on failure.

## Focused verification

All four focused groups are accepted on **x86_64 Linux native executables
generated by the GPU compiler**, with strict ELF checks and no allocation
events. Acceptance spans three invocations with two test-harness corrections;
there was no single full-suite invocation in which all four groups passed.

`tests/stdlib_entropy_bounded_execution.rs` defines four focused native gates:

| Exact test | Contract explored |
| --- | --- |
| `bounded_entropy_actual_host_bytes_layouts_and_chunks` | Real bytes compared with `strace -xx`, native-strided and packed layouts, nonzero offsets, 256-byte chunking and shared partial exhaustion |
| `bounded_entropy_metadata_zero_and_shared_budget_priority` | Bounds before empty/exhaustion, empty ranges with exhausted allowance, independent metadata and shared-budget effects |
| `bounded_entropy_injected_errors_short_reads_and_prefixes` | Single-attempt interruption, bounded interruption retries, EAGAIN, host failure, zero/impossible counts, partial progress and untouched suffixes |
| `bounded_entropy_ordinary_consumer_without_error_projection` | Ordinary 257-byte fill plus 17-byte read, exhaustion and empty behavior without projecting the new error types |

### Admission history

All logs below are in the ignored local directory
`target/stdlib-work/tls-auth-admission/`.

| Invocation log | Observed result | Elapsed |
| --- | --- | ---: |
| `entropy-bounded-all.log` | Metadata/zero/shared-budget group passed; the other three stopped in the Rust trace parser after native processes exited successfully | 5.83 s |
| `entropy-bounded-trace-corrected.log` | With the metadata group skipped, actual-host and ordinary groups passed; injected group stopped on strace diagnostic stderr despite an already-correct `InvalidCount` response | 6.53 s |
| `entropy-bounded-injections-corrected.log` | Exact injected-errors group passed after the narrowly scoped warning correction | 5.42 s |

The first correction handles strace's padding before its result column:
the parser splits at ` = `, trims trailing padding and then removes the
closing parenthesis. The second accepts only empty stderr or the exact line
`strace: Injected return value 4294967296 will be clipped to 0 in compat personality`
for the explicit `retval=4294967296` injection. All other stderr still fails.
The test separately asserts that the native trace contains the full return
value 4294967296, then checks `InvalidCount` (protocol code 3), zero completed
bytes, remaining allowance and the unchanged destination. The independent
host probe in `entropy-host-wide-return-probe.log` also observed 4294967296.
No compiler defect was demonstrated; compiler and runtime were untouched.

Production code, fixtures and expected prefix/count assertions were unchanged
throughout these corrections. Rust driver builds took 1.36 s initially,
1.31 s after the parser correction and 1.55 s after the warning correction,
recorded in `build-entropy-bounded.log`, `build-entropy-trace-fix.log` and
`build-entropy-warning-fix.log`. The local driver basename was
`stdlib_entropy_bounded_execution-5a9e01bd64cb6efb` in
`target/stdlib-build/debug/deps/`; a fresh build can produce another basename.
These timings include orchestration and compilation rather than isolated
entropy throughput.

The reusable protocol ELF reports the result, remaining allowance and every
destination byte after each operation. Its independent Rust boundary model
consumes the traced syscall events, checks each requested size and flag,
and derives expected counters, completed prefixes and full destination
snapshots. Every trace rejects `mmap`, `mremap`, `munmap` and `brk` calls.
Each native process has a 15-second test-harness bound. Rust provides only
test orchestration and a boundary model, not a production entropy backend.

Injected short successes are explicitly synthetic. The tests use
`strace`'s documented [return-value and memory-poke injection](https://man7.org/linux/man-pages/man1/strace.1.html)
to skip the real syscall, report five bytes and write the fixed byte sequence
`01 23 45 67 89` into staging. That data establishes partial-copy and budget
behavior; it is not evidence of real entropy or its statistical quality.
Error/zero/impossible-count injections also modify staging in selected cases
to check that rejected staging never reaches the destination. Real host
bytes are compared exactly with their traced bytes; tests do not use
randomness-quality heuristics such as requiring two draws to differ.

Admission is limited to the enumerated cases on x86_64 Linux. GPU execution
here refers to the compiler; other target architectures and user GPU kernels
remain unverified. No entropy-quality certification, boot-time initialization
experiment or clock deadline follows from these tests. The manual physical
backing and shared-budget lifetime/concurrency contracts remain applicable.
