# pax archives and the tgz tool

`ext::pax` reads and writes POSIX pax extended headers (typeflags `x` and `g`)
on top of the [`ext::tar`](extended-tar.md) ustar profile. Long paths, long
link targets, long owner names, large IDs and fractional modification times
round-trip through it. Like `ext::tar`, it is pure Lanius over borrowed
`core::slice::View<u8>` storage: it allocates nothing, calls no host service
and applies no extraction policy.

[`sample_programs/library/tgz.lani`](../sample_programs/library/tgz.lani) is a
`tar czf` / `tar xzf` / `tar tzf`-style program built on `ext::pax`,
[`ext::compression`](extended-compression.md) (gzip framing, CRC32,
[`ext::deflate`](extended-deflate.md) and [`ext::inflate`](extended-inflate.md))
and the native directory, file and symlink APIs.

Executable evidence covers **x86_64 Linux with native executables produced by
the GPU compiler**. Other targets and GPU-kernel execution are unverified.

## Library API

```text
Error = Tar(ext::tar::Error) | Bounds | InvalidHeader | InvalidRecord
      | InvalidNumber | UnsupportedKey | MisplacedExtension | GlobalLimit
      | SizeMismatch | OutputTooSmall | Finished

reader(input: View<u8>) -> Result<Reader, Error>
Reader.next() -> Result<Option<Entry>, Error>     // None certifies the footer
Reader.position() -> i32
Reader.is_finished() -> bool
Entry { header: ext::tar::Entry, path, has_path, link_name, uname, gname,
        uid, gid, mtime, mtime_nanos, offset }
Entry.path_len() -> i32
Entry.copy_path(output: View<u8>) -> Result<i32, Error>

writer(output: View<u8>) -> Result<Writer, Error>
member_len(meta: ext::tar::Metadata, data_len: i32) -> Result<i32, Error>
Writer.add(meta: ext::tar::Metadata, data: View<u8>) -> Result<i32, Error>
Writer.finish() -> Result<i32, Error>
Writer.position() -> i32
Writer.is_finished() -> bool

apply_records(records: View<u8>, target: &Overrides) -> Result<i32, Error>
empty_overrides(empty: View<u8>) -> Overrides
```

`Entry.header` is the underlying ustar member: kind, mode, size, data range,
device numbers and the raw header fields. The other `Entry` fields are the
effective values after global then per-member overrides. `offset` is the
first extension header that belongs to the member, or the ustar header when
there is none. `path` is a borrowed view into the pax record when `has_path`
is true; otherwise `copy_path` assembles the ustar `prefix/name` path.

`ext::tar` gains two resumption constructors used by this module:
`reader_at(input, cursor, full_uname, full_gname)` and
`writer_at(output, cursor)`. Both require a record-aligned cursor inside the
view. `full_uname`/`full_gname` accept an unterminated 32-byte owner field;
`ext::pax` sets them only when a pax record replaces that field. Python's
tarfile writes exactly such truncated fields for owner names over 31 bytes.
Plain `ext::tar::reader` keeps the strict NUL-terminated rule.

## Reading rules

An `x` header applies to the next member only. A `g` header applies to every
later member. Records are `LEN key=value\n`, where `LEN` is the decimal length
of the whole record. Keys end at the first `=`, so values may contain `=` and
any other byte. Each record must fit in the header data, and its last byte must
be a newline; otherwise `InvalidRecord`. Extension headers need a valid
checksum and `ustar\0` `00` magic, like ustar members. Their padding must be
zero.

| Key | Effect |
| --- | --- |
| `path` | Replaces the assembled ustar path |
| `linkpath` | Replaces the link target |
| `uname`, `gname` | Replace the owner names |
| `uid`, `gid` | Unsigned decimal u64 |
| `mtime` | Nonnegative decimal seconds with an optional fraction; nanoseconds keep the first nine digits and truncate the rest |
| `size` | Must equal the ustar header size, else `SizeMismatch` |
| `GNU.sparse.*` | `UnsupportedKey` |
| anything else | Ignored, as POSIX requires (`atime`, `ctime`, `comment`, `hdrcharset`, vendor keys) |

An empty value (`key=`) removes an earlier override, so the ustar field
applies again. Signs, empty numbers, non-digits and u64 overflow return
`InvalidNumber`; negative times therefore fail. Sizes over the ustar
8 GiB field would also exceed the i32 view range, so `size` never needs to
replace the header value here.

Two `x` headers in a row, a `g` header between an `x` header and its member,
and an `x` header followed by the footer return `MisplacedExtension`. One `g`
header per archive is supported; a second returns `GlobalLimit` instead of a
partial merge. GNU long-name (`L`/`K`), old-GNU magic and sparse members keep
`ext::tar`'s explicit errors. Errors preserve the reader cursor and global
state, so a failing `next()` can be reported without advancing.

## Writing rules

`Writer.add` writes a plain ustar member when every field fits. Otherwise it
first writes one `x` header named `././@PaxHeader` (mode 0644, IDs and time
zero) whose records cover only the fields that do not fit:

- `path` when the path exceeds the 100-byte name and has no valid
  prefix/name split (`ext::tar`'s 256-byte rule);
- `linkpath` over 100 bytes; `uname`/`gname` over 31 bytes;
- `uid`/`gid` over 2,097,151 and `mtime` over 8,589,934,591.

The following ustar header then carries a truncated name/link (first 100
bytes), truncated owner names (31 bytes) and zero for oversized numbers, so
ustar-only readers still see a well-formed member. Mode and device numbers
must still fit their ustar fields, otherwise `ext::tar` errors are returned.
Each text field is limited to 1 MiB and must not contain NUL.

`member_len` gives the exact bytes `add` needs, including extension padding.
`add` checks extension capacity before writing; the ustar member then checks
its own capacity. A failed `add` keeps the cursor, but bytes after it are
unspecified. `finish` writes the two zero records.

## tgz

```text
tgz (-c|-x|-t) [-z] -f ARCHIVE [-C DIR] [--max-bytes N] [PATH...]
```

Short options group, so `tgz -czf out.tgz dir` and `tgz -xzf in.tgz -C dir`
work. `-c` creates from `PATH...` (relative to `-C DIR` when given), `-x`
extracts into `DIR` (default `.`) and `-t` lists one raw member path per line.
`-z` gzip-encodes on create. Reading detects the gzip magic `1f 8b` and decodes
whether or not `-z` is given. `--max-bytes` (default 268,435,456, minimum 2,048)
bounds each input file, the archive file, the decoded tar stream and the
created archive.

Creation stores regular files, directories (with one trailing slash),
and symbolic links, recursing through `std::directory::walk` with its default
limits. Other file types return exit 2. Metadata is captured without
following links: permission bits, numeric uid/gid and whole-second mtime. Owner
names are not looked up. The archive, and its gzip encoding, are built in
memory and written at the end.

Extraction validates the whole archive in a first pass before creating
anything. Paths lose leading `./` components and trailing slashes. Empty
paths, absolute paths and any `.`, `..` or empty interior component are
rejected as unsafe, as are absolute symlink targets. Hard links, devices,
FIFOs and other kinds are rejected as unsupported. The second pass creates
missing parent directories, accepts directories that already exist, writes
regular files with their permission bits and creates symbolic links. Existing
files are truncated and replaced through the path, and symlinks inside the
destination are not guarded against: extract only into a directory you
control.

Exit status: 0 success; 2 arguments, format, unsafe path, unsupported type or
limit; 3 I/O; 4 allocation. Each error writes one diagnostic line to stderr.

```sh
target/release/laniusc --stdlib-root stdlib --source-root extended \
  sample_programs/library/tgz.lani -o target/stdlib-work/tgz
target/stdlib-work/tgz -czf target/stdlib-work/src.tgz -C docs api
target/stdlib-work/tgz -tzf target/stdlib-work/src.tgz | head
mkdir target/stdlib-work/out
target/stdlib-work/tgz -xzf target/stdlib-work/src.tgz -C target/stdlib-work/out
```

## Python oracle evidence

[`tests/fixtures/extended/tgz_oracle.py`](../tests/fixtures/extended/tgz_oracle.py)
drives `tgz` and [`compress-bytes`](extended-compress-bytes.md) against
Python 3.12's `zlib`, `gzip` and `tarfile`, using one fixed seed. It is
registered as `tests/extended_tgz_execution.rs`, which compiles both programs
and runs the oracle. On 2026-10-31 the oracle ran directly against
executables compiled by `target/release/laniusc` and passed with **3,090 agreeing
cases and 0 failures in 28.5 s**. The cargo wrapper itself was not run in this
increment.

| Group | Cases |
| --- | ---: |
| Lanius encode, Python decode (raw / zlib / gzip), 72 generated inputs | 72 / 72 / 72 |
| Python encode, Lanius decode: levels 0, 1, 6, 9 and the fixed, Huffman-only and RLE strategies, so stored, fixed and dynamic Huffman blocks (raw / zlib / gzip) | 504 / 504 / 504 |
| Corrupted streams (truncation, bit flips, trailing bytes, random byte writes): both reject | 537 |
| Corrupted streams that Python still accepts: Lanius accepts with identical bytes | 63 |
| Corrupted streams that Python accepts and Lanius rejects | 0 |
| tgz create, Python tarfile reads identical names, types, modes, contents and link targets (plain / gzip), 60 generated trees | 60 / 60 |
| tgz list equals Python member names in order | 120 |
| Python pax create, tgz extract identical tree (plain / gzip) | 60 / 60 |
| Python ustar create, tgz extract identical tree (plain / gzip); 76 tree/format pairs ustar cannot represent are skipped | 22 / 22 |
| tgz create, tgz extract | 60 |
| Python GNU-format archives rejected before any file is created | 120 |
| Python global pax header with a 300-byte path, 40-byte uname and fractional mtime | 1 |
| Hand-built pax records: path, nine-digit fractional mtime, uid and an empty-value deletion | 1 |
| Tar header byte flips rejected (16 also rejected by Python, 24 Python tolerates) | 40 |
| Truncated tar rejected (29 also rejected by Python, 11 Python tolerates) | 40 |
| gzip trailer CRC32/ISIZE flips rejected; truncated gzip rejected | 40 / 40 |
| Unsafe member paths and an absolute symlink target rejected with nothing created | 6 |
| Malformed pax extensions rejected (record length, newline, `=`, uid, negative mtime, `GNU.sparse`, size mismatch, two `x`, trailing `x`, second `g`) | 10 |

Generated trees mix 0 to 70,000-byte files, 90 to 140-byte names and paths
over 256 bytes (pax `path`), UTF-8 names, nested directories, several
permission modes and symlinks with targets over 100 bytes (pax `linkpath`).
The six "Python tolerates" rows are deliberate: tarfile accepts damaged data
blocks, short files, `..`/absolute members and pax records this reader rejects.

Zlib preset dictionaries, GNU tar formats, sparse files, hard links, ownership
restoration, mtime restoration and streaming (not whole-archive) tar I/O remain
open.
