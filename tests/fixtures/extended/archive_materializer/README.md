# Direct archive materializer gates

These fixtures call the actual `ext::archive_source` and
`ext::archive_extract::Run` APIs. Python supplies independent archive bytes,
namespace arrangements, syscall injection and observations. It supplies no
production extractor, codec, checksum or filesystem implementation.

The frozen direct-owner campaign passed **11 groups / 100 native process
invocations** on x86_64 Linux. These include repeated calibrations and overlapping
baselines; they are not 100 distinct behaviors. Root ran the independent Python
oracle against the frozen GPU-compiled ELF. The Python-only control now passes
44 assertions across producer interoperability, fd/phase mutation rejection,
binary framing, complete first-failure preservation, borrowed caller-fd identity
and exact ENOMEM and `fcntl` input-owner classification. It runs no compiler or
native probe. Source-only and CLI receipts retain their separate scopes.

The actual fixture compiled successfully in
`target/stdlib-work/archive-materializer-fixture-single-owner-retry.log`.
The shared direct/CLI Rust driver build passed in 1.26 seconds in
`archive-materializer-and-unpack-drivers-build.log`. The initial three libtests
failed before native execution; no passing libtest execution is claimed. The
accepted native campaign used direct Python invocations instead.

| Accepted artifact | SHA-256 |
| --- | --- |
| `extended/ext/archive_extract.lani` | `cf1347d5fe5df9adb9e8efcbf94a725e1e7d9784e25aff61ccdbd2e8e786276f` |
| `probe.lani` | `8c47b00f66f1536fc24d4bfa872a70146ef2f6efe365b5d92a260f7cb5c929ff` |
| `target/stdlib-work/archive-materializer-admission` | `268b8bedbb2c5d5eb856b153a7a9ae4fcf14179d7c719f7b305c8eb634ea9704` |

## Files and execution boundary

- `probe.lani`: actual Prepared and Run owners, caller root and four ACK barriers.
- `cases.py`: Python `tarfile` USTAR, `zipfile`, and classic raw-name ZIP records
  around established `zlib` stored/fixed/dynamic output; independent declared
  namespace manifests checked with `lstat` and file bytes.
- `ledger.py`: verified raw-ELF opcode/source sites from the unchanged TempFile
  helper, the Source fixture's full-width live mapping helper, and local fd
  generations, anchored-call policy and operation phases.
- `oracle.py`: finite groups, pre-exit `/proc` checks, causal baseline/fault
  binding, binary report interpretation and filesystem observations.
- `tests/extended_archive_extraction_execution.rs`: one focused test per group;
  GPU compilation produces a native x86_64 Linux executable.

No filesystem operation runs in a GPU kernel. The namespace must be cooperative
and stable during extraction, apart from the explicit anchor-rename control.
These gates make no network-filesystem, hostile-writer or power-loss claim.

## Checkpoints

The request is 29 little-endian u64 words followed by the exact archive bytes.
Its order is `REQUEST_NAMES` in `oracle.py`; it binds every actual Source and
Run limit explicitly. Layouts are packed, packed offset seven, and a native
strided window at offset three. Archives are capped at 65,528 bytes by the
probe; the strided fixture is capped at 8,188 bytes.

Each response has a four-byte payload length, a 192-u64 header, copied recovery
and transferred-name buffers of 37 bytes each, then per-node records. A node
has 58 u64 words followed by its canonical path bytes. Header and node records
retain primary, cleanup and action errors, including the complete nested
AtomicFile failure receipt. Stats, identity, exact sync/close attempts and
publication facts remain separately inspectable. Packed stdout writes are at
most 1,024 bytes; the oracle reconstructs actual completed chunks.
The source-cause word retains its category in the low 32 bits and typed planner
Allocation detail 12 in the high 32 bits. This does not change frame offsets.
Checkpoints 2 and 3 must preserve all 320 serialized bytes of checkpoint 1's
primary Failure, including its original nested AtomicFile receipt. Cleanup,
action and current receipt fields can evolve independently. Admitted caller
roots must keep the same fd generation through checkpoints 0, 1 and 2.

1. Checkpoint 0 follows complete Source admission and caller-root open, before
   Run execution. The output tree must still match its initial snapshot.
2. Checkpoint 1 follows first execution and cached terminal execution, before
   any caller recovery. The oracle observes published files, confirmed mkdirs,
   retained temporary bytes, source maps and descriptor generations here.
3. Checkpoint 2 follows selected explicit directory-sync retry, cleanup or
   keep/name transfer. It exposes recovery results before final cleanup.
4. Checkpoint 3 follows cleanup, repeated terminal destruction, Prepared
   destruction and caller-root close. No owned source mapping or native fd
   may remain before ACK permits process exit.

The native child opens its own root; no descriptors are inherited as library
owners. `/proc/<pid>/fd` must equal the trace's live generations plus 0/1/2.
`/proc/<pid>/maps` must agree with live requested allocations and actual release.
Requested source bytes are tracked at verified mmap/munmap runtime addresses
with exact full-width pointers, flags and requested lengths. Named-site fallback
is rejected. Syscall post-instruction addresses must be in verified executable
ranges. Process exit cannot conceal a leak.
Execution-phase descendant opens require a decimal, tracked-live parent dirfd;
AT_FDCWD is rejected even for a single-component name. The renamed-anchor case
also preserves the replacement root and its sentinel unchanged.

## Accepted finite groups

Receipts below are under `target/stdlib-work/`. Counts include each group's
baseline and each actual child; earlier failed diagnostic attempts are excluded.

| Group | Processes | Direct-owner scope | Receipt |
| --- | ---: | --- | --- |
| `success` | 12 | Independent USTAR and Python ZIP, stored/fixed/dynamic DEFLATE, implied then explicit parents, empty archives/files/directories, binary/raw names, both formats with offset/strided input, renamed/replaced caller-root anchor. | `archive-materializer-tree-single-owner-retry.log` |
| `existing` | 8 | Existing parent metadata, intermediate regular file/symlink to a real outside directory, NoReplace leaf regular/symlink/FIFO/socket/hard-link conflicts; outside targets/aliases unchanged. | `archive-materializer-tree-single-owner-retry.log` |
| `partial` | 3 | Exact first publication before late leaf conflict, CRC error or invalid DEFLATE; no missing parents created for a bad payload. | `archive-materializer-tree-single-owner-retry.log` |
| `bounds` | 25 | Zero shared allowances and invalid root owners; measured exact/one-under owned/host/cleanup/write/sync/step limits. | `archive-materializer-bounds-first.log` |
| `allocations_first` | 8 | One calibration plus first seven reached source-allocation failures on the measured multi-entry ZIP path. | `archive-materializer-allocations-first.log` |
| `allocations_second` | 8 | One calibration plus remaining seven reached source-allocation failures on that same path. | `archive-materializer-allocations-first.log` |
| `namespace` | 9 | Reached duplication/metadata/reopen failures; confirmed mkdir remains recorded before later fallible operations. | `archive-materializer-namespace-sync-fcntl-retry.log` |
| `sync` | 5 | Reached child/parent/file/post-rename directory fsync errors, including retained Published-unsynced bytes before one explicit retry. | `archive-materializer-namespace-sync-fcntl-retry.log` |
| `writes` | 8 | Write EIO/zero/invalid count/EINTR, finite write interruption exhaustion, entropy EIO and finite entropy interruption exhaustion. | `archive-materializer-write-close-first.log` |
| `close_rename` | 6 | Each reached execution close denied separately, exact retired-generation repair, internal Atomic cleanup diagnostics and Unconfirmed rename. | `archive-materializer-write-close-first.log` |
| `recovery` | 8 | Directory-sync retry and retry HostLimit with original cleanup lease, genuine three-byte prefix, failed unlink followed by cleanup or kept-name transfer. | `archive-materializer-recovery-first.log` |

The allocation halves cover **all 14 reached allocation positions** on the
measured current path, with two calibrations. This is not every possible
allocation path. All native groups inspect source/fd ownership before final
ACK, preserve the serialized first failure through recovery/destruction, and
exercise cached terminal execution without native work.

The namespace oracle rejects regular destination open/truncate, metadata
restoration, unsupported host effects, slash-containing descendant lookup,
followed directory opens, replacement rename and unlink of any destination.
New objects must have requested content-only private modes; normal parent
timestamps/link counts may change through child creation. Existing directory
permission/ownership/inode metadata must remain unchanged.

All injections must reach the selected syscall ordinal and preserve its
successful/failure-control source address, phase, owner role and argument shape.
There are no accepted unreachable-injection skips. A paired failed-operation
control supplies the cleanup unlink when the successful baseline has no unlink.
ENOMEM expectations derive from the measured allocation's phase, anchor/rename
progress and requested size: Source planner Allocation or member allocation,
Run reservation AllocationFailed, ZIP AllocationFailed, Atomic destination
AllocationFailed or TempFile name AllocationFailed. Other errors in those
families do not pass the allocation campaign.

The first three direct tests stopped before native execution at unsupported
fixture `else if` syntax (`archive-materializer-tree-first.log`, 4.11 seconds).
An admission retry then exposed a fixture nested integer-match inference issue
in its source-error serializer (`archive-materializer-fixture-admission.log`).
Nested `else` blocks and a boolean match with explicit u64 assignment corrected
these fixture issues. The typed retry compiled successfully in
`archive-materializer-fixture-typed-match-retry.log`; it supplies no native
acceptance by itself. Production code was unchanged.

The first native launch then stopped in the oracle before its first checkpoint:
the event-selector helper shadowed Python's imported `select` module
(`archive-materializer-tree-guards-retry.log`). Importing that module as
`select_io` separates it from the event helper without changing timeout behavior.
The next launch materialized the first USTAR tree and reached checkpoint 2, then
the strict source ledger rejected duplicate releases before checkpoint 3
(`archive-materializer-tree-select-retry.log`). The probe had called destroy on
two separately unwrapped shallow Prepared copies. Binding one owner, destroying
that same owner twice, then storing its retired state back fixes the fixture's
manual ownership violation. The ledger assertion remains unchanged. Neither
attempt is accepted coverage, and neither required a production change.

The first namespace fault run then reached the intended failed root duplicate
but the oracle compared its missing *result* owner with the successful
duplicate's new result owner (`archive-materializer-namespace-sync-first.log`).
A failed duplicate creates no result fd. The corrected ledger instead annotates
the verified live input owner of every fcntl and binds its role, generation and
complete arguments on both success and failure. A positive CPU control accepts
that causal pair; four mutations reject changed/missing input ownership or
arguments. The strict resource assertions remain intact. Namespace 9 and sync 5
then passed in `archive-materializer-namespace-sync-fcntl-retry.log` against the
same accepted ELF, with no production or probe change.

## Genuine effects and recovery

The short-write case lowers **only the traced child's** `RLIMIT_FSIZE` to three
while it waits at checkpoint 0. The child installs SIGXFSZ ignore in phase H;
the canonical signal enum has no SIGXFSZ variant, so this test mirrors its
existing kernel sigaction layout through `std::linux::call`. Local Linux headers
confirm SIGXFSZ 25, rt_sigaction 13 and SIG_IGN 1. This agrees with
[Linux resource-limit behavior](https://man7.org/linux/man-pages/man2/getrlimit.2.html)
and [sigaction](https://man7.org/linux/man-pages/man2/sigaction.2.html).
The oracle/strace process limits and dispositions are unchanged. A real file
write must return three, the next must return EFBIG, and one separately injected
unlink EIO retains the actual three-byte temporary before checkpoint 1 ACK.
No synthetic positive write result is called a real prefix.

An injected close is skipped by strace and leaves that physical fd generation
open. The library must retire its logical owner once. The probe's separately
marked Q phase closes precisely that known generation after checkpoint 1;
repeated production close or missing/wrong repair fails. These repairs are
harness artifacts, not claims about natural Linux close failures.

The retry-credit control uses one root-level file, an injected post-rename fsync
EIO, the measured exhausted host allowance and an exact four-credit cleanup
allowance (root one plus AtomicFile three). Retry must return HostLimit without
native work or consumed cleanup credit, then explicit cleanup must still work.
No retry may write, rename, allocate or unlink the destination.

## Commands

Run one group at a time. The Rust driver limits the oracle to 68 seconds and
the oracle refuses to start another case after 62 seconds. Root coordinates
compilation and all native execution.

```sh
python3 -B tests/fixtures/extended/archive_materializer/oracle.py controls
cargo test --test extended_archive_extraction_execution actual_materializer_extracts_ustar_zip_and_raw_views_with_owned_parent_records -- --exact --nocapture
timeout --kill-after=2s 68s python3 -B tests/fixtures/extended/archive_materializer/oracle.py success PATH_TO_RETAINED_ELF
```

Replace `success` with one other group for separate bounded native invocations.
Successful groups emit exactly `archive-materializer group=<group> cases=<N>`
with positive N. Native failure preserves the request, command, trace, partial
packets, namespace snapshots, live maps/fds and stderr under the printed
`/tmp/archive-materializer-*` directory. Killing a child is diagnostic recovery
and never turns a failure into acceptance.
