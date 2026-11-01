# pax archives and the tgz tool

`ext::pax` reads and writes POSIX pax extended headers (typeflags `x` and `g`)
on top of the [`ext::tar`](extended-tar.md) ustar profile. Long paths, long
link targets, long owner names, large IDs and fractional modification times
round-trip through it. Like `ext::tar`, it is pure Lanius over borrowed
`core::slice::View<u8>` storage: it allocates nothing, calls no host service
and applies no extraction policy.

[`sample_programs/library/tgz.lani`](../sample_programs/library/tgz.lani) is a
`tar czf` / `tar cJf` / `tar xf` / `tar tf`-style program built on `ext::pax`,
[`ext::compression`](extended-compression.md) (gzip framing, CRC32,
[`ext::deflate`](extended-deflate.md) and [`ext::inflate`](extended-inflate.md)),
[`ext::xz`](extended-xz.md) and the native directory, file and symlink APIs.

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

```text
reader_with(input: View<u8>, options: ext::tar::ReadOptions) -> Result<Reader, Error>
extension_data_len(header: View<u8>, options: ext::tar::ReadOptions)
    -> Result<Option<i32>, Error>
header_len(meta: ext::tar::Metadata) -> Result<i32, Error>
Writer.add_header(meta: ext::tar::Metadata, size: i32) -> Result<i32, Error>
```

`ext::tar::ReadOptions { full_uname, full_gname, gnu, headers_only }`
selects the extensions below; `ext::tar::read_options()` is all false, which
is what `reader` uses. `ext::tar` gains matching `reader_with(input, cursor,
options)`, `writer_at(output, cursor)` and `Writer.add_header(meta, size)`.

- `full_uname`/`full_gname` accept an unterminated 32-byte owner field.
  `ext::pax` sets them itself when a pax record replaces that field; Python's
  tarfile writes such truncated fields for owner names over 31 bytes.
- `gnu` accepts old-GNU magic `ustar  \0` members, GNU base-256 numbers
  (negative values fail) and unterminated 32-byte owner names, and ignores the
  GNU atime/ctime/sparse area where ustar keeps its prefix. In `ext::pax` it also
  accepts GNU `L` (long name) and `K` (long link target) headers, normally
  named `././@LongLink`, whose data is the name followed by NUL padding. GNU
  sparse (`S`), multivolume, volume-label and dump-directory types stay
  `UnsupportedType`.
- `headers_only` parses member headers without requiring their data in the
  view: `Entry.header.data` is empty and the cursor moves past the header
  only. Extension data must still be present. Streaming readers use it with
  `extension_data_len`, which returns the data length that follows an
  `x`/`g` (or, with `gnu`, `L`/`K`) header and `None` for other headers.

`add_header` writes any extension header and the member header for `size`
data bytes; the caller then writes the data and zero padding to the next
512-byte record. `header_len` is the exact byte count `add_header` writes.

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

Two `x` headers in a row, two `L` or two `K` headers for one member, a `g`
header after a member's `x`/`L`/`K` header, and extension headers followed by
the footer return `MisplacedExtension`. `L`/`K` values are applied after any
`x` records before them, matching GNU tar's order. One `g`
header per archive is supported; a second returns `GlobalLimit` instead of a
partial merge. Without `gnu`, GNU long-name headers and old-GNU magic keep
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
tgz (-c|-x|-t) [-z|-J] -f ARCHIVE|- [-C DIR] [PATH...]
```

Short options group, so `tgz -czf out.tgz dir` and `tgz -xzf in.tgz -C dir`
work. `-c` creates from `PATH...` (relative to `-C DIR` when given), `-x`
extracts into `DIR` (default `.`) and `-t` lists one raw member path per line.
`-f -` means stdout for create and stdin for reading. `-z` gzip-encodes on
create; `-J` writes xz, but as stored (uncompressed) LZMA2 chunks with a
CRC64 check, since there is no LZMA encoder yet: the archive is valid xz that
any decoder reads, and it is slightly larger than the tar. Reading detects the
gzip magic `1f 8b` and the xz magic `fd 37 7a 58 5a 00` and decodes whether
or not `-z`/`-J` is given; xz archives from `xz`, `tar -J` and Python
`tarfile` (any preset, CRC32/CRC64/no check, several blocks or streams) are
read through the [streaming xz decoder](extended-xz.md). GNU (`--format=gnu`), pax, ustar and Python tarfile archives are
read; `v7` and GNU sparse archives are rejected.

**Streaming.** Both directions stream through fixed 64 KiB buffers and the
resumable [gzip encoder](extended-streaming-deflate.md) and
[decoder](extended-streaming-inflate.md) or the xz decoder; no archive, decoded tar stream or
member is held in memory. Per-member state is bounded: extension headers
(pax/GNU) up to 1 MiB, the current member's names, and on create the
directory walk snapshot and a hard-link table. Gzip streams are limited to
2 GiB of compressed and decoded data per pass, and single members to 2 GiB.
The xz dictionary grows by doubling up to the stream's declared size, so it
stays near the decoded size for small archives (an 8 MiB `xz -6` window costs
8 MiB only once 4 MiB have been decoded).
A 96 MiB `tgz -czf - | tgz -xzf -` pipeline peaks at 11.6 MiB resident per
process, the same as `tgz --help` forked from the measuring interpreter.

**Validation.** Listing or extracting a named file first streams the whole
archive once to validate headers, gzip CRC32/ISIZE, xz checks and index,
paths and types, and
writes nothing (no listing, no files) when that fails. Reading `-f -` cannot
re-read stdin, so it lists or extracts in one pass and may leave a partial
result before reporting an error later in the stream.

**Create.** Regular files, directories (with one trailing slash) and
symbolic links are stored, recursing through `std::directory::walk` with its
default limits. Other file types return exit 2. Metadata is captured without
following links: permission bits, numeric uid/gid and whole-second mtime.
Owner names are not looked up. A regular file with more than one link whose
device and inode were already archived becomes a hard-link member naming the
first path. A file that shrinks while it is read fails with exit 3; growth is
not included.

**Extract.** Paths lose leading `./` components and trailing slashes. Empty
paths, absolute paths and any `.`, `..` or empty component are rejected as
unsafe, as are absolute symlink targets and hard-link targets that are not
clean relative member paths. Devices, FIFOs and other kinds are unsupported.
For every member:

- each parent below the destination must be a real directory; missing ones
  are created, and an existing symbolic link or non-directory among them is
  refused (exit 2). This also stops an archive that first creates `s -> ..`
  and then writes `s/x`;
- an existing non-directory at the leaf (including a symbolic link) is
  removed first, and regular files are created with `O_CREAT|O_EXCL|O_NOFOLLOW`,
  so nothing is written through a link; an existing directory where a
  non-directory belongs is refused;
- hard links are created with `linkat` without following, and the target
  must be an existing non-directory reached through real directories inside
  the destination;
- regular files get their permission bits (`mode & 0777`) and mtime,
  including pax nanoseconds; directories get `mode & 01777` and mtime after all
  members, deepest first, so later members cannot disturb them. Symbolic-link
  times and ownership are not restored.

The guard checks and the create calls are separate system calls. A concurrent
process that swaps a parent for a link between them is not defended against;
extract into a directory that no one else modifies.

Exit status: 0 success; 2 arguments, format, unsafe path, unsupported type or
limit; 3 I/O; 4 allocation. Each error writes one diagnostic line to stderr.

```sh
target/claude-work/bin/lcc --stdlib-root stdlib --source-root extended \
  -o target/stdlib-work/tgz sample_programs/library/tgz.lani
target/stdlib-work/tgz -czf target/stdlib-work/src.tgz -C docs api
target/stdlib-work/tgz -tzf target/stdlib-work/src.tgz | head
mkdir target/stdlib-work/out
target/stdlib-work/tgz -czf - -C docs api | target/stdlib-work/tgz -xzf - -C target/stdlib-work/out
```

## Oracle evidence

[`tests/fixtures/extended/tgz_oracle.py`](../tests/fixtures/extended/tgz_oracle.py)
drives `tgz` and [`compress-bytes`](extended-compress-bytes.md) against
Python 3.12's `zlib`, `gzip`, `lzma` and `tarfile` and GNU tar 1.35, using one
fixed seed. It is registered as `tests/extended_tgz_execution.rs`, which
compiles both programs and runs the oracle. On 2026-10-31 the oracle ran
directly against executables compiled through `target/claude-work/bin/lcc` and
passed with **4,159 agreeing cases and 0 failures in 102 s**, 690 of them xz. The cargo
wrapper itself was not run. The xz decoder's own oracle is in
[extended-xz.md](extended-xz.md#oracle-evidence).

| Group | Cases |
| --- | ---: |
| Lanius encode, Python decode (raw / zlib / gzip), 72 generated inputs | 72 / 72 / 72 |
| Python encode, Lanius decode: levels 0, 1, 6, 9 and the fixed, Huffman-only and RLE strategies, so stored, fixed and dynamic Huffman blocks (raw / zlib / gzip) | 504 / 504 / 504 |
| Corrupted streams (truncation, bit flips, trailing bytes, random byte writes): both reject | 537 |
| Corrupted streams that Python still accepts: Lanius accepts with identical bytes | 63 |
| Corrupted streams that Python accepts and Lanius rejects | 0 |
| tgz create, Python tarfile reads identical names, types, modes, mtimes, contents, link targets and hard-link groups (plain / gzip / xz), 60 trees | 60 / 60 / 60 |
| tgz create, GNU tar `-xp` extracts the identical tree (gzip / xz) | 60 / 60 |
| tgz list equals Python member names in order | 180 |
| Python pax / GNU-format / ustar create, tgz extracts the identical tree, modes, mtimes and hard links (plain + gzip + xz each) | 180 / 180 / 51 |
| GNU tar `--format=pax` / `gnu` / `ustar` create, tgz extracts the identical tree (plain + gzip + xz each) | 180 / 180 / 36 |
| tgz create, tgz extract (gzip / xz) | 60 / 60 |
| 96 MiB `-czf - \| -xzf -` pipeline identical and under 32 MiB RSS | 1 |
| Destination guard: symlinked parent refused, symlink leaf replaced without following, archive `s -> ../outside` then `s/x` refused, hard link through a symlink refused, hard link to a member shares the inode | 5 |
| Python global pax header with a 300-byte path, 40-byte uname and fractional mtime; hand-built pax records | 1 / 1 |
| Tar header byte flips rejected (21 also rejected by Python, 19 Python tolerates) | 40 |
| Truncated tar rejected (34 also rejected by Python, 6 Python tolerates) | 40 |
| gzip trailer CRC32/ISIZE flips rejected; truncated gzip rejected | 40 / 40 |
| xz-compressed tar: bit flips / truncations / one trailing byte rejected with nothing extracted (Python's incremental decoder returns all data for 1 cut in the index and tolerates all 80 trailing bytes) | 80 / 80 / 80 |
| Unsafe member paths and an absolute symlink target rejected with nothing created | 6 |
| Malformed pax extensions rejected (record length, newline, `=`, uid, negative mtime, `GNU.sparse`, size mismatch, two `x`, trailing `x`, second `g`) | 10 |

Ustar cannot represent 129 of the Python and 144 of the GNU tar
tree/format/compression triples (long names); those are skipped and not counted. Generated trees mix 0
to 70,000-byte files, 90 to 140-byte names and paths over 256 bytes (pax
`path`, GNU `L`), UTF-8 names, nested directories, several permission modes,
hard links across directories and symlinks with targets over 100 bytes (pax
`linkpath`, GNU `K`). The "Python tolerates" rows are deliberate: tarfile
accepts damaged data blocks, short files, `..`/absolute members and pax records
this reader rejects.

Zlib preset dictionaries, an LZMA encoder for `-cJ`, GNU sparse and
multivolume archives, ownership restoration, symlink times and archives over
2 GiB remain open.

Two compiler defects were found and worked around in `tgz.lani`:
`if (f()? != n)` compares incorrectly (bind the value to a local first), and
indexed stores through a multi-element `[i64]` view made with
`typed_slice_from_raw_parts` over a local `[i32; N]` array are lost (store one
word per helper call, as `std::linux` does).
