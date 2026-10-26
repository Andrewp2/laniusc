# Bounded archive extraction plan

Status: the selected bounded TAR/ZIP extraction workflow has executable
acceptance on native Linux x86_64, kernel `7.0.0-38-generic`, using ext4 under
`/tmp`. The direct materializer passes 100 process invocations across eleven
groups, including calibrations and overlapping controls. The unpack program
passes 74 invocations in its separate campaign. These are finite receipts for
the contracts below, not completion of the standard and extended libraries.
The earlier AtomicFile/KV and TempFile receipts retain their original scope.

Build one native unpack workflow: read a bounded ustar or classic ZIP archive,
validate its complete entry namespace, then publish regular files into a
caller-selected directory. Reuse the existing archive engines and
[AtomicFile contract](stdlib-atomic-files.md). Initial execution targets native
x86_64 Linux on the explicitly tested local filesystem. Other hosts, network
filesystems and GPU-kernel execution need separate evidence.

## Current source and exact gaps

| Surface | Present behavior | Extraction work |
| --- | --- | --- |
| [`ext::tar`](../extended/ext/tar.lani) | Borrowed ustar headers/data; checked full footer; allocation-free path copying. Its reader preserves unsafe extraction names and several special file kinds. | Consume through `None` before effects; adapt only regular files/directories; apply the policy below. No second tar parser. |
| [`ext::zip`](../extended/ext/zip.lani) | Full structural parse; borrowed cursor; stored/DEFLATE payload extraction with exact length and CRC-32 verification. The raw creator word now survives parsing/cursors without restricting byte-archive acceptance. | Reuse the [strict extraction profile](extended-archive-profile.md) and shared namespace plan. No second ZIP/DEFLATE/CRC implementation. |
| [`std::file_ops`](../stdlib/std/file_ops.lani) | `open_at`, metadata, duplication, sync, NoReplace rename and non-directory removal; checked `create_dir_at`/`remove_dir_at` now pass 55 native cases. | Use one validated component per anchored extraction operation. Automatic directory rollback remains outside this workflow. |
| [`std::directory`](../stdlib/std/directory.lani) | Owned getdents reader and bounded observational walk. Final-component no-follow; raw byte names. | Reuse descriptor/identity rules. Neither a directory listing nor a walk proves that future lookups are safe or unchanged. A whole-tree walk is unnecessary for extraction. |
| [`std::filesystem`](../stdlib/std/filesystem.lani) | Path-based mkdir/rmdir/unlink/rename. | These operations do not supply the anchored component operations needed here; do not use chdir or reconstructed full paths as substitutes. |
| [`std::atomic_file`](../stdlib/std/atomic_file.lani) | In-place writer/publication owner; 66 native process invocations across owner/bounds/publication/fault groups pass on the documented local Linux profile. `create_in`, bounded writes, commit, receipts, explicit directory-sync retry and retained cleanup. | The shared materializer uses NoReplace for every output file and preserves the complete receipt on failures. |

The checked host creation primitive is [implemented and tested](stdlib-directory-at.md):

```text
file_ops::create_dir_at(directory_fd, path, mode) -> Result<i32, io::Error>
```

It stages/validates the complete byte path and mode before one `mkdirat`
attempt, preserves errno, validates the zero success result, and allocates nothing.
The x86_64 call is 258, `(dirfd, path, mode)`. It remains a general relative-path
wrapper like `open_at`; the extractor alone imposes a single-component rule.
Linux permits an existing name to produce EEXIST even when it is a symlink;
EEXIST must never mean "safe directory". Requested permissions are subject to
umask/default ACL behavior. See [Linux mkdirat](https://man7.org/linux/man-pages/man2/mkdir.2.html).

The companion `remove_dir_at` uses existing syscall 263 (`unlinkat`) with
AT_REMOVEDIR=512, rather than the flags=0 file-removal wrapper. It can
remove one empty directory name only. It is useful for a later explicit empty
directory cleanup API, not a reason to add recursive deletion now. See
[Linux unlinkat](https://man7.org/linux/man-pages/man2/unlinkat.2.html).
Both calls fit existing `std::linux::call`; no compiler, extern or ABI work is
needed. The host's `asm/unistd_64.h` supplies the same syscall numbers.

## Archive type profile

This workflow restores file contents and directory structure. It does not apply
archive ownership, permissions, executable bits, timestamps, ACLs, xattrs or
device information. New files request AtomicFile's private 0600; new directories
request 0700. Do not apply archive metadata to existing directories; normal host
mutations can still change their timestamps. The program must
describe this policy in help and report ignored metadata rather than imply a
backup/restore tool.

For TAR, combine `prefix` and `name` using `Entry.copy_path`; use `kind`, not
filename spelling, to classify the entry. Accept Regular and Directory. Reject
HardLink, SymbolicLink, CharacterDevice, BlockDevice, Fifo and Contiguous
explicitly. A directory's size field can be an allocation hint in the existing
ustar profile; it does not authorize reading data records or allocating that
size. Continue to reject all archive extensions rejected by `ext::tar`.
The type distinction and prefix join follow the
[ustar format reference maintained by libarchive](https://github.com/libarchive/libarchive/blob/master/libarchive/tar.5).
The normative format reference remains [POSIX pax/ustar](https://pubs.opengroup.org/onlinepubs/9799919799/utilities/pax.html);
this restricted extractor makes no general pax restoration claim.

For ZIP, interpreting `Entry.external_attributes` also needs the central
header's two-byte "version made by" field. The canonical parser/cursor now
exposes it as `Entry.version_made_by`, preserving all 16 bits.
APPNOTE sections 4.4.2 and 4.4.15
make the attribute representation host-dependent; section 4.4.17 describes the
stored name syntax. See [PKWARE APPNOTE 6.3.10](https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT).

The first ZIP policy is implemented in the
[allocation-free profile adapter](extended-archive-profile.md):

- Support DOS creator 0 and Unix creator 3; reject other creator profiles until
  their attribute semantics have an explicit adapter and tests.
- A terminal `/` marks a directory; a directory entry must declare zero decoded
  bytes and still pass `zip::extract` integrity checks. An empty regular file is
  valid. Empty names are rejected even though the byte archive API allows them.
- For DOS attributes, accept only documented ordinary file/directory attribute
  bits; reject volume-label/reserved bits and unsupported high fields. A set
  directory bit must agree with the directory name form. Zero attributes remain
  valid for the current Lanius writer's files and slash-terminated directories.
- For Unix attributes, inspect the mode's file-type field: zero may use the
  name convention; explicit regular/directory types must agree with it. Reject
  symlink, socket, FIFO, device and unknown types. Reject contradictory DOS
  directory hints too. Permission bits are metadata, never creation authority.
- For both local and central extras, start with an explicit allowlist of ignored
  timestamp/UID/GID metadata and documented Unicode path/comment metadata.
  Reject every other extra ID, including Unix type/link/device extensions
  0x000d and 0x756e. Do not substitute an extra-field path or decode a link target
  into a destination. Unknown extras remain valid in the byte archive API; this
  first filesystem profile rejects them explicitly.

The profile guide freezes exact masks and ignored-extra shapes, with 222
classifications across four native processes. The metadata addition changes
the public Entry layout; focused metadata and existing payload-contract gates
pass, and its consumers were audited. It needs no compiler feature.
Existing archive indexing continues to store
the same snapshot bytes/ordinals unless a separate storage change is approved.

## One path policy for both formats

Validate names before any filesystem mutation. Treat them as length-delimited
bytes. A flagged ZIP UTF-8 name already passes the archive parser's check;
otherwise preserve raw bytes without CP437 conversion or Unicode normalization.
The host profile is Linux byte names, not cross-platform filename equivalence.

The only spelling adjustment is removal of one terminal `/` from a directory
entry. Then require a nonempty relative sequence of components:

- Reject a leading slash, NUL, backslash and drive-style second-byte colon.
- Reject empty components, `.` and `..`; repeated separators are errors, not
  collapsed aliases. Thus `a//b`, `./a`, `a/../b` and `d//` all fail.
- Reject a terminal slash on a regular file. TAR Directory may spell `d` or
  `d/`; both designate the same planned directory.
- Bound total path bytes, component bytes and depth before copying or indexing.
  Initial component maximum is 255 bytes; a smaller host limit remains an error.
- Do not percent-decode, expand variables/tilde, case-fold, strip components or
  resolve a path with realpath. Those transformations could change identity.

The planner owns canonical path bytes and a bounded node table. Include implied
parent directories even if the archive lists a child first. Coalesce an implied
directory with one later explicit directory entry. Reject every duplicate
explicit destination and every file/ancestor conflict, independent of input
order: two `a` files, two explicit `d/` entries, and `a` plus `a/b` all fail
before mutation. There is no first-wins, last-wins or overwrite switch initially.

This is a deliberately strict extraction policy derived from the archive
metadata and Linux name rules. It is not a change to TAR/ZIP interchange parsing.
The byte APIs must keep accepting their currently documented name profiles.

## Anchors, existing objects and mutation authority

The library accepts an already-open ordinary directory File and duplicates its
descriptor. The caller keeps its owner; reject invalid/non-directory/O_PATH
anchors using existing metadata/status queries. The CLI opens its user-selected
root once. Earlier components in that user-selected root path are trusted input;
archive names never participate in that initial lookup.

All descendant traversal uses one validated component per `open_at` with Read,
directory, no_follow and close_on_exec. Create missing directories with one
anchored mkdirat, then open/check the actual resulting directory. On EEXIST,
open it with those same flags; never infer its type from errno or getdents hints.
Do not pass a slash-containing archive path to `open_at`. Linux O_NOFOLLOW only
checks the final component, while a directory descriptor continues to identify
its opened object after rename. See
[Linux openat and O_NOFOLLOW](https://man7.org/linux/man-pages/man2/openat.2.html).

Use a bounded descriptor stack or repeated component walks, with every open,
metadata query, close and traversal step charged. An identity check may detect
a change; it does not lock a name. The selected namespace must be exclusively
owned or cooperatively stable throughout extraction/recovery, including temporary
names. An attacker able to move opened directories or replace children is
outside the contract. Mount topology must also remain stable; the initial test
profile has no nested mounts. No no-mount/sandbox claim follows from comparing
device numbers. A later adversarial-directory design would need its own review;
Linux [openat2 resolution flags](https://man7.org/linux/man-pages/man2/openat2.2.html)
are relevant but are not present in the checked library or required here.

Existing directories may serve as parents. Every regular-file destination uses
AtomicFile NoReplace, so any existing leaf—including a symlink, FIFO, socket,
hard link or regular file—causes an explicit conflict. Do not open/truncate that
leaf or precheck-then-replace it. A supported atomic NoReplace flag is required;
unsupported filesystem/kernel errors do not trigger fallback. See
[Linux renameat2](https://man7.org/linux/man-pages/man2/rename.2.html).
Late conflicts can leave earlier entries published; they are not archive-plan
validation failures.

## Stages, lifetime and partial publication

The implemented layers are [archive_plan](extended-archive-plan.md),
[archive_profile](extended-archive-profile.md),
[archive_source](extended-archive-source.md) and
[archive_extract](extended-archive-extraction.md). Complete archive admission
owns one shared namespace plan; the materializer walks directories and publishes
files. The [unpack program](extended-unpack.md) owns bounded input and reports.
The guides freeze their signatures, ownership and supported target.

1. Read the complete bounded archive and close its input owner before output
   mutation. This supports input/output path overlap without streaming from a
   file that extraction may change. The library may instead borrow a complete
   immutable input view; its backing must physically cover its declared range
   and remain live through all plan/data use. Logical bounds checks cannot prove
   those physical backing/lifetime obligations.
2. Parse all metadata and paths, certify the TAR footer or complete ZIP parse,
   reject unsupported types/duplicates/conflicts, and reserve the namespace,
   status and diagnostic storage. Planning failure has no mutation effects.
3. Process explicit entries in archive order (TAR record order, ZIP central
   order), creating implied parents when needed. For ZIP, decode/check that
   entry before creating its missing parents or temporary file. Retain only
   one decoded payload owner at a time; TAR data stays borrowed.
4. Create an inactive in-place AtomicFile in the opened leaf parent. Set
   NoReplace and finite byte/write/entropy/sync allowances. Call its writer,
   then commit once. Copy its scalar receipt into reserved report storage
   before proceeding. Never infer publication from a bare I/O result.
5. Record each successful directory creation before any subsequent fallible
   open/sync/close. After opening a new directory, sync it and then its opened
   parent before descending or publishing inside it; record both outcomes.
   This includes empty directories. Later child creation syncs its parent again;
   file commit supplies that file's immediate-parent sync. Do not infer the
   durability of preexisting ancestors from these scoped calls.
6. Stop publication at the first failure. Attempt bounded cleanup of the active
   unpublished temporary and all live descriptor owners; preserve the primary
   error and distinct cleanup errors. Do not remove earlier published files or
   created directories. Repeated terminal execution cannot publish again.

ZIP metadata preflight does **not** certify payload CRC/DEFLATE integrity. A bad
later payload can fail after earlier files were committed. TAR's header checksum
does not authenticate payload bytes. Neither checksum establishes a trusted
publisher; this workflow supplies no signing or cryptographic verification.

Use one active manual run owner. Preallocate bookkeeping before effects so an
allocation failure cannot lose a created-directory or publication record.
An AtomicFile failure can still retain temporary backing/anchor ownership; keep
it in that same run owner. Expose explicit cleanup, keep and current-file
directory-sync retry through the existing AtomicFile operations, without
repeating write/rename or continuing extraction after failure. Destruction is
fallible while recovery resources remain. Close a descriptor once and retire
its number before reporting errors, following the existing File ownership rule
and [Linux close](https://man7.org/linux/man-pages/man2/close.2.html).

Reports must identify stage, archive ordinal, canonical path, exact earlier
published files/created directories, confirmed bytes, the current AtomicFile
visibility/receipt, unsynchronized directory records, remaining recovery name,
and first operation plus cleanup errors. Keep reports/paths valid through their
documented owner lifetime. A recovery-name view expires when its retained owner
releases/reuses storage; format/copy it before then. A failed report write cannot
undo filesystem effects or convert them into a successful extraction.

An ordinary success requires every selected file's commit and cleanup to succeed,
all required directory syncs/closes to succeed, and all report owners to remain
usable. Published-but-unsynced and visibility-unconfirmed are distinct failed
outcomes, preserved through cleanup; no automatic rename retry or rollback.
File and directory sync receipts describe actual successful calls on the tested
filesystem, not universal power-loss survival. See
[Linux fsync](https://man7.org/linux/man-pages/man2/fdatasync.2.html).

## Bounds and observability

Freeze explicit defaults/caps with the implementation. A reasonable first CLI
profile is 64 MiB input, 4,096 explicit entries, 4,096 total directory nodes,
16 MiB per decoded file, 128 MiB aggregate decoded data, depth 64, 4,095 bytes
per path and 255 per component. Empty archives/files are valid; invalid signed
limits and checked-arithmetic overflow fail before effects. Exact limits need
boundary tests. Limits count implied directories and repeated traversal work.

Separate budgets rather than advertising one number that omits work:

- Archive bytes, entries and declared/actual decoded totals; inherit ZIP limits.
- Plan node/path/report capacities and peak simultaneous requested source bytes.
  The library's owned-byte cap excludes borrowed input backing; the CLI ledger
  must add its input owner capacity and all other application owners explicitly.
- Planning comparisons/path-byte scans, decoder compressed/output byte caps,
  input-read and namespace/native attempts, writes, entropy attempts, syncs and
  output bytes. Global budgets persist across entries: derive each AtomicFile's
  allowance from the remaining total and charge its actual receipt before the
  next file. Creating a new owner cannot replenish a run's allowance.
- Maximum live directory depth plus the root/current AtomicFile descriptors.
  A full-stack implementation owns at most `1 + max_depth + 2` descriptors:
  root duplicate, child directory stack, and active AtomicFile's parent/file.
  The caller's root/input/standard-stream descriptors are separate. Prove the
  chosen implementation's actual cap. Reserve recovery/cleanup allowances so
  exhaustion cannot suppress cleanup.

Current ZIP `max_work` meters structural parsing, not `extract`'s DEFLATE/CRC
loop; `inflate::decode_into` has no caller-supplied work counter. The initial
workflow can promise finite compressed/output byte bounds and a separately
metered planner/host loop. It must not call that a shared decoder CPU budget.
An interruptible aggregate decoder-work API would require a real metered decoder
or a justified conservative precharge, not an after-the-fact debit. Existing
blocking opens/writes/syncs also prevent a hard wall-clock guarantee.

Record requested source allocation counts/peak live bytes and actual descriptor
generations in focused tests. These exclude native allocator/kernel caches/RSS;
there is no compiler-performance or cross-tool speed claim. A modest unpack
observation can use many small files plus one bounded compressed payload once
correctness gates pass; compilation stays outside its runtime measurement.

## Program boundary

```text
unpack --format tar|zip --root OUTPUT_DIRECTORY [limits] -- ARCHIVE_FILE
```

Choose the format explicitly. The output root must already exist; first-version
input is one regular archive file, read with both byte and attempt limits into
an immutable source owner. An exact-full buffer needs a bounded EOF/extra-byte
check, rather than silently accepting a truncated archive. Reading and closing
input finishes before output mutation; no unbounded EINTR retry helper may
bypass the read-call allowance. FIFOs/devices and streaming stdin are outside
this first input profile.

Expose the documented byte/entry/depth/plan/host-call bounds as flags. Help must
state content-only metadata, NoReplace, cooperative namespace and partial
publication. Machine-readable diagnostics use ordinal plus hex byte paths and
the publication/cleanup outcomes above; raw names cannot inject diagnostic
lines. Reserve report storage before effects. Report after the run, including
failure and live recovery-name information, before releasing that information.
Keep an existing nonzero operation status when diagnostic output also fails;
an output failure after successful publication must itself produce failure.
Freeze exact flags/status codes/report schema with the program owner.

## Focused acceptance sequence

These are the selected acceptance requirements. Their finite passing receipts
are in the module guides and the
[direct owner fixture](../tests/fixtures/extended/archive_materializer/README.md).
The tests use actual compiled Lanius executables; Python/Rust supply fixtures,
independent parsing and host observations. Every command was bounded below two
minutes. The native output is emitted by the GPU compiler; extraction itself
does not run in a GPU compute kernel.

| Gate | Required executable evidence |
| --- | --- |
| Pure plan | Both archive adapters; complete footer/central metadata; raw names, all rejected path/type forms, duplicate/prefix conflicts in either order, implicit/explicit parents, malformed logical views, exact/over limits. Guard output tree unchanged on every planning failure. |
| Checked primitive | mkdirat relative identity, existing directory/file/dangling symlink EEXIST, raw names, bounds/NUL/mode, real errors/invalid counts and allocation-free staging. Parent rename/cwd changes preserve the chosen descriptor identity. |
| Real unpack | Independent Python tarfile USTAR/zipfile inputs plus hand-built raw-name/attribute fixtures; stored/fixed/dynamic DEFLATE, empty files/directories, nested/out-of-order parents, binary bytes and both source views/offsets. Compare final names/types/contents with the independently declared fixture manifest using lstat. |
| Existing objects | Intermediate symlink/non-directory and leaf regular/symlink/FIFO/socket/hard-link conflicts; outside sentinel/alias contents untouched; trace no forbidden leaf open/truncate. Existing directories keep permissions/ownership; no archive metadata setters run. |
| Partial outcomes | First file succeeds then late conflict/CRC/decode failure; fsync-after-rename failure; ambiguous rename; created-directory open/sync failure. Inspect the exact published prefix, retained recovery state and separate primary/cleanup errors before process exit. |
| Faults/ownership | Every reached source allocation position; short write/EINTR/zero/count violations; entropy/open/metadata/sync/rename/close/unlink failures. Prove finite attempts, cached terminal behavior, one-close ownership and actual FD/allocation balance, including explicit recovery retry/keep. Do not label a skipped injected close as a real Linux close. |
| Bounds/program | Depth/entries/implied parents/decoded totals/work/call/report caps; trace actual descriptor cap and requested source memory. CLI help, byte-name diagnostics, exit outcomes, output failure after publication, and one realistic mixed tree. Preserve finite evidence per group. |

Do not implement symlinks/devices, overwrite, recursive rollback, archive metadata
restoration, streaming decoders, gzip/pax/ZIP64/encryption, hostile namespace
containment or whole-directory atomic publication in this increment. These stay
visible future work under the full library roadmap. Sensitive cryptography, if
later required, must use OpenSSL or another established native library.

## Acceptance and remaining work

AtomicFile's accepted checkpoint is committed. The ZIP creator/type addition
and checked directory wrappers have passed source review and focused runtime
gates. The [namespace planner](extended-archive-plan.md) and
[complete source admission](extended-archive-source.md) also execute. Source
admission passes 120 process cases, including eight reached allocation failures;
those source-only receipts remain separate from filesystem extraction. The
[Run contract](extended-archive-extraction.md) records report lifetimes,
directory-sync order, separate cleanup reserves and its eleven passing groups.

The direct groups cover success 12, existing objects eight, partial outcomes
three, bounds 25, allocation halves eight each, namespace nine, sync five,
writes eight, close/rename six and recovery eight: 100 process invocations.
The allocation halves reach all fourteen measured source allocation positions;
their two calibrations are included. Pre-exit ledgers check actual requested
source mappings and descriptor generations. Recovery observes a real three-byte
temporary prefix, preserved primary failure, explicit kept-name transfer and
post-rename directory-sync retry without republication. Skipped injected closes
have explicitly marked harness repairs; they are not real Linux close failures.

The separate CLI campaign has 69 libtest-driven invocations plus five direct
retained-executable input-fault cases. A single additional untraced observation
extracts 273 ZIP entries, including 256 small files and one 2 MiB payload, in
1.653438 seconds. Tree/content validation occurs outside that timer; it includes
startup, input, extraction, synchronization and reporting, excludes compilation,
and makes no compiler-throughput or general performance claim.

Active host-call limits use conservative precharges for opaque AtomicFile calls;
observed write/name/entropy/sync counters settle monotone receipt deltas across
files. Cleanup authority is reserved before acquiring descriptors or an Atomic
owner. A rejected retry cannot consume its existing cleanup lease. Automatic
failure cleanup preserves a published-but-unsynced Atomic anchor for explicit
sync retry; cleanup, keep and recovery-name transfer remain caller decisions.

Both formats now use the same executable host workflow. The selected gates pass
on the recorded target/filesystem, recovery and partial publication remain
inspectable, and the real unpack program is documented. Terminal no-work returns
are explicit state outcomes, never silent placeholder implementations. Other
hosts/filesystems, hostile namespace containment, whole-tree transactions,
rollback, archive metadata restoration, streaming/resumable decoding and broader
formats remain outside this accepted increment. The larger library goal stays
open in the [roadmap](library-roadmap.md#remaining-work-beyond-atomic-files).
