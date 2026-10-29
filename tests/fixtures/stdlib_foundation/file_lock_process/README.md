# Process-level advisory lock contracts

`peer.lani` calls the public `std::file_ops::lock` and `unlock` functions on
actual File owners. The Rust driver uses independent host `flock` calls and
separate opens as controls. These are finite native Linux x86_64 tests on the
local filesystem, using executable output produced by the GPU compiler.

## Protocol and scope

The peer sends its native PID, descriptor and `R` readiness byte. One-byte pipe
commands request shared/exclusive nonblocking locks, a blocking exclusive lock,
unlock, duplication, individual closes or exit. Every operation has an explicit
acknowledgement. A blocking request first sends `A`; the host then observes
`/proc/PID/syscall` reporting syscall 73 on that descriptor with operation 2
(`LOCK_EX`). Only after that pending-call observation does the controlling
process release the conflicting lock. The peer sends `K` after acquisition.

Four tests cover six native peer lifecycles:

- Independent shared holders coexist; an exclusive nonblocking request returns
  WouldBlock while a conflicting holder remains. Exclusive ownership excludes
  both shared and exclusive independent contenders.
- A blocked exclusive acquisition wakes after an explicit host unlock.
- Closing the original owner leaves its duplicate's lock active; closing the
  last duplicate wakes an already blocked second native process.
- Actual process exit releases the description and wakes a blocked contender.
  This branch deliberately performs no explicit File close. It tests kernel
  process-exit scope and does not imply an automatic Lanius destructor.

Each scenario checks unchanged file bytes, native shared cursor 37 and host
cursor 19. Trace checks require the selected flock/close counts and no heap
mapping, release, remapping, `brk`, `fsync` or `fdatasync` calls. The ordinary
cleanup paths close each actual owner once; repeated logical closes issue no
extra host close. No failed-conversion retention assumption is used.

Pipe readiness/acknowledgement, pending-syscall observation and exit waits have
five-second deadlines and use no sleeps. The tracer uses `--kill-on-exit`.
Cleanup stays armed through successful status, bounded pipe EOF checks and final
trace validation; any failure kills and reaps the private process group. These
checks require readable descendant `/proc/PID/syscall` and a strace version
supporting that option.

## Accepted execution

All four registered tests passed on the identities below:

| Receipt under `target/stdlib-work/` | Result | Reported test duration |
| --- | --- | --- |
| `file-lock-process-blocking.log` | blocking-unlock test passed; three filtered | 5.97 s |
| `file-lock-process-lifetime.log` | remaining three passed; blocking-unlock filtered | 5.37 s |

All three blocking scenarios recorded
`pending_syscall=73 operation=LOCK_EX observed_before_release`. These durations
include fixture admission and instrumented process work; they are not lock
latency measurements. The evidence does not cover device execution, other
mount/filesystem locking semantics, deadlines in the public blocking API or
formal verification.

Accepted SHA-256 identities (driver before later formatting-only changes):

| Source | SHA-256 |
| --- | --- |
| `peer.lani` | `5b20e19d1e28af3832346a6d63d0d6edf14d3578aae2b9164c66b5efed472f7b` |
| `tests/stdlib_file_lock_process_execution.rs` | `2a12f1a4c2d205fbf96f68fb37447ec52286131f1de5dea90bccccb4185c9e11` |

Reproduce the same split selectors from the repository root, serializing GPU
compiler use and bounding each command below two minutes:

```sh
timeout --kill-after=2s 100s flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  env CARGO_TARGET_DIR=target/stdlib-build cargo test \
  --test stdlib_file_lock_process_execution \
  blocking_process_lock_is_pending_until_explicit_host_unlock \
  -- --exact --test-threads=1 --nocapture
timeout --kill-after=2s 100s flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  env CARGO_TARGET_DIR=target/stdlib-build cargo test \
  --test stdlib_file_lock_process_execution \
  -- --skip blocking_process_lock_is_pending_until_explicit_host_unlock \
  --test-threads=1 --nocapture
```
