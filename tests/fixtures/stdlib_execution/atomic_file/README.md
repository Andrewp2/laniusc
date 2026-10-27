# Atomic-file publication tests

The native probe and independent Python oracle exercise the frozen
[`std::atomic_file` contract](../../../../docs/stdlib-atomic-files.md).
Production operations run in Lanius. Python arranges the namespace, observes
file contents, controls test-only syscall injections and checks ownership.

The actual probe compiled successfully to
`target/stdlib-work/atomic-file-owner`; its receipt is
`target/stdlib-work/atomic-file-owner-first-compile.log`. The Rust driver also
compiled in `atomic-file-and-kv-test-drivers-build.log`. Root then ran all four
native oracle groups successfully against that executable. The Rust driver's
`--no-run` build is separate evidence; no libtest execution is claimed here.

The accepted raw probe ELF has SHA-256
`2a62125749eebfcffe2a76597a1f24d971fc3cdace70b54efd586640163ef59c`.
Its static profile has three verified allocation/free runtime pairs and no
named-site fallback. These checks use the existing trusted compiler-runtime
verifier; native traces must then match those sites and their requested lengths.

## Accepted finite groups

| Group | Process cases | Scope | Receipt under `target/stdlib-work/` |
| --- | ---: | --- | --- |
| `owner` | 9 | Replace with an old reader still open, empty publication with zero byte/write limits, 33,798-byte binary data, vacant NoReplace, renamed/replaced parent and changed cwd, keep, cleanup and replacement of a destination symlink itself. | `atomic-file-owner-group-first.log` |
| `publication` | 6 | Successful baseline, Published directory-sync EIO followed by one successful retry, exhausted shared sync allowance, real NoReplace conflict and two real contenders held at a precommit barrier. | `atomic-file-publication-first.log` |
| `bounds` | 25 | Five invalid options, nine invalid destinations/views, two valid long/non-UTF-8 destinations, three bad parent descriptors, three invalid write views, an empty write with zero budget and two recoverable preflight errors followed by real writes. | `atomic-file-bounds-selector-retry.log` |
| `faults` | 26 (`24 + A`, `A=2`) | Every baseline-reached source allocation, write errno/zero/over-count, bounded EINTR, a synthetic positive count, a real 1,024-byte prefix followed by EIO, file sync/close, ambiguous rename, directory sync/close and failed unlink followed by retry or keep. | `atomic-file-faults-first.log` |

The accepted total is **66 process case invocations** (`64 + A`, with `A=2`).
Baselines repeat behavior from other groups, so the total is not distinct
coverage. `A` is measured from one successful binary publication and is not a
claim about every library path.
Earlier smoke tests or prerequisite TempFile cases retain their own scope;
they must not be added as new distinct AtomicFile behaviors.

The first bounds attempt stopped at `19-write-view-1` because the oracle's
no-payload-write assertion counted the one-byte stderr `W/w` markers. The trace
and report agreed that the owned file fd 5 had no write and bytes/attempts were
zero. The fixture correction selects writes on the captured owned file fd;
markers stay excluded, while an actual payload write still fails. Two CPU
controls cover that distinction. Receipt `atomic-file-bounds-first.log`
preserves this harness failure; the full 25-case retry passed without a change
to production or the compiled probe.

## Checkpoints and observations

The request is twelve little-endian u64 words. Each response is 128 u64 words,
a copied 37-byte temporary component and a copied 255-byte destination buffer:
1,316 bytes in total. The ordinary descriptor writer sends the frame in native
chunks of at most 1,024 bytes. The oracle reconstructs exact completed stdout
chunks, checks the frame boundary and compares them with the captured response.
It does not assume that a frame is one native write.

- Checkpoint 0 is the NoReplace contender barrier. Both owners have created and
  written separate temporary files before either is allowed to commit.
- Checkpoint 1 follows the first commit, or the selected create/write operation,
  before recovery or cleanup. An ACK permits the next action.
- Checkpoint 2 follows explicit cleanup/destroy and caller-parent retirement.
  The oracle inspects resources before its final ACK permits process exit.

The child opens its own parent descriptor; the harness passes no fd through
strace. At each checkpoint, `/proc/<pid>/fd` must match the live native fd
generations in the syscall ledger. `/proc/<pid>/maps` must agree with live and
released source allocations. Final release requires no live source mapping or
owned native fd, before process exit could conceal leaks.

The ledger reuses the accepted TempFile raw-ELF runtime verifier and final source
mapping checker. Source allocation/release addresses and original requested
lengths must balance. Cached commit and keep make no native call; directory-sync
retry cannot write, allocate, open, rename or unlink. Cleanup may unlink only the
captured temporary name through its captured anchor, never the destination.

Reports expose current state and sync facts, the first-publication snapshot,
the first fatal diagnostic, the latest action diagnostic, per-call cleanup and
cumulative cleanup errors. The probe compares the exact cached first commit
Result before and after retry/cleanup. Current state may change while that
historical result remains unchanged. Successful progress clears latest_error;
the first fatal diagnostic and cumulative close/removal errors remain available.

The critical directory-sync case observes the complete new destination and
Published visibility while the anchor remains live and directory durability is
unconfirmed. Only then does ACK permit one retry. That retry must perform one
directory fsync, preserve one total rename and never unlink the destination.
The exhausted-budget variant makes no additional fsync and still preserves the
published bytes and visibility.

The real-prefix case uses one large write_all: the first native 1,024-byte
write succeeds, then the next write returns injected EIO. Actual temporary-file
bytes, lifetime bytes and Failure.completed must all identify that real prefix.
The separate synthetic-positive case skips the kernel write while returning
three. It requires reported progress three and actual file length zero, and
does not attempt publication. This tests count handling without claiming those
synthetic bytes were written.

Each declared injection must reach its exact ordinal and match the successful
baseline's source site/owner role and relevant argument prefix. A skipped
file/anchor close remains physically live in the ledger until the probe's
separately marked raw repair closes that same fd generation. A missing repair,
wrong phase or repeated production close fails. These are labelled harness
artifacts, not claims about physical effects of natural close failures.

Failed cases retain requests, partial reports, stdout/stderr/status, commands,
traces, ownership snapshots and filesystem evidence where available. Killing
a child is diagnostic recovery and cannot make a case pass.

## CPU controls and reproduction

The current CPU-only check passes **36 controls**, including the reused TempFile
ownership mutations, live/final AtomicFile mapping and fd checks, forbidden
cached/retry work, malformed report metadata, two-chunk frame reconstruction,
frame drift rejection, finite EINTR injection ranges and the distinction between
stderr phase markers and actual owned-file payload writes. It executes no compiler,
native probe or tracing process.

Run each native group separately, under two minutes:

```sh
timeout --kill-after=2s 70s python3 -B tests/fixtures/stdlib_execution/atomic_file/oracle.py owner target/stdlib-work/atomic-file-owner
timeout --kill-after=2s 70s python3 -B tests/fixtures/stdlib_execution/atomic_file/oracle.py publication target/stdlib-work/atomic-file-owner
timeout --kill-after=2s 70s python3 -B tests/fixtures/stdlib_execution/atomic_file/oracle.py bounds target/stdlib-work/atomic-file-owner
timeout --kill-after=2s 70s python3 -B tests/fixtures/stdlib_execution/atomic_file/oracle.py faults target/stdlib-work/atomic-file-owner
timeout --kill-after=2s 10s python3 -B tests/fixtures/stdlib_execution/atomic_file/oracle.py controls
```

Each successful native group prints exactly
`atomic-file group=<group> cases=<positive N>`. The Rust driver
`tests/stdlib_atomic_file_execution.rs` provides one test per group.

The target is native x86-64 Linux host execution on the tested local filesystem;
GPU compilation produces that executable. No filesystem operation runs in a GPU
kernel. These tests do not establish network-filesystem semantics, protection
against hostile directory writers, locking or power-loss durability.
