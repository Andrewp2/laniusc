# Atomic file publication

`std::atomic_file` is executable on the selected native x86_64 Linux profile.
Four focused groups passed **66 native process invocations**, including repeated
baselines. The migrated `kv_tool` consumer has its own
[application receipts](extended-kv.md#current-application-receipts).
The parent namespace must be exclusive/cooperative throughout creation,
publication and cleanup. This is not a hostile-directory sandbox, filesystem
transaction, concurrency lock or universal power-loss guarantee.

## Frozen public contract

The shortened names below refer to core/std modules. These declarations fix the
consumer/test boundary; executable implementation lives in `std::atomic_file`.

```lanius
pub struct Options {
    temporary: temp_file::Limits,
    policy: file_ops::RenamePolicy,
    max_bytes: u64,
    write_calls: u64,
    directory_sync_calls: u64
}
pub enum State { Inactive, Writing, Failed, Published, Kept, Released }
pub enum Visibility { NotPublished, Published, Unconfirmed }
pub enum Stage {
    Validate, Allocate, Create, Write, SyncFile, CloseFile,
    Rename, Disarm, SyncDirectory, Cleanup, Keep
}
pub enum Error {
    InvalidState, InvalidOptions, InvalidDestination, AllocationFailed,
    Bounds, ByteLimit, WriteLimit, DirectorySyncLimit, NoProgress, InvalidCount,
    Io(io::Error), Temporary(temp_file::Failure), Ownership(temp_file::Error)
}
pub struct Stats {
    bytes: u64, writes: u64, file_syncs: u64,
    renames: u64, directory_syncs: u64
}
pub struct Diagnostic { stage: Stage, cause: Error, completed: u64 }
pub struct Receipt {
    state: State,
    visibility: Visibility,
    stats: Stats,
    temporary_stats: temp_file::Stats,
    file_synced: bool,
    directory_synced: bool,
    file_open: bool,
    directory_open: bool,
    temporary_owned: bool,
    retained: bool,
    cleanup: temp_file::Cleanup,
    last_error: Option<Diagnostic>
}
pub struct Failure {
    stage: Stage, cause: Error, completed: u64, receipt: Receipt
}
pub fn empty() -> AtomicFile;
pub fn default_options() -> Options;
pub impl AtomicFile {
    pub fn borrow(&self) -> &AtomicFile;
    pub fn create_in(&self, parent: &File, destination: Path, options: Options)
        -> Result<bool, Failure>;
    pub fn write(&self, input: View<u8>) -> Result<i32, Failure>;
    pub fn write_all(&self, input: View<u8>) -> Result<u64, Failure>;
    pub fn commit(&self) -> Result<Receipt, Failure>;
    pub fn retry_directory_sync(&self) -> Result<Receipt, Failure>;
    pub fn keep(&self) -> Result<bool, Failure>;
    pub fn cleanup(&self) -> Result<Receipt, Failure>;
    pub fn destroy(&self) -> Result<Receipt, Failure>;
    pub fn receipt(&self) -> Receipt;
    pub fn last_failure(&self) -> Option<Failure>;
    pub fn last_cleanup(&self) -> temp_file::Cleanup;
    pub fn temporary_name(&self) -> View<u8>;
    pub fn destination(&self) -> View<u8>;
    pub fn file_handle(&self) -> Option<i32>;
    pub fn directory_handle(&self) -> Option<i32>;
}
```

Defaults are TempFile's 32 candidate/128 entropy calls, Replace, 16 MiB,
65,536 write attempts and eight directory-sync attempts. Zero max_bytes or
write_calls permits an empty publication. Directory-sync allowance is positive.
The owner copies a validated destination component before effects and calls
TempFile.create_in_excluding with that owned copy. No File/TempFile write borrow
is returned. Descriptor identifiers are borrowed inspection metadata; independent
I/O, closing, adoption or namespace mutation through them violates ownership.
Names borrow the live owner until release/reuse. Keep one active manual owner.

## Write policy

Writes are sequential and bounded by cumulative confirmed bytes and native
attempts. One write attempt transfers at most 1,024 bytes, adapting packed or
strided input through the existing file writer. Logical View bounds precede any
indexing or effect; callers must supply valid physical backing.

- Malformed logical Views and requests exceeding the remaining byte allowance
  are recoverable preflight errors: no host attempt, progress or poisoned owner.
- Empty writes make no native call, including with a zero write allowance.
- Every nonempty native attempt consumes allowance, including EINTR.
  `write` reports EINTR without poisoning; `write_all` retries only EINTR under
  the same finite allowance.
- Exhausted write allowance, other host errors, zero progress and unexpected
  counts are fatal. A fatal write prevents commit. Failure.completed is the
  confirmed prefix for that write operation; Stats.bytes is lifetime progress.

## Publication and recovery

Commit freezes writes, syncs the file, closes it once, makes one anchored rename,
locally records Published and disarms temporary deletion, then syncs the
directory. File sync/close failure prevents rename. NoReplace uses the real
atomic host flag, preserving an existing destination. It has no check/replace
or copy/delete fallback.

For the selected local Linux profile, documented ordinary rename errors
(including EEXIST) establish NotPublished. EIO, undocumented EINTR and unexpected
native results remain Unconfirmed. These are conservative distinctions based on
the [POSIX rename contract](https://man7.org/linux/man-pages/man3/rename.3p.html)
and [Linux rename](https://man7.org/linux/man-pages/man2/rename.2.html), whose NFS
replay warning is another reason network filesystems are excluded. The caller
must never infer rollback from an ambiguous failure.

Successful rename records Published before directory sync. A directory-sync
failure retains the anchor; retry_directory_sync makes at most one attempt
under the original shared sync allowance and never writes, renames or rolls
back. Successful sync retires remaining resources. Repeated commit returns the
exact cached first result without a native call; receipt() reports current
facts after explicit retry or cleanup.

The first saved diagnostic remains Failure.stage/cause/completed. The receipt's
last_error is the error of the latest progress action: failures set it and
successful write/create/keep/retry/cleanup actions clear it, including successful
inert calls. Inspections and exact cached commit replay do not mutate it.
Recoverable preflight errors and EINTR can update last_error without poisoning
last_failure or publication. Receipt.cleanup accumulates actual cleanup
attempts and preserves close/removal errors across later inert/successful calls.
last_cleanup is the latest-call receipt. Published visibility and successful
sync facts survive all cleanup errors. Cleanup never unlinks the destination or
turns unconfirmed directory durability into success.

Before publication, unresolved cleanup retains the temporary name and anchor.
keep can accept that leftover file and disarm deletion, after which cleanup
retires remaining descriptors/backing. Keep does no I/O and prevents later
publication. Confirmed Published state already disarmed the source, so keep
there returns a recoverable InvalidState instead of adopting the destination.
The application must report a kept recovery name while its borrow
is live. Failed construction likewise retains acquired recovery ownership.
Receipts/failures own metadata only; no allocation is needed for commit, keep,
retry or terminal cleanup. Kernel writes/opens/syncs can block: budgets bound
attempts, not time.

## Executable acceptance

The GPU compiler produced a native x86_64 ELF from the frozen implementation.
The accepted production source SHA-256 is
`9e0a970995d68f4c3ac1c1f2d307438d07796bee978affee694423b0d543af34`;
the probe ELF SHA-256 is
`2a62125749eebfcffe2a76597a1f24d971fc3cdace70b54efd586640163ef59c`.
The actual process directories were on local **ext4**, with **Linux
7.0.0-38-generic** on **x86_64**. These are host filesystem tests, not GPU-kernel
execution, cross-platform acceptance or power-cut tests.

Receipts under `target/stdlib-work/` record:

| Group | Process invocations | Scope | Receipt |
| --- | ---: | --- | --- |
| Owner | 9 | Binary/empty/33,798-byte publication, old open reader, vacant NoReplace, anchored parent after rename/replacement and cwd change, keep/cleanup, destination symlink | `atomic-file-owner-group-first.log` |
| Bounds | 25 | Invalid options, names, Views and parents; raw names; zero budgets; recoverable preflights followed by real writes | `atomic-file-bounds-selector-retry.log` |
| Publication | 6 | Retained directory-sync failure/retry, exhausted retry allowance, existing-target conflict and two actual NoReplace contenders | `atomic-file-publication-first.log` |
| Faults | 26 | Two baseline-reached source allocations, write/partial-progress/EINTR/count failures, sync/close/rename failures and unlink recovery | `atomic-file-faults-first.log` |

The total counts process invocations, including overlapping baselines; it is not
66 distinct behaviors. The two allocation sites were measured from the selected
successful binary-publication baseline. Their denial checks are not a claim
about every possible allocation path.

The critical directory-sync case independently observed the complete new
destination, Published receipt and retained anchor **before** allowing recovery.
One explicit retry then made one directory sync with one total rename and no
destination unlink. The two real NoReplace contenders both acquired and wrote
separate temporary files before commit; exactly one published, and the EEXIST
loser could not replace its bytes. The source/descriptor ledger checked acquired
owners and release before process exit, including failed cleanup and explicit
recovery. A real 1,024-byte write prefix followed by EIO agreed with both
Failure.completed and the observed temporary contents.

The first bounds run failed in the oracle: its no-payload-write check counted
the one-byte stderr `W/w` phase markers. Inspection showed zero writes to the
owned file and zero reported attempts/bytes. The corrected selector uses the
captured file descriptor; two added CPU controls distinguish markers from an
actual file write. All 25 cases then passed against the same frozen ELF, with
no production/probe change or compiler rerun. The harness now passes 36 CPU
controls. `atomic-file-bounds-first.log` preserves the initial harness failure.

The Rust AtomicFile and KV test drivers also passed `--no-run` build admission
in `atomic-file-and-kv-test-drivers-build.log`. That build adds no runtime cases.
The [fixture guide](../tests/fixtures/stdlib_execution/atomic_file/README.md)
records exact filters, checkpoints, injections and ownership evidence.

### Preliminary smoke receipt

The first smoke process passed binary six-byte publication, copied destination
storage, recoverable Bounds/ByteLimit preflights, empty writes without a native
write, cached commit without another syscall, an old open reader and a genuine
NoReplace EEXIST conflict followed by cleanup. Receipts under
`target/stdlib-work/` are `atomic-file-smoke-first-compile.log` and
`atomic-file-smoke-native-first.log` (`cases=1`).

This preliminary case overlaps the accepted groups and is not a 67th distinct
case. The current receipts establish the finite profile above; no crash or
power-cut durability claim follows from ordinary process execution.

Independent source review of the frozen implementation found no material
findings in outer write-prefix accounting, recoverable EINTR/preflights,
commit-cache ownership, rename/disarm ordering, sync retry or retained cleanup.
This source review is separate evidence from the executable gates.
