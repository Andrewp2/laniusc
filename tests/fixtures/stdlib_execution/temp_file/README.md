# Temporary-file ownership and anchored filesystem tests

All five native oracle groups passed against the frozen Linux x86-64
executables below. Production operations run in Lanius; Python arranges and
inspects the filesystem, validates reports and accounts for native resources.
See the [module guide](../../../../docs/stdlib-temp-files.md) for the
public API and ownership rules.

## Accepted receipts

Root ran each oracle group separately and inspected the filesystem,
descriptor, source-allocation, phase and reached-injection assertions.
Receipts are under `target/stdlib-work/`.

| Group | Process cases | Accepted finite scope | Receipt |
| --- | ---: | --- | --- |
| `owner` | 8 | Binary cleanup, keep, repeated explicit file close, renamed/replaced parent anchor, already-absent name, active-create rejection, 33,798-byte kept binary file and empty kept file. | `temp-file-owner-group-first.log` |
| `collisions` | 6 | Existing regular-file and symlink collisions, bounded collision exhaustion, excluded equality before open, excluded exhaustion and shared entropy-budget exhaustion after a collision. | `temp-file-collisions-first.log` |
| `validation` | 18 | Four invalid limits, nine invalid excluded components/views, two valid long/non-UTF-8 exclusions and three invalid parent descriptors: regular, closed and `O_PATH`. | `temp-file-validation-first.log` |
| `faults` | 19 | Two successful baselines; the one reached 37-byte source allocation with ENOMEM; duplicate, metadata, status and create EIO; seven bounded entropy cases; failed unlink followed by retry or keep; cleanup file/anchor close EIO and explicit file-close EIO. | `temp-file-faults-first.log` |
| `primitives` | 27 | Replace/NoReplace, relative/nested/raw/absolute byte paths, symlink leaves, missing/directory errors, oversized-path rejection, one-attempt injected errors/invalid counts and the logical-bounds probe. | `file-at-primitives-group-first.log` |

The five groups total **78 process case invocations**. They include overlapping
coverage: the fault group's successful cleanup and explicit-close baselines
also occur in `owner`. This total is not a count of distinct behaviors or an
exhaustive test claim. The fault campaign derives its source-allocation count
from its successful cleanup baseline; the accepted build reached one source
allocation, so `cases = 18 + 1`. It does not cover every allocation path in the
library or compiler.

Accepted executables:

- `target/stdlib-work/temp-file-owner`: `probe.lani`, used by the first four
  groups. The final compile receipt is `temp-file-owner-final-probe-compile.log`.
- `target/stdlib-work/file-at-primitives`: `primitives.lani`.
- `target/stdlib-work/file-at-bounds`: `bounds.lani`, used as the final primitive
  case. Its initial compile receipt is `file-at-bounds-first-compile.log`.

Each raw ELF passed static admission using the existing trusted source-runtime
verifier: three allocation/free runtime pairs per executable, with no named-site
fallback. Native source mapping checks then bind observed MAP_32BIT allocation
and release calls to those verified instruction addresses and original requested
lengths.

## Independent observations

The owner probe reads five little-endian u64 request words, emits 64 u64 report
words plus a copied 37-byte name, then waits for `!` on stdin. It acquires its
own parent descriptor; the oracle passes no native descriptor through strace.
Before ACK and process exit, the oracle verifies:

- The reported PID identifies the traced child, whose `/proc/<pid>/fd` contains
  exactly stdin, stdout and stderr.
- Every successful native open/duplicate has one final close of the same fd
  generation. Source allocations have matching verified releases with their
  original requested sizes.
- The real namespace and file bytes match removal or keep, with mode `0600`
  on kept files. Sentinel files and failed-construction namespaces stay intact.
- Renaming the original parent and creating a replacement at its old path
  leaves cleanup anchored to the original directory. This is a cooperative
  namespace test, not a hostile child-name race guarantee.
- Candidate names match the bytes actually returned by bounded OS entropy.
  Exclusive-open flags include create, exclusive, no-follow and CLOEXEC, without
  truncation. Excluded equality makes no open attempt. Both owned descriptors
  receive actual CLOEXEC queries.
- Marker-delimited create, keep, close, cleanup and repair phases agree with
  returned receipts. Repeated terminal cleanup has no effects, and keep makes
  no native call or allocation.

After ACK, the only extra traced call may be that one-byte read; process exit
must be zero with no extra stdout. Captured stderr must equal the trace's phase
markers. Primitive probes exit normally after explicit close; their completed
trace must balance every descriptor and contain no source allocation. Their
pre-exit `/proc` state is not inspected.

Faults are explicitly synthetic syscall results, not observations of natural
kernel failures. Each requested injection must reach its exact native ordinal,
and no unlisted injection is accepted. The allocation/constructor/close targets
are bound to the corresponding successful baseline's source address and role.
Entropy injections live only in strace; production exposes no deterministic
entropy alternative or predictable fallback.

An injected close skips the kernel close. The ledger therefore keeps that
actual fd generation live until the probe's separately marked `Q/q` raw repair
closes it. Cleanup close faults must occur in `A/a`; the explicit `close_file`
fault must occur in `F/f`. A wrong phase, repeated production close, missing
repair or repair of a different generation fails. These checks establish
logical owner retirement and truthful physical test cleanup; they do not claim
that a real Linux close error leaves an fd open.

The bounds probe rejects eleven malformed logical/NUL/4096-byte paths before
any mutation. It then performs exactly two successful renameat2 calls and one
unlinkat, with no source allocation and an empty final namespace. The primitive
fault cases require one native attempt and unchanged data for injected EIO,
EINTR, EAGAIN, ENOSYS or a nonzero success result. No retry or fallback may make
those cases pass.

Failed checks retain their case directory, including command/request, partial
report, stderr/status, native trace, diagnostics and filesystem snapshot where
available. Killing a child is failure recovery and cannot establish acceptance.

## CPU controls and scope

The accepted CPU-only check passed **26 controls**: valid ledgers/reports plus
mutations for missing/repeated/wrong-size source release, fd ownership errors,
unverified sites, incomplete traces, close repair/phase violations, incorrect
cleanup receipts and entropy/name disagreement. Static Python syntax and scoped
whitespace checks also passed. These start no native child and are separate
from the 78 native process cases.

The preliminary `temp-file-owner-basic-native.log` mode-0 check overlaps the
accepted owner group. The earlier `file-at-bounds-native.log` check overlaps the
last primitive case. Neither adds a case to 78; counting them would give 80
invocations with two additional repeats. They established narrower observations
before the full oracle, and do not independently establish source accounting or
the fault campaign. The earlier owner compiler error for typed `>=` spellings
stopped before native execution; the spacing and final-probe retries compiled.

Acceptance covers native x86-64 Linux host behavior on the filesystem used by
these runs. GPU compilation produces the native executable; these filesystem
operations do not run in GPU kernels. Other operating systems/filesystems,
power-loss durability, crash scavenging, hostile directory writers and atomic
publication are outside these receipts. The publication workflow remains in the
[atomic-files plan](../../../../docs/library-atomic-files-plan.md).

## Reproduction

Run commands separately, each under two minutes. The direct commands reuse the
already compiled executables; the Rust driver
`tests/stdlib_temp_file_execution.rs` also supplies one test per group.

```sh
timeout --kill-after=2s 70s python3 -B tests/fixtures/stdlib_execution/temp_file/oracle.py owner target/stdlib-work/temp-file-owner
timeout --kill-after=2s 70s python3 -B tests/fixtures/stdlib_execution/temp_file/oracle.py collisions target/stdlib-work/temp-file-owner
timeout --kill-after=2s 70s python3 -B tests/fixtures/stdlib_execution/temp_file/oracle.py validation target/stdlib-work/temp-file-owner
timeout --kill-after=2s 70s python3 -B tests/fixtures/stdlib_execution/temp_file/oracle.py faults target/stdlib-work/temp-file-owner
timeout --kill-after=2s 70s python3 -B tests/fixtures/stdlib_execution/temp_file/oracle.py primitives target/stdlib-work/file-at-primitives target/stdlib-work/file-at-bounds
timeout --kill-after=2s 10s python3 -B tests/fixtures/stdlib_execution/temp_file/oracle.py controls
```

Each native group emits exactly `temp-file group=<group> cases=<positive N>`
after all checks pass. A positive summary alone is not a broader platform or
durability guarantee.
