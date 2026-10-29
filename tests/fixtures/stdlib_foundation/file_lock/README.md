# Native advisory file-lock contracts

Both registered gates are accepted through separate runs described below.
These fixtures target Linux x86_64 CPU executables produced by the GPU
compiler, with no claim about device execution or other filesystems.

`contracts.lani` opens the same seeded file through independent descriptions
and checks shared/exclusive compatibility, repeat acquisition followed by one
unlock, uncontended conversions in both directions, and unlock without a held
lock. A duplicate-description sequence checks shared lock state, unlock through
an alias, conversion through an alias, survival after one close, and release
after the final duplicate closes. Closed logical owners reject all four
acquisition mode/wait combinations and unlock without another syscall.

The driver checks a 39-call lock table against actual syscall number 73,
descriptor identities, exact Linux flags and success/WouldBlock results.
Only the fixture's explicit position/status observations and live-owner closes
are permitted. File bytes and length must match the independently seeded host
file, and the host `flock` command must acquire an exclusive nonblocking lock
after cleanup.

`fault.lani` selects one lock or unlock operation. Unlock first acquires an
acknowledged exclusive lock. The driver runs two ordinary controls and fourteen
single-result injections: EINTR, EAGAIN, EBADF, ENOLCK, EIO, positive one and
positive 2^32 for each selected phase. Every injection must be reached exactly
once, with no retry or hidden unlock. The owner remains logically open with the
same raw descriptor, cursor and status flags after the result, then closes
once. Closed-owner rechecks produce no lock calls. Host bytes and post-close
release are checked separately for every schedule.

Both gates reject observed allocation services and synchronization calls.
The contracts do not assert lock retention after failed conversion, automatic
cleanup, crash durability, pathname protection or protection from writers that
ignore advisory locks. Blocking calls here are compatible/uncontended; true
separate-process blocking and contention belong to the other locking fixtures.

## Executed receipts

- **Native semantics passed** in
  `target/stdlib-work/file-lock-native-first.log`. This accepted the one
  contract process, including the 39-call table and independent host byte and
  post-close lock checks. The whole command took 6.86 seconds and reported one
  passed test and one failed fault test; 6.86 seconds is not an isolated
  semantics timing or a receipt that both gates passed together.
- **Native faults passed** in
  `target/stdlib-work/file-lock-native-fault-final.log`: one registered test in
  5.45 seconds, all 16 schedules (14 injected and two ordinary controls). Both
  positive-2^32 cases require the actual syscall-73 trace result to remain
  `4294967296` and the Lanius report to be `InvalidCount`.

The first fault run stopped at a harness stderr assertion: `strace` warned
that the injected 2^32 return would be clipped in a compatibility personality,
while the actual x86_64 trace retained all 64 bits and the fixture reported
`InvalidCount`. The driver now permits only that exact warning for those two
precise injections; all other stderr remains rejected. No production or Lanius
fixture change was needed. The semantics gate was not rerun for this driver
correction.

Retained SHA-256 identities:

| Source | Hash |
| --- | --- |
| `contracts.lani` | `0a921787777d7923e328e2085ee5d6b9622812d71e695c18a82d25edb1ac9352` |
| `fault.lani` | `fad16704481f851562bf042d62ca27bac615e0da357cabef8e3cbdce30c1d1bc` |
| Initial driver, semantics receipt | `8f212ac1a0c5f3f0f11a608f62bb72551360cf53c7555ea878a833dc19f1568a` |
| Final driver, fault receipt | `cc9cb10a6d005f2e8e70ca5d4f2c71554b6f3b86e51adcf5b7a5cf33f5c4793c` |
| `stdlib/std/file_ops.lani` | `9ca5ca58e09b39342c6409bded385b18e08d7488de233d32a87fe82826cf9f8a` |

Focused selectors:

```text
cargo test --test stdlib_file_lock_execution file_locks_obey_independent_open_compatibility_and_duplicate_lifetime -- --exact
cargo test --test stdlib_file_lock_execution file_lock_and_unlock_faults_are_single_attempts_and_preserve_live_owners -- --exact
```
