# Cooperatively locked file patch fixture

This fixture reuses only the independent byte/file setup from the unlocked
test oracle. Its own runner checks flock acquisition and cleanup around every
positional read/compare/write. The production library is not imported into
the Python model.

| Group | Cases | Coverage |
| --- | ---: | --- |
| model | 15 | Binary ranges, 1025/4096-byte staging, uppercase hex, leading-zero offsets, >4 GiB sparse patch, unchanged replacement, mismatch/EOF cleanup, literal four-operand path named --lock and seeded byte cases |
| bounds | 15 | Leading-only option grammar, no -l alias, duplicate/misplaced flags, argument counts and complete path/offset/hex validation before open or lock |
| faults | 15 | Acquisition EINTR/EAGAIN/ENOLCK without retry, unlock errors, primary/secondary diagnostic order, confirmed partial write, close/open/read failures, positional retries while held and two CLI allocation denials |
| protection | 4 | Host shared/exclusive holders exclude all payload I/O; two separate-process syscall-barrier protocols protect small and 4096-byte patches |

Each ordinary trace requires acquisition before payload reads, complete reads
before writes, one explicit unlock after acknowledged acquisition, and one
close afterward. Failed acquisition skips all payload I/O and unlock. Phase,
unlock and close diagnostics must follow cleanup in that order. Invalid local
inputs make no open/lock call. The two CLI snapshot mappings are the only
allocations; successful observed mappings require matching explicit releases.
Failed writes retain the confirmed prefix, never a fictitious rollback.

The protection helper uses Linux x86_64
[ptrace syscall stops](https://man7.org/linux/man-pages/man2/ptrace.2.html)
using Linux 5.3+ syscall information, without changing registers, results or
file bytes. At every native pread/pwrite
entry, an independent host open attempts a nonblocking exclusive
[flock](https://man7.org/linux/man-pages/man2/flock.2.html), which must fail.
The helper also reads the current file to check the exact previously confirmed
write prefix. At the native unlock-success stop, that host open must acquire
the lock before the native close. These are deterministic process barriers;
there are no timing sleeps. A 15-second alarm and ptrace EXITKILL bound the
protocol. No successful native byte transfer is fabricated.

Injected unlock/close errors skip those actual kernel calls. Such cases check
attempts, error precedence and eventual process exit, not that the injected
cleanup action executed. Finite local-host observations do not establish
distributed-filesystem semantics, lock authority over noncooperating writers,
pathname replacement protection, atomicity, durability, lifetime or leak proofs.

```sh
python3 -B tests/fixtures/stdlib_execution/locked_file_patch/oracle.py controls
python3 -B tests/fixtures/stdlib_execution/locked_file_patch/oracle.py model PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/locked_file_patch/oracle.py bounds PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/locked_file_patch/oracle.py faults PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/locked_file_patch/oracle.py protection PATH_TO_ELF
```

Each ordinary child and syscall protocol has a 15-second deadline; each
registered group has an 85-second deadline. Commands, bytes, stdout, stderr,
status and strace/ptrace evidence are retained. The existing unlocked oracle
changes only its exact help expectation, corresponding length control and
trace selection to observe unexpected flock calls.

## Acceptance

All four groups passed: **49 native Linux x86_64 cases** using the same
application, oracle and protection helper across two receipts. The driver
used the GPU compiler and shared strict ELF checker before CPU execution.

- Model 15 passed in 7.73 seconds; the other three tests were filtered.
  Receipt: `target/stdlib-work/file-lock-app-model-first.log`.
- Bounds 15, faults 15 and protection 4 passed in 7.62 seconds; the model
  test was filtered. Receipt:
  `target/stdlib-work/file-lock-app-boundaries.log`.

Evidence directories:

- Model: `/tmp/locked-file-patch-model-qhtvtmvs`.
- Bounds: `/tmp/locked-file-patch-bounds-qrrrrt84`.
- Faults: `/tmp/locked-file-patch-faults-nrqc6k4w`.
- Protection: `/tmp/locked-file-patch-protection-oztdgsqn`.

Executed application SHA-256:
`b2a6984c1bf73d0092327286bf858725ee729dcb4a51f1b13876160fa9ad7528`.
Oracle SHA-256:
`1a55a38db71cfe5aa957df496ae2acd111f1b64844f18ffc8ed0a9fbe1a3ab57`.
Protection helper SHA-256:
`702ccdb2ec67dc9f4381a760b953c5c23fc2d380798a5e19c5d3e1f034316ab8`.
Baseline test-oracle dependency SHA-256:
`412368ccc6b4c2cfc87bd642071c06d0af68dbe112f98dc03c487b31da99b6d5`.
Preformat executed driver SHA-256:
`37e1ae0b39081cb13cf1eed879ce376bd3811d0b2944eb9fd8ca98a2cb4775ec`.
This is the historical runtime identity before final whitespace formatting.

The 15 fault processes reached 18 injected errors, including two CLI
allocation failures and compound write/unlock/close failures. All observed
successful mappings matched explicit releases. Shared and exclusive host
holders each prevented every positional read/write. The three-byte ptrace
protocol observed two blocked host-lock probes; the 4096-byte protocol
observed eight. Both independently acquired the host lock at the successful
unlock stop before the application closed its descriptor. The helper was
unchanged between admission and these accepted runs.

Two pure CPU controls also passed. These finite local-filesystem observations
do not establish protection from noncooperating writers or pathname
replacement, cross-filesystem semantics, atomicity, durability, leak freedom,
device execution, formal verification or exhaustive fault coverage.
