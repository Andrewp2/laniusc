# Resumable directory cursor verification

These fixtures execute [`std::walk`](../../../stdlib/std/walk.lani) through a
native-linked Lanius probe. The Python oracle builds real filesystem trees,
chooses one cursor operation at a time, and checks copied event reports against
the host filesystem. Traversal and resource ownership remain in Lanius.
The public contract is in [Resumable directory traversal](../../../docs/stdlib-directory-cursor.md).

The accepted target is Linux x86_64 CPU output from the GPU compiler. The gates
require the compiler's GPU environment, native link tools, `python3`, `strace`,
`/proc`, and the tools used by the shared native source-authority verifier.
They do not execute directory services on a GPU device or establish support
for other hosts.

## Files and protocol

- `probe.lani` accepts limits and explicit `next`, `descend`, `prune`, and
  `close` commands. Its binary reports contain event bytes, metadata, descriptor
  numbers and counters. Each report pauses the process for host inspection or
  a deterministic filesystem mutation.
- `oracle.py` checks membership, types, identities, nesting, decisions,
  resource traces and reached faults. It does not prescribe sibling order or
  assume traversal supplies a filesystem snapshot.
- `host_controls.py` tests the observer against good and deliberately invalid
  reports and traces. It needs no compiled probe.
- [`tests/stdlib_directory_cursor_execution.rs`](../../stdlib_directory_cursor_execution.rs)
  compiles the probe once per test process and registers five focused gates.

## Accepted gates

The parent execution lane accepted **60 native scenarios and 39 host observer
controls**. Fault-group counts include successful baselines. Logs below are
local receipts under `target/stdlib-work/`; they are not committed artifacts.

| Group | Exact test selector | Accepted result | Test duration | Receipt |
| --- | --- | --- | --- | --- |
| Model | `directory_cursor_resumption_pruning_and_borrowed_descriptors_execute` | 6 cases | 9.83 s | `directory-cursor-model-accepted.log` |
| Mutations | `directory_cursor_anchoring_replacements_and_symlink_policy_execute` | 9 cases | 11.31 s together with limits | `directory-cursor-mutations-limits.log` |
| Limits | `directory_cursor_limits_cancellation_and_terminal_states_execute` | 20 cases | Same combined run | `directory-cursor-mutations-limits.log` |
| Faults | `directory_cursor_reached_allocation_and_io_failures_release_owners` | 25 scenarios | 8.72 s | `directory-cursor-faults.log` |
| Observer | `directory_cursor_observer_rejects_bad_reports_and_resource_traces` | 39 controls | No separate duration recorded | `directory-cursor-functional-final.log`, observer selector only |

The observer receipt came from an earlier mixed run in which native selectors
still rejected probe syntax. The three later native receipts above supersede
those native failures; the mixed log is evidence only for its passing observer
selector. The accepted durations include the work performed within each test
run and are not compiler or traversal benchmarks.

Run a single native gate from the repository root, replacing `SELECTOR` with
the exact name above:

```sh
timeout 100s cargo test --test stdlib_directory_cursor_execution SELECTOR -- --exact --test-threads=1 --nocapture
```

Run only the observer controls:

```sh
timeout 10s python3 -B tests/fixtures/stdlib_directory_cursor/host_controls.py
```

The Rust driver gives each oracle group 80 seconds. The oracle admits no new
case after 72 seconds and bounds each report/exit wait. A failure retains its
temporary directory and prints its path; success removes per-case traces.
The acceptance logs therefore retain group totals, not per-site syscall
ordinals or separate allocation-fault totals.

## Behavioral evidence

The six model cases cover empty, nested and pruned trees, 16 and 160 siblings,
and twelve nested directories. Names include invalid UTF-8 and a newline.
Symlinks, a dangling link, a loop link, a FIFO and a Unix socket are observed
without descending into them. Checks include parent descriptor identity,
live descriptors through `Leave`, balanced enter/leave events, explicit
decisions, invalid repeated decisions, and fused exhaustion. Pruning must not
open the child. Equal-length names in the two wide trees must yield the same
peak source-owned heap extent.

Mutation cases pause at known events. Renaming an opened root must preserve
its original contents; closing the caller's parent descriptor after `open_at`
must leave the cursor usable. Replacing an observed child with a different
directory, a symlink or no entry must produce the appropriate fault rather
than enter the replacement. Separate cases distinguish final-component
no-follow from an explicit `root/.` path and check constructor failures.

Bounds cases cover invalid logical views, invalid limits, zero entries on an
empty tree, exact entry/path limits, the active-reader cap, and cancellation
at entry, enter and leave events. Entry-cap rejection consumes no admission
count; a later path-cap rejection retains the admitted count. Metadata faults
also count as admitted entries. Counters must remain unchanged through close,
repeated close and rejected closed-state calls.

Work acceptance is independent of reported work deltas. The oracle combines
constructor cost, active transitions, checked path/name lengths, descent cost,
and traced `getdents64` returned bytes and record extents. It checks the
reported total, then uses the independently computed value for exact and
one-unit-short budget cases.

## Resource and fault evidence

Every native case runs with `LANIUS_ALLOC=mmap`. The oracle classifies each traced
post-syscall instruction through the shared native source-authority verifier.
Sized Lanius functions and exact runtime blocks authorize source calls;
loader and verified CRT bootstrap activity remain separate. An unknown
executable-image site fails the observer.

The shared source-map ledger checks full-width addresses, allocation flags,
requested byte extents, matching releases and zero live source owners.
A separate ledger tracks each descriptor generation and close attempt.
Both run against a completed report checkpoint while the child remains alive,
then against the final trace. `/proc/PID/fd` also verifies that explicit
cleanup leaves no owned descriptors. Process exit cannot satisfy the earlier
cleanup checkpoint.

Faults are selected from successful source traces using global syscall
ordinals. Each faulted run must show exactly that injected call at an
authorized source instruction. Coverage includes every source mmap call in
the small-tree baseline, the first allocation of each additional stack/path
extent in a deeper tree, and every baseline source `openat`, `statx` and
`getdents64` call. The oracle checks typed outcomes, sibling continuation,
event balance and cleanup. This does not exhaust every allocation schedule,
filesystem race, metadata-mask failure or host errno.

Two EIO cases exercise close after `Leave` and explicit cancellation with two
active readers. Cancellation must attempt each reader once, return the first
close error, preserve counters and make repeated close do no native work.
Because strace injection skips the actual close, the failed descriptor stays
open in the kernel. A separate `Q/q`-marked repair closes that exact generation
once. The evidence establishes owner invalidation and one-attempt behavior;
it does not treat the synthetic failure as real kernel descriptor release.

The 39 observer controls reject missing or duplicate closes, leaked or
wrong-sized mappings, unknown syscall sites, bad repair ownership, incorrect
event identities/depths/counts, wrong work totals, and cancellation that drops
the first error or fails to close the other reader.

The [recursive grep consumer](../../../docs/extended-text-grep-walk.md) has a
separate 35-case acceptance receipt. Its cases are not part of these 60.
