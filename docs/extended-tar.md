# Borrowed ustar archives

`ext::tar` reads and writes a documented POSIX ustar byte profile in Lanius.
Its executable target is x86_64 Linux. Parsing, metadata access, path copying,
member writing and finalization allocate no heap storage. The module performs
no filesystem extraction, link following, ownership lookup or path rewriting.

```lanius
let archive: ext::tar::Reader = core::result::unwrap(ext::tar::reader(input));
let item: core::option::Option<ext::tar::Entry> =
    core::result::unwrap(archive.next());

let out: ext::tar::Writer = core::result::unwrap(ext::tar::writer(output));
let meta: ext::tar::Metadata = ext::tar::metadata(path,ext::tar::Kind::Regular);
core::result::unwrap(out.add(meta,file_bytes));
let length: i32 = core::result::unwrap(out.finish());
```

All byte arguments are `core::slice::View<u8>`. Copies of readers, writers,
metadata and entries alias their borrowed storage. Backing storage must live
for every use and cover each declared range. Signed logical metadata and
overflow are checked; physical backing and lifetime are caller obligations.
Native strided arrays and nonzero offsets are supported.

## Supported profile

Records are 512 bytes. Each member has one header followed by its data and
zero-filled record padding. Header magic is exactly `ustar\0`, version is
exactly `00`, and the twelve reserved header bytes are zero. Checksums use
unsigned header bytes, with the checksum field treated as eight spaces.
Signed historical checksums are not accepted.

| `Kind` | Type byte | Data records |
| --- | --- | --- |
| `Regular` | `0`, or NUL when reading | File bytes |
| `HardLink` | `1` | None; nonempty link name and size zero |
| `SymbolicLink` | `2` | None; nonempty link name and size zero |
| `CharacterDevice` | `3` | None; device metadata only |
| `BlockDevice` | `4` | None; device metadata only |
| `Directory` | `5` | None |
| `Fifo` | `6` | None |
| `Contiguous` | `7` | File bytes |

Unknown types, pax `x`/`g` headers, GNU long-name/link/sparse headers, old/GNU
magic and base-256 numbers return explicit errors. Types are never guessed or
converted into regular files. Device and FIFO sizes are preserved as metadata
and do not imply data records. A directory's size is preserved as its POSIX
allocation hint. The writer emits size zero for every type without data.

Paths and links are opaque non-NUL bytes, including non-UTF8 bytes. This is
the profile's byte-preserving interchange encoding; it performs no character
conversion. `name` and `prefix` remain separate borrowed fields. A nonempty
prefix forms `prefix + '/' + name`; otherwise the path is `name`. Repeated
slashes, leading slashes, dot components and parent components retain their
spelling. This module imposes no extraction policy on those names.

Fields `name`, `prefix` and `link_name` may fill all 100, 155 and 100 bytes,
respectively. Otherwise the first NUL terminates the field, and every byte
after it must be zero. User and group names must have a NUL terminator, so
their maximum length is 31 bytes. Both links require a nonempty target;
other kinds require an empty link field. The combined path must be nonempty.
An empty `name` with a nonempty prefix can represent a trailing slash.

Numeric fields accept octal digits followed by NUL/space terminators, with
optional leading spaces. A field containing only NULs/spaces means zero;
this includes Python tarfile's unused device fields. Embedded junk, signs,
base-256 numbers and unterminated digit fields fail. Values are bounded to
12 mode bits, 7 octal digits for IDs/device numbers and 11 for size/time.
Negative or fractional times require a different archive format.

## Reader contract

| API | Result |
| --- | --- |
| `reader(input) -> Result<Reader,Error>` | Validate logical input metadata and construct a cursor. |
| `Reader.next() -> Result<Option<Entry>,Error>` | Yield a fully checked header and complete data range, or certify the footer with `None`. |
| `Reader.position() -> i32` | Next header offset; after valid footer, the complete input length. |
| `Reader.is_finished() -> bool` | True after footer and trailing-padding validation. |
| `Entry.path_len() -> i32` | Length of the assembled path. |
| `Entry.copy_path(output) -> Result<i32,Error>` | Copy the exact assembled path, without a terminator. Capacity/bounds failure writes nothing. |

`Entry` exposes borrowed `name`, `prefix`, `link_name`, `uname`, `gname` and
`data`; `kind`; `mode: u32`; `uid`, `gid`, `size`, `mtime`, `dev_major` and
`dev_minor: u64`; and `offset: i32`. Its views retain the source stride and
refer to the original input. These structs should be obtained from the
constructors; modifying their representation can invalidate their contracts.

Each failed `next()` leaves the cursor unchanged and the input untouched.
An entry is yielded only after its entire data and zero padding are present.
The cursor can be retried after repairing the same backing bytes. A declared
data length beyond the signed view-count range returns `CapacityOverflow`.
This is an in-memory reader, without incremental stream state.

End of input alone is `MissingFooter`. A complete terminator requires two
consecutive all-zero records. Additional complete all-zero records are
accepted, including normal 10240-byte tar blocking. Nonzero trailing records
return `TrailingData`; an incomplete trailing record returns `UnexpectedEof`.
A single zero record or a zero record followed by a nonzero record is
`MissingFooter`. The stricter zero-padding policy rejects opaque nonzero tape
padding and concatenated archives. Once complete, `next()` is fused and
returns `None` again. To validate an archive, consume through that result;
reading only its first entry does not validate later entries or the footer.

## Writer contract

`metadata(path,kind)` creates `Metadata` with empty link/user/group names,
zero IDs/time/device numbers and mode `0644` (`0755` for directories).
Its public fields are `path`, `link_name`, `uname`, `gname`, `kind`,
`mode: u32`, and `uid`, `gid`, `mtime`, `dev_major`, `dev_minor: u64`.

| API | Result |
| --- | --- |
| `writer(output) -> Result<Writer,Error>` | Construct an empty writer in caller storage. |
| `Writer.add(metadata,data) -> Result<i32,Error>` | Append one complete member; return the new total length. |
| `Writer.finish() -> Result<i32,Error>` | Append two zero records; return total archive length. Repeated success is idempotent. |
| `Writer.position()`, `is_finished()` | Current initialized prefix and finalization state. |
| `Writer.rebind(output) -> Result<bool,Error>` | Switch to grown/copy-preserved storage after checking its entire existing prefix is identical. |

The writer derives sizes from data. Only regular/contiguous members accept
nonempty data. Path lengths through 100 use `name` alone. Longer paths split
at the last slash that leaves a prefix of at most 155 bytes and a name of at
most 100 bytes. No normalization occurs. Unsplittable or over-256-byte paths
fail. Numeric output is deterministic, zero-padded octal followed by NUL;
the checksum uses six octal digits, NUL and space. All padding is zero.

Every failed `add`, `finish` or `rebind` preserves output, cursor and
finalization state. Validations and capacity checks precede writes. To retry
after capacity failure, provide a larger buffer containing the same existing
prefix and call `rebind`; the library does not allocate or copy that prefix.
Keep both the old and replacement storage live until `rebind` succeeds; only
then release the old storage. Growing an owner that invalidates the old view
before this check violates the borrowed-storage contract.
Adding after successful finalization returns `Finished`.

Metadata/data sources must not overlap the appended output region, and
`copy_path` output must not overlap its borrowed name/prefix sources. These
alias conditions are caller obligations. Existing writer prefix bytes are
never modified by append/finalization. The output tail beyond `position()`
is unchanged, including bytes after a successful footer.

## Errors and verification

Errors distinguish `Bounds`, `UnexpectedEof`, `MissingFooter`,
`InvalidChecksum`, `UnsupportedFormat`, `InvalidNumber`, `NumberOverflow`,
`InvalidName`, `UnsupportedType`, `InvalidSize`, `InvalidPadding`,
`TrailingData`, `PathTooLong`, `LinkTooLong`, `NameTooLong`,
`CapacityOverflow`, `OutputTooSmall`, `Finished` and `InvalidState`.
For a reader error, `position()` identifies the unchanged offending record.

Focused executable tests are in `tests/extended_tar_execution.rs` and the
`tests/fixtures/extended/tar_*.lani` programs. All six groups passed together
in 13.00 seconds. They exercise both directions
with Python tarfile USTAR archives, every supported kind, raw byte names,
256-byte paths, full-width links, maximum IDs/times, zero and extra footer
records, numeric/string rejection and every truncated prefix of a member
archive. Deterministic generated archives cover record boundaries and data
through 131073 bytes. Atomic failures compare the entire output buffer,
including existing prefix and untouched tail. Additional native-array
programs check negative byte strides and offsets. Every executable runs with
allocation syscalls traced and `mmap` forced to fail; successful traces are
empty. Python and Rust supply references and drivers only.

```sh
timeout --kill-after=2s 100s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 \
  CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --locked --test extended_tar_execution -- --nocapture
```

GPU-kernel execution has not been established. Large native byte-array
repeat expressions still have the existing compiler limitation described in
the library dependency inventory; packed i32 backing or an explicit native
array literal avoids it. No compiler or runtime changes were needed.

Sources: [POSIX.1-2024 pax, ustar interchange format](https://pubs.opengroup.org/onlinepubs/9799919799/utilities/pax.html)
and [FreeBSD tar(5)](https://man.freebsd.org/cgi/man.cgi?query=tar&sektion=5).
