# Positional file I/O

This increment adds allocation-free explicit-offset contracts in `core::io`
and a Linux descriptor adapter in `std::file_ops`. The
[fixed plan](library-positional-io-plan.md) defines the selected interface.
Portable contracts, the independent schedule model and native adapter gates
pass. The real file-patch application passes all four groups/82 process cases,
and selected old stream/FileOps regressions pass separately. This selected
increment is accepted on the finite native profile below.
Earlier stream and file receipts retain their original source/API scope;
the whole library goal remains open.

## Portable contracts

```lani
pub trait ReadAt {
    pub fn read_at(&self,destination:[u8],offset:i32,count:i32,position:u64)
        -> core::result::Result<i32,Error>;
}
pub trait WriteAt {
    pub fn write_at(&self,source:[u8],offset:i32,count:i32,position:u64)
        -> core::result::Result<i32,Error>;
}
pub fn valid_position(position:u64,count:i32) -> bool;
pub fn read_exact_at<R>(reader:&R,destination:[u8],offset:i32,count:i32,
    position:u64,max_attempts:i32) -> core::result::Result<i32,Failure>
    where R:ReadAt;
pub fn write_all_at<W>(writer:&W,source:[u8],offset:i32,count:i32,
    position:u64,max_attempts:i32) -> core::result::Result<i32,Failure>
    where W:WriteAt;
```

Array `offset` and file `position` are separate byte coordinates. Each trait
operation uses the supplied file position and leaves the receiver's shared
file cursor unchanged. Successful counts are in `0..=count`; short transfers
are normal. A nonempty read returning zero means EOF. An error acknowledges
no completed bytes for that call.

`valid_position` checks the whole positional span without reading backing:

```text
MAX = 9223372036854775807
count >= 0 && position <= MAX && count <= MAX - position
```

The exclusive end must fit this signed-64-bit file-length domain. An empty
request may start at MAX; a nonempty request there is invalid. This check
does not promise that a filesystem supports that size or position.

Exact/all helpers also require a valid logical array range:
`offset >= 0`, `count >= 0` and `offset + count <= i32::MAX`. They validate
both complete spans and a nonnegative attempt budget before any callback.
Invalid input returns `Failure { cause:InvalidInput, completed:0 }`, including
for empty input. Physical backing, initialized bytes and lifetime remain
caller obligations.

## Bounded progress and failure

`max_attempts` counts trait calls, including calls returning `Interrupted`.
It is not a syscall count or wall-clock deadline. A valid empty operation
returns zero without calling the receiver, even with zero attempts. A
nonempty operation with zero attempts returns `LimitExceeded`.

After a successful short count, the next call receives:

```text
array offset = original offset + completed
file position = original position + completed
count = original count - completed
```

Admission of the original full spans makes those increments representable.
Completion returns the requested count without an extra receiver call.

| Observation before completion | Result |
| --- | --- |
| `Interrupted` | Spend the attempt and retry the same uncompleted range |
| `WouldBlock` or another error | Return that error and the confirmed prefix |
| Count outside `0..=remaining` | `InvalidCount`; exclude that call from completed |
| Read returns zero | `UnexpectedEof` |
| Write returns zero | `WriteZero` |
| No attempts remain | `LimitExceeded` |

`Failure.completed` uses the existing stream failure record and counts only
confirmed positive transfers. Earlier read bytes or writes remain in place;
there is no rollback. An invalid count cannot establish the failing call's
actual effects. Source/callback work and termination are outside the helper's
call budget. Helpers add no allocation, flush, synchronization, close or owner
retirement.

## Linux File adapter

```lani
pub const POSITIONAL_CHUNK_BYTES:i32 = 1024;
pub fn read_at(file:&File,destination:View<u8>,position:u64)
    -> Result<i32,Error>;
pub fn write_at(file:&File,source:View<u8>,position:u64)
    -> Result<i32,Error>;
```

These free functions belong to `std::file_ops`. That module also provides
`ReadAt` and `WriteAt` implementations for `std::file::File`; import
`std::file_ops` when using the portable helpers with a File. The operation
borrows a single manual descriptor owner without seeking, duplicating or
transferring cleanup authority.

Admission checks the full View metadata and positional span before checking
the owner. The complete requested length is checked before the 1024-byte
transfer clamp; a valid staged prefix cannot admit an invalid full span.
Negative start/length and overflowing logical ends return
`InvalidInput`. A closed File returns `Host(9)`. A valid empty call on a live
File returns zero without host calls; it does not inspect status flags or
access mode. An empty portable helper does not dispatch to this adapter at
all, so its zero result alone does not validate a File owner.

For a nonempty request the adapter reads status with `F_GETFL`, then applies
these policies before any transfer:

| Flag | Read | Write |
| --- | --- | --- |
| `O_DIRECT` (16384) | `InvalidInput` | `InvalidInput` |
| `O_APPEND` (1024) | Permitted | `InvalidInput` |

The Linux [pread/pwrite contract](https://man7.org/linux/man-pages/man2/pread.2.html)
preserves the open-file cursor and permits short transfers. Linux pwrite can
append despite an explicit offset when O_APPEND is set; rejecting append
writes preserves the promised position. Packed stack staging does not supply
direct-I/O alignment. The adapter does not change either flag.

After status validation there is at most one `pread64` (syscall 17) or
`pwrite64` (18), transferring at most 1024 bytes. Write bytes are packed from
the selected native stride into contiguous stack storage. Reads go to private
stack storage; only a valid successful count publishes bytes to the selected
destination prefix. Host errors and malformed read counts leave destination
bytes untouched. Successful short counts and EOF return unchanged.

`EINTR` maps to `Interrupted`, `EAGAIN` to `WouldBlock`, and other errno values
to `Host(errno)`. Neither status checks nor transfers retry or fall back.
Access-mode errors, nonseekable descriptors, filesystem size/space limits and
other host restrictions remain explicit host errors. Portable exact/all
helpers can make repeated bounded adapter calls to cross the staging limit.

Duplicates share status flags and the open-file cursor. Callers must prevent
concurrent close/replacement and status-flag mutation through every alias or
duplicate during an operation. The status check is not synchronization.
Positional access supplies no transaction, compare-and-swap, implicit flush,
crash durability or file lock. Concurrent changes to file contents remain
caller/host policy. See [descriptor operations](stdlib-file-operations.md).

## Compiler expression boundary

The [retained comparison/cast reproduction](../tests/fixtures/stdlib_compiler_state/filesystem_imports/README.md)
documents one ambiguous count guard. The inline form
`received<0 || received>(requested as i64)` can be parsed as a generic
application, producing a standalone syntax diagnostic. In a complete imported
module, the fallback can instead label an unrelated Iterator bound; this
does not establish a generic-bound restriction.

The positional adapter uses the same established disambiguation: widen the
requested amount into an `i64` local, then compare against that identifier.
Validation still precedes destination copying, and syscall/API/error behavior
is unchanged. This library expression change does not repair the compiler.

## Verification and target

| Accepted gate | Observation | Receipt under `target/stdlib-work/` |
| --- | --- | --- |
| Portable contracts, two tests | One scripted native executable with no memory or host-I/O services; two source-local missing-capability rejections | `positional-io-portable-first.log`, 7.01s |
| Independent portable model, one test | 11,012 cases / 6,836 provider calls / 652 failures after progress, both directions and two byte layouts, seed `0xa71020261030` | `positional-io-model-first.log`, 4.38s |
| Native adapter, five tests | Four native fixture groups plus one CPU trace-parser check; 30 fault schedules with 24 reached injections | `positional-io-native-gates.log`, 13.11s |
| Focused amended native contract, one existing test | Both physically backed 1025-byte requests at MAX−1024 reject before status/transfer; full span checked before staging clamp | `positional-io-native-contract-final.log`, 7.74s; other native tests filtered |
| File-patch application, four tests across two runs | Model24 + CLI35 + preservation6 + I/O17 = 82 unique process cases | `positional-io-file-patch-model-first.log`, 7.18s; `positional-io-file-patch-boundaries.log`, 7.57s, model filtered |
| Selected old stream regression, one test | Two native fixtures exercise existing partial-progress/failure behavior | `positional-io-stream-regression.log`, 11.34s; three unrelated tests filtered |
| Selected old FileOps regression, one test | Existing descriptor behavior executes against the final typed-local production module | `positional-io-file-ops-regression-final.log`, 7.12s |

The [portable contracts](../tests/fixtures/stdlib_foundation/positional_io/README.md)
cover four scenario functions, fifteen admission configurations in both
directions, twelve failures after a prefix and two byte layouts. The
[independent model](../tests/fixtures/stdlib_foundation/positional_io_model/README.md)
compares complete provider transcripts, bytes, errors and progress under
budgets `-1..=8`; its maximum observed call count is eight. This is portable
provider evidence, separate from host pread/pwrite and cursor preservation.

The [native driver](../tests/stdlib_file_positional_execution.rs) checks
ascending packed and descending native byte buffers, nonzero View starts,
exact helpers across 1024 bytes, sparse offset 4,294,967,311, unchanged shared
duplicate cursors, append/access/pipe/closed-owner policies and injected
status/transfer results. The actual O_DIRECT rejection branch executes on the
accepted host, without the filesystem-declined branch. Observed native
processes add no allocation or automatic synchronization calls. An initial
native contract exited zero but its Rust trace parser rejected aligned
whitespace; a driver-only parsing correction precedes the final five passes.

The five-test native receipt used contract fixture `6fcd487`. The final
focused receipt reruns that existing test with fixture `dd12564d`, adding
the full-span-before-clamp assertions in both directions. The four other
test identities retain their earlier passing receipt. There are five unique
native-driver tests across these receipts; the focused row adds boundary
coverage to the same native contract.

The bounded
[file-patch program](stdlib-file-patch.md) reads/compares expected bytes before
positional writes. Its matching check and replacement are not atomic, and
write failure may publish a prefix. Its four accepted groups contain
82 unique process cases across the two disjoint receipts above, separate
from portable model cases and native fault schedules. Argument snapshots
retain their own explicit allocation/cleanup policy; stack payload staging
does not make the entire application allocation-free. The selected old
regressions have separate scopes; no full old stream/FileOps suite was rerun.

Accepted production SHA-256 identities:

| Source | SHA-256 |
| --- | --- |
| `stdlib/core/io.lani` | `cd9edded4e607a9e85b97c5bcae8243bcbe0660a59af4411ada24c3d04fb8ee1` |
| `stdlib/std/file_ops.lani` | `f01be8a2747ae8845dda002c1d17eeb7b775188b40ca101b603dda32c9f3ca83` |

The core contracts contain no host dependency. The selected native target is
Linux x86_64 CPU output from the GPU compiler. Other targets, GPU device
execution, automatic lifetimes and formal proofs are unclaimed. Existing
stream/file regressions require their own current receipts; earlier evidence
does not establish these new APIs.
