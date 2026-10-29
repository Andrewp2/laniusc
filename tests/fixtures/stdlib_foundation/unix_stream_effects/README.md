# Unix stream effects and fault contracts

These three fixtures complement the direct API and independent named-peer
gates. They test observable validation, descriptor authority and selected host
failures on native Linux x86_64 output from the GPU compiler.

## Selected behavior

`bounds.lani` rejects negative/overflowing View metadata on null and real
backing, oversized names before backing access, and empty pathname names.
A pathname constructed successfully is then mutated to contain NUL; bind and
connect must revalidate it. Malformed transfer/until requests, valid empty
transfers, generic I/O range errors and other selected local rejections make
no host call inside the `P/p` phase. Real output sentinels remain unchanged.
Closing retires its single acquired descriptor once; closed wrappers reject
I/O, cloning and flush without another host call.

`lifecycle.lani` acquires a real pair and one cloned descriptor. Transfer and
adoption preserve authority without acquisition or close. Cloned descriptors
share nonblocking status, while the other pair endpoint remains independent.
The clone still receives real bytes after the original descriptor closes.
A transferred clone is adopted again, half-close produces real peer EOF, and
exactly three acquired descriptors receive three actual close calls.

`fault.lani` executes **63 schedules: 13 genuine kernel baselines and 50
individually reached injections**. Operations are stream/pair creation, clone,
connect, bind, listen, empty accept, send, receive, close, flag query, shutdown
and readiness. The table covers selected Interrupted/WouldBlock/Host errors,
malformed counts and full-width `4294967296` results. Every direct operation
has its expected single attempt; no automatic EINTR retry is allowed here.

Receive errors and rejected counts leave the first destination untouched.
Because injection skipped the kernel receive, a separate explicit later call
recovers the real queued bytes into another buffer. This is not an invented
successful transfer count. Likewise, fabricated descriptor/status results do
not enter the acquired-descriptor ledger. A skipped socketpair call returning
invented zero must reject its untouched `[-1,-1]` output.

The three injected close cases retire the logical wrapper before one attempt
and never retry it. Since injection skipped the kernel call, each leaves one
actual descriptor until process exit. The ledger counts those residuals
explicitly; they are not reported as successful kernel closes. Other actual
acquisitions/releases match by descriptor. Genuine bind creates a socket path
that remains after close; injected skipped binds create none.

All traces use a closed syscall allowlist and permit no library heap services.
Creation/accept flags and MSG_NOSIGNAL are observed directly. These finite
cases do not establish every backpressure/deadline schedule, other platforms,
GPU device execution or formal lifetime/memory correctness.

## Receipts and harness corrections

Receipts are under `target/stdlib-work/`:

| Log | Observed result |
| --- | --- |
| `unix-stream-effects-first.log` | bounds and lifecycle passed; fault gate stopped on tool stderr. Mixed run: 13.15 s. |
| `unix-stream-effects-fault-final.log` | fault-only run stopped on hexadecimal F_GETFL trace parsing: 7.91 s. |
| `unix-stream-effects-fault-accepted.log` | fault gate passed all 63 schedules; two other tests filtered: 8.40 s. |

Both corrections were in the Rust harness; all Lanius fixtures remained
unchanged. Only the exact known strace compat-personality warning is accepted,
and only for the scheduled `retval=4294967296` injection. The strict x86_64 ELF
check remains, and every such case requires the actual injected trace return
to equal all 64 bits of `4294967296`, plus native InvalidCount code 2.
Hexadecimal F_GETFL output such as `0x100000000` is parsed numerically alongside
decimal output. Unrelated or additional stderr still fails. Reported durations
include fixture compilation/admission and instrumented process work.

Accepted source identities (final fault driver before later formatting):

| Source | SHA-256 |
| --- | --- |
| `stdlib/std/socket.lani` | `44f6739da9be0aa5d28c97dee2c905bca157e237df91c34a0ee6790909c06ccb` |
| `bounds.lani` | `cd6bfb88b310aa005bf925bfa8eb5e86d228b27f81e4d6a3e37c19d6757ee55d` |
| `lifecycle.lani` | `015c1583fb6b27fb326536379d21cb27d6029f0531fbddaef7274efd25936df2` |
| `fault.lani` | `84941ae6063923217c8457775fe1d13492d0e8e44fed68405068f05af0a34e4e` |
| `tests/stdlib_unix_stream_effects_execution.rs` | `db4c6af705a891db48b51a1a44f47368aa28b481cd0fb7e20df3dc1604d07a18` |

Reproduce from the repository root, serializing compiler access and bounding
each command below two minutes:

```sh
timeout --kill-after=2s 100s flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  env CARGO_TARGET_DIR=target/stdlib-build cargo test \
  --test stdlib_unix_stream_effects_execution \
  -- --skip unix_selected_faults_preserve_bytes_full_width_guards_and_single_attempt_ownership \
  --test-threads=1 --nocapture
timeout --kill-after=2s 100s flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  env CARGO_TARGET_DIR=target/stdlib-build cargo test \
  --test stdlib_unix_stream_effects_execution \
  unix_selected_faults_preserve_bytes_full_width_guards_and_single_attempt_ownership \
  -- --exact --test-threads=1 --nocapture
```
