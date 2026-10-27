# Bounded archive materialization

`ext::archive_extract` materializes a sealed `ext::archive_source::Prepared`
through the canonical `std::atomic_file` owner. Source implementation is
present and has executed through both direct Run fixtures and the real
[unpack program](extended-unpack.md). The selected direct ownership, failure
and recovery campaign passed 11 groups / 100 native process invocations.
The finite scope and separate CLI receipts are recorded below.

The selected profile is native x86_64 Linux, an ordinary already-open directory
anchor, a local filesystem supporting atomic `NoReplace`, and a cooperatively
stable namespace including temporary names and mount topology. The caller's
root owner is borrowed and preserved. Directory descriptors remain the anchors
if their ancestors are renamed. This is not hostile-directory containment or
whole-tree atomic publication.

## Public owner

```lani
pub fn default_limits() -> Limits;
pub fn empty() -> Run;
pub impl Run {
    pub fn borrow(&self) -> &Run;
    pub fn execute(&self, source:&archive_source::Prepared,
        root:&std::file::File, limits:Limits) -> Result<bool,Failure>;
    pub fn state(&self) -> State;
    pub fn last_failure(&self) -> Option<Failure>;
    pub fn cleanup_failure(&self) -> Option<Failure>;
    pub fn root_close_error(&self) -> Option<core::io::Error>;
    pub fn stats(&self) -> Stats;
    pub fn node_status(&self, index:i32) -> Option<NodeStatus>;
    pub fn current_node(&self) -> i32;
    pub fn current_ordinal(&self) -> i32;
    pub fn current_receipt(&self) -> Option<std::atomic_file::Receipt>;
    pub fn recovery_name(&self) -> core::slice::View<u8>;
    pub fn resources_remaining(&self) -> bool;
    pub fn retry_current_directory_sync(&self) -> Result<bool,Failure>;
    pub fn keep_current(&self) -> Result<bool,Failure>;
    pub fn take_kept_name(&self, destination:core::slice::View<u8>)
        -> Result<i32,Failure>;
    pub fn cleanup(&self) -> Result<bool,Failure>;
    pub fn destroy(&self) -> Result<bool,Failure>;
}
```

Keep one active manual `Run`. Its shallow copies, File handles, and current
AtomicFile inspection identifiers are not additional owners. There is no
implicit destructor, extraction resume, rename retry, rollback or metadata
restoration. Every created directory requests 0700 and every temporary file
requests AtomicFile's private 0600, subject to normal host policy.

States are `Empty`, `Running`, `Complete`, `Failed`, `Destroyed`. The first
`execute` returns `Ok(true)` only after every explicit member and final
descriptor close succeeds. Repeating a completed execute is `Ok(false)`;
repeating a failed execute returns its immutable first execution failure.
Both repeats perform no archive decoding or host operation. A destroyed Run
cannot execute again. Recovery never resumes later archive members or changes
Failed to Complete.

`Failure { cause, stage, ordinal, node }` is metadata only. Stages identify
validation/reservation/root admission, payload decode, component walk,
directory creation/open/sync, AtomicFile create/write/commit, descriptor close,
cleanup, directory-sync retry, keep, name transfer and destroy. Causes retain
typed I/O, ZIP or AtomicFile failure data, or an explicit state, allocation,
metadata, namespace or budget limit. `last_failure` is the original execution
failure; recovery operations return their current failure without replacing
that primary or replaying AtomicFile's cached commit result.

Diagnostic limitation: per-node/member Run preflight checks currently leave
`Failure.node` and `Failure.ordinal` at `-1`, even when their validation loop
knows the relevant node/member. The typed cause remains accurate, and the
failure still precedes filesystem effects, but it does not identify that
entry's path. This includes Run depth/member-consistency/ZIP-output-bound
preflight failures; callers must not invent a node from the missing IDs.
Global validation/reservation failures also use `-1` deliberately. This
nonblocking diagnostic precision limit does not change `archive_source`'s
separate error ordinals or the IDs recorded during effectful Run operations.

## Preflight and borrowed data

The source must be live and its complete namespace sealed before extraction.
`archive_source` is responsible for the complete TAR footer/ZIP metadata pass,
member-kind policy, path policy, duplicates and file/ancestor conflicts. Run
checks membership/node consistency, depth, component lengths and resource
arithmetic, then allocates all node-status, directory-stack, node-chain and
37-byte recovery-name storage before duplicating the root or mutating output.
Every planned node has a status slot, including implied parents.

Prepared and its immutable complete archive backing are borrowed only during
`execute` and caller report resolution. Run stores node IDs/ordinals, never
borrowed input or scratch paths. Resolve a reported path with
`prepared.plan().path(node)` while Prepared is live. The materializer cannot
prove the physical backing/lifetime of a caller's manually constructed View.

Explicit members execute in archive order. ZIP payload extraction, decoded
length and CRC checking happen before *any* parent lookup/creation for that
member, including an explicit zero-byte directory. One decoded ZIP Vec is live
at a time and is destroyed on success or failure; TAR data stays borrowed.
A bad later ZIP payload can therefore leave earlier publications intact.
Checksums do not authenticate the archive's publisher. Decoder compressed and
decoded sizes are bounded; the separate host/loop cap is not an aggregate
DEFLATE/CRC CPU budget or a hard wall-clock limit.

## Anchored directory and file effects

Root admission duplicates the caller's descriptor with close-on-exec, checks
directory type and identity metadata, and rejects `O_PATH`. Every descendant
lookup passes exactly one validated component to `open_at` with directory,
no-follow and close-on-exec flags. No archive full path, cwd change, chmod,
metadata setter or recursive removal is used.

The materializer repeats component walks from its root duplicate. Opened
directories occupy the preallocated stack; previous traversal descriptors close
before the next walk. Missing components get one `create_dir_at` attempt.
Success is recorded immediately, before another open, sync or close can fail.
EEXIST authorizes only a checked reopen; it does not prove the name is a safe
directory. Existing symlink/non-directory parents fail the no-follow directory
open. Reopens compare checked inode/device identity against the earlier
observation; this detects changes without locking names or extending the
cooperative namespace contract.

For each newly created directory, the opened child is synchronized first,
then its opened parent, before descending. Both outcomes are retained. A
created directory whose open fails remains explicitly created/open-failed/
unsynced in its reserved record. Preexisting directories do not receive
invented creation/sync success, and a later explicit directory member does
not erase the earlier implied-parent creation/sync history.

Each regular file uses AtomicFile `NoReplace`; there is no destination
open/truncate or precheck-then-overwrite fallback. Writes use single AtomicFile
attempts, respecting short positive progress. Only nonsticky EINTR is retried,
within global write/host/step limits. Zero/count violations retain AtomicFile's
typed failure. Commit runs once, and publication visibility and synchronization
are taken from its receipt. Existing leaves and unsupported NoReplace behavior
fail explicitly. Earlier files/directories are never rolled back.

## Limits and accounting

| Limit | Default | Meaning |
| --- | ---: | --- |
| `max_owned_bytes` | 67,108,864 | Conservative simultaneous requested source heap, including Prepared |
| `max_depth` | 64 | Maximum selected plan node depth |
| `max_host_calls` | 1,048,576 | Conservatively charged active host-call upper bound |
| `max_cleanup_calls` | 1,048,576 | Separate monotone cleanup-credit reservations |
| `max_write_calls` | 1,048,576 | Actual AtomicFile write attempts across files |
| `max_sync_calls` | 1,048,576 | Actual directory and AtomicFile sync attempts across the run/recovery |
| `max_entropy_calls` | 1,048,576 | Actual TempFile entropy attempts across files |
| `max_name_attempts` | 262,144 | Actual temporary-name attempts across files |
| `max_zip_output` | 16,777,216 | Per-member ZIP decoded-output bound |
| `max_steps` | 16,777,216 | Bounded materializer validation/walk/write/close loop turns |

The heap reservation adds Prepared's actual `reserved_bytes`, exact node-status,
stack and node-chain capacities, the recovery copy, one maximum decoded ZIP
output candidate and 255+37 AtomicFile destination/temporary bytes. ZIP capacity
is conservatively at least four for a nonempty payload even though the current
canonical `try_resize` reserves its exact requested length. Arithmetic and each
Vec's byte-capacity limit are checked before effects. Borrowed input backing,
caller/application owners, native allocator/kernel state, stack memory and RSS
are excluded; the CLI must add its separate input owner and other allocations.
`Stats.owned_bytes` reports this conservative reservation, not measured RSS.

Run owns at most `1 + selected_depth + 2` descriptors: root duplicate, traversal
stack, and current AtomicFile directory/file. The caller root and process
streams/input owner are separate. `peak_fds` observes the materializer's owner
generations. The focused runtime ledgers below check the corresponding host
facts on the recorded native profile.

Namespace operations each precharge one active host call. Atomic create
precharges `3 + allowed_names + allowed_entropy`, commit five, directory-sync
retry two. A write precharges one per actual attempt; unused per-file write
allowance does not consume the global host budget. These opaque-call
precharges are deliberately conservative and are never described as exact
syscall counts. Default per-file temporary budgets are min(32, remaining global
names) and min(128, remaining global entropy). Write allowance is the remaining
global cap. Commit requires two remaining global sync attempts; AtomicFile's
directory-sync allowance is derived from remaining syncs minus its file sync.
Fresh per-file counters are reset before create and monotone write/byte/name/
entropy/sync deltas are settled after every AtomicFile call, including failures
and recovery. Constructing a new file cannot replenish global budgets.

## Cleanup, retained publication and kept names

Before each descriptor acquisition Run reserves one close credit; before an
AtomicFile create it reserves three cleanup credits. Reservations are monotone,
and unused reservations may remain charged. They are separate from the active
budget, so its exhaustion cannot suppress one worst-case cleanup attempt for
each currently owned descriptor/current AtomicFile. Explicit Atomic cleanup
consumes its lease once; another attempt needs additional credits. Exhaustion
returns `CleanupLimit` while retaining unresolved ownership. Each namespace
close retires its File before its result is reported and is never retried.

On the first execution failure Run attempts cleanup of an unpublished current
temporary and closes independent traversal/root descriptors. A definitely
published file with an unsynchronized parent keeps its AtomicFile anchor for
`retry_current_directory_sync`; automatic cleanup does not abandon that duty.
Visibility-unconfirmed remains a distinct failed receipt, not a successful
publication. A failed unlink retains its current temporary and anchor.

Public `cleanup` is a caller decision that may abandon an unsynchronized
published anchor. It does not undo publication or claim its directory became
synced. Public retry calls only the canonical directory-sync recovery, with
current receipts/deltas; it does not repeat write or rename. The original
execution failure stays unchanged even if recovery succeeds.

`keep_current` copies the current 37-byte temporary component into preallocated
Run storage *before* disarming deletion and cleanup can invalidate the original
name. `NodeStatus.kept` records that fact. The caller then owns an external
cleanup duty for that kept name under its recorded node/parent. Its component
remains available through `recovery_name`. Call `take_kept_name` with a live
at-least-37-byte destination to copy it and explicitly transfer that duty;
this does not close any still-retained native handles after a cleanup error.
`keep_current` can return a cleanup error after keep already succeeded. Inspect
the kept flag, current receipt and recovery component on that error path too;
an Err does not revoke the already-disarmed deletion or the transfer duty.
Unresolved handle/name ownership or an untransferred kept-name duty makes
`destroy` return `Retained` without freeing report storage. After resources
are gone, destroy frees tables once and invalidates their views. Repeat destroy
is `Ok(false)`. Check `resources_remaining`, not cleanup's boolean alone.

## Reports and acceptance

`NodeStatus` records every node's ID/original ordinal/kind/explicitness, visits,
confirmed mkdir and creating ordinal, open attempts/physical open, child and
parent sync attempts/success/errors, close attempts/error, and any file's
attempt/publication/keep/AtomicFile receipt. Sync/creation history is preserved
on reopens. `cleanup_failure` retains the first cleanup diagnostic, with per-node
close errors and a separate root close error. The current AtomicFile receipt
evolves after recovery; the first execution failure is immutable metadata.
Settlement also discovers AtomicFile's internal file-close, unlink and
directory-close diagnostics even if commit already retired all resources and
no later Run cleanup call is needed. That discovery does not increment a
numeric counter a second time.

`Stats` exposes seen/completed entries, created directories, definitely
published files, confirmed bytes, actual writes/name/entropy/sync attempts,
conservative active/cleanup charges, namespace closes/cleanup errors, loop
steps, conservative heap reservation and observed descriptor peak. It does
not erase an earlier publication when a later entry fails.
`cleanup_errors` counts failed Run Atomic-cleanup invocations (including a
cleanup-credit refusal), actual Atomic-directory-sync retry error reports, and
namespace close error reports. It does not count every Linux errno or infer
native attempts from receipt flags; internal AtomicFile cleanup details remain
in their separate receipt fields and first-discovery diagnostic.

The source freeze reviewed here is SHA256
`cf1347d5fe5df9adb9e8efcbf94a725e1e7d9784e25aff61ccdbd2e8e786276f`.
Independent read-only review found no material blocker in the selected
ownership/budget/recovery scope. That review is not executable acceptance.

### Direct Run acceptance

The selected campaign passed on native x86_64 Linux, kernel `7.0.0-38`, with
ext4 output under `/tmp`. All accepted native groups ran the independent Python
oracle directly against the same GPU-compiled native ELF:

| Accepted artifact | SHA-256 |
| --- | --- |
| Direct `probe.lani` | `8c47b00f66f1536fc24d4bfa872a70146ef2f6efe365b5d92a260f7cb5c929ff` |
| `target/stdlib-work/archive-materializer-admission` | `268b8bedbb2c5d5eb856b153a7a9ae4fcf14179d7c719f7b305c8eb634ea9704` |

Receipts are under `target/stdlib-work/`. Counts include calibrations and
overlapping baselines; they are not 100 distinct behaviors.

| Receipt | Groups / process invocations | Finite scope |
| --- | --- | --- |
| `archive-materializer-tree-single-owner-retry.log` | `success` 12; `existing` 8; `partial` 3 | Independent USTAR/ZIP trees, stored/fixed/dynamic DEFLATE, raw/offset/strided input, empty objects, implied/explicit parents, renamed root anchor, existing-parent and NoReplace conflicts, exact earlier publication before a later conflict/CRC/DEFLATE failure |
| `archive-materializer-bounds-first.log` | `bounds` 25 | Zero shared allowances, invalid root owners, measured exact/one-under heap, host, cleanup, write, sync and step limits |
| `archive-materializer-allocations-first.log` | `allocations_first` 8; `allocations_second` 8 | Two calibrations plus 14 reached source-allocation failures on one measured two-entry ZIP path |
| `archive-materializer-namespace-sync-fcntl-retry.log` | `namespace` 9; `sync` 5 | Reached duplicate/metadata/reopen failures; recorded mkdir before later failure; child, parent, file and post-rename directory-sync errors |
| `archive-materializer-write-close-first.log` | `writes` 8; `close_rename` 6 | Write/entropy errors and bounded interruptions, zero/invalid write counts, reached execution closes, internal AtomicFile cleanup diagnostics and visibility-unconfirmed rename |
| `archive-materializer-recovery-first.log` | `recovery` 8 | Published-directory sync retry, exhausted active budget with preserved cleanup lease, genuine three-byte prefix, failed unlink followed by cleanup or kept-name transfer |

The allocation campaign injected failure at all 14 measured source-allocation
positions on that path, binding each attempt to its verified runtime instruction
address, phase, requested size and prior publication/anchor progress. It covers Source
and planner storage, Run reservations, ZIP output and AtomicFile/TempFile source
buffers reached there. It does not establish every possible allocation path
or inject native allocator failures.

Four host ACK checkpoints expose owners before execution, after execution and
cached terminal replay, after explicit recovery, and after final destruction.
Before process exit, the oracle compares exact requested source mappings and
full-width allocation/release pointers with `/proc`, and tracked descriptor
generations with the live fd set. The caller root stays borrowed until its
separate close. The original serialized failure stays byte-for-byte unchanged through recovery;
the current receipt and cleanup diagnostics evolve separately. Cached terminal
execute performs no native work. Descendant opens require a tracked live
directory anchor and a single no-follow component. Outside sentinels and a
replacement root remain unchanged in the corresponding controls.

The short-write control sets only the native child's `RLIMIT_FSIZE` to three:
a real write returns three, the next fails with EFBIG, and a reached unlink
failure retains those actual bytes for inspection. Injected close failures
skip the kernel close; the probe separately repairs the exact physical fd
generation after checking logical retirement. Those marked repairs describe
the harness, not natural Linux close behavior. The retry-credit control uses
an exhausted active host budget and exactly four cleanup credits (root one,
AtomicFile three): a refused retry performs no native work and leaves the
original cleanup lease usable. Recovery does not write, rename, allocate or
unlink the published destination.

The shared Rust driver build passed in 1.26 seconds in
`archive-materializer-and-unpack-drivers-build.log`. The initial three libtests
stopped before native execution: `archive-materializer-tree-first.log` reports
`LNC0016` for unsupported fixture `else if` at 131:14 (0/3 tests; 4.11 s).
There was no passing libtest rerun. Fixture syntax/ownership and oracle-binding
corrections preceded the accepted direct Python campaign; they did not change
the frozen materializer source or weaken its resource assertions. The
[fixture guide](../tests/fixtures/extended/archive_materializer/README.md)
records those failed attempts, exact group scopes and checkpoint rules.
Separate Python CPU controls passed 44 assertions covering producer/framing
checks, first-failure preservation, source/fd ownership classification and
rejection of mutated causal bindings. They run no compiler or native probe.

### Unpack program acceptance

The real unpack CLI has these separate native receipts:

| Receipt under `target/stdlib-work/` | Result | Finite scope |
| --- | --- | --- |
| `archive-unpack-groups-first.log` | 4/4 tests; 69 process invocations; 10.64 s | Real trees 7, argument/input admission 27, bounds 30, reporting 5 |
| `archive-unpack-input-faults-first.log` | Direct retained-ELF oracle; 5 process invocations | One input calibration plus four reached read injections: EINTR recovery, exhausted EINTR allowance, EIO and synthetic oversized returned count |

These total 74 CLI process invocations with overlapping controls. The fifth
group was executed directly against the retained CLI ELF, not claimed as a
fifth libtest run or another compile. A synthetic positive count establishes
invalid-adapter-count handling, not actual bytes read. The
[program guide](extended-unpack.md#verification-scope) records its executable,
source hashes and ownership scope. This is native host filesystem execution
through GPU-compiled Lanius, not filesystem work inside GPU kernels.

A separate single observation extracted 273 ZIP entries with 2,129,920 decoded
file bytes in 1.653438 seconds. That time includes process startup, input,
extraction, synchronization, cleanup and reporting; it excludes compilation,
archive generation and independent validation. It is outside the 74-process
CLI campaign and is not a traced ownership receipt, throughput distribution or
compiler performance comparison. See the
[bounded runtime observation](extended-unpack.md#one-bounded-runtime-observation)
for its input, caps and measured scope.

### Remaining limits

These selected native gates establish the listed paths on one local Linux
profile. They do not establish every limit combination, archive layout,
allocation path or filesystem failure. Other architectures, hosts and
filesystems, GPU-kernel execution, power-loss durability and hostile namespace
mutation remain outside this acceptance. The cooperative namespace contract,
partial publication, explicit retained cleanup duty and lack of metadata
restoration/rollback still apply. The larger standard-library roadmap remains
open.
