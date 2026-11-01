# Streaming ZIP records and the zip tool

`ext::zip_stream` reads and writes ZIP records one at a time with u64
offsets: the end of central directory record with its ZIP64 end record and
locator, central directory headers, local headers, ZIP64 and
extended-timestamp extras, and data descriptors. It is pure Lanius over
borrowed `core::slice::View<u8>` storage. It allocates nothing, calls no host
service, compresses nothing and applies no extraction policy. Archives of any
size therefore stream through fixed buffers.

[`ext::zip`](extended-zip.md) is the other ZIP module. It parses and encodes
whole classic archives held in one view, with i32 sizes, and rejects ZIP64.
Use `ext::zip_stream` for archives that do not fit in memory, for ZIP64, and
for writing to pipes.

[`sample_programs/library/zip.lani`](../sample_programs/library/zip.lani) is
a `zip`/`unzip`-style program built on `ext::zip_stream`, the raw
[`ext::deflate`](extended-deflate.md) levels,
[`ext::inflate`](extended-inflate.md), `ext::compression.crc32_update` and the
native file, directory and symlink APIs.

Executable evidence covers **x86_64 Linux with native executables produced by
the GPU compiler**. Other targets and GPU-kernel execution are unverified.

## Library API

```text
Error = Bounds | Truncated | Signature | Corrupt | Zip64 | OutputTooSmall
LOCAL_LEN = 30   CENTRAL_LEN = 46   END_LEN = 22   LOCATOR_LEN = 20
ZIP64_END_LEN = 56   STORED = 0   DEFLATED = 8   MADE_BY_UNIX = 813
FLAG_ENCRYPTED = 1   FLAG_DESCRIPTOR = 8   FLAG_UTF8 = 2048

// Reading
end_search_len() -> i32                              // 65577
find_end(tail: View<u8>, tail_offset: u64) -> Result<End, Error>
read_zip64_end(end: End, record: View<u8>) -> Result<End, Error>
central_entry(directory: View<u8>, at: i32) -> Result<Entry, Error>
local_header(bytes: View<u8>) -> Result<Local, Error>
modified(directory: View<u8>, entry: Entry) -> i64
unix_seconds(time: i32, date: i32) -> i64

End { entries: u64, central_offset: u64, central_size: u64, end_offset: u64,
      comment_length: i32, has_zip64: bool, zip64_offset: u64 }
Entry { version_made, version_needed, flags, method, dos_time, dos_date: i32,
        crc: u32, compressed: u64, size: u64, local_offset: u64,
        internal: i32, external: u32, name_start, name_length, extra_start,
        extra_length, comment_length, next: i32 }
Local { version_needed, flags, method: i32, crc: u32, compressed: u64,
        size: u64, name_length, extra_length, header_length: i32 }

// Writing
Member { name: View<u8>, method: i32, dos_time: i32, dos_date: i32,
         external: u32, zip64: bool, utf8: bool, mtime: i64 }
local_len(member) -> i32
write_local(output: View<u8>, member: Member) -> Result<i32, Error>
descriptor_len(zip64: bool) -> i32
write_descriptor(output, crc: u32, compressed: u64, size: u64, zip64: bool)
    -> Result<i32, Error>
central_len(member, compressed: u64, size: u64, offset: u64) -> i32
write_central(output, member, crc: u32, compressed: u64, size: u64, offset: u64)
    -> Result<i32, Error>
end_len(entries: u64, central_offset: u64, central_size: u64, force_zip64: bool) -> i32
write_end(output, entries, central_offset, central_size, force_zip64)
    -> Result<i32, Error>
dos_time(seconds: i64) -> DosTime          // DosTime { time: i32, date: i32 }
```

Each writer returns the bytes written, which always equal the matching
`*_len` value. An output view shorter than that is `OutputTooSmall`, and
nothing is written. A negative view start or length is `Bounds`.

`ext::compression` gains `crc32_update(state: u32, bytes: View<u8>) -> u32`,
the CRC-32 that gzip and ZIP use. Start from `core::crc32::INITIAL` and end
with `core::crc32::finish`. Packed spans of 2 KiB or more use slicing-by-8.

## Reading rules

A reader passes the archive's last `min(size, end_search_len())` bytes to
`find_end` with their absolute offset. `find_end` searches backward. It
takes the first end record whose comment length reaches exactly the end of
the archive, so an end signature inside a comment is not mistaken for the
record. It returns:

- `Signature` when there is no such record;
- `Corrupt` for disk numbers other than zero, or per-disk counts that differ
  from the totals;
- `Corrupt` when the central directory does not end exactly where the end
  records begin. This rejects data prepended to the archive, such as a
  self-extractor stub.

When the 20 bytes before the record are a ZIP64 locator, `has_zip64` is set
and `zip64_offset` names the ZIP64 end record. The caller reads its
`ZIP64_END_LEN` bytes and passes them to `read_zip64_end`. That function
requires a signature (else `Zip64`), a size field that ends the record
exactly at the locator, disk zero, and equal per-disk and total counts. It
then replaces the entry count, central size and central offset. The central
directory must again end where the ZIP64 end record starts. A classic record
that holds the ZIP64 marker values (0xffff or 0xffffffff) without a locator
is `Zip64`.

`central_entry(directory, at)` parses the header at offset `at` of a view
holding the whole directory. Name, extra and comment are offsets into that
view, and `next` is the following header's offset. The fixed fields are
checked against the view (`Truncated`), along with the signature
(`Signature`) and disk zero (`Corrupt`). The ZIP64 extra (id 1) supplies
size, compressed size and local header offset, in that order, but only for
fields stored as 0xffffffff. A needed value the extra does not hold is
`Zip64`. An extra record that runs past the extra area is `Corrupt`. A tail
of fewer than four bytes is ignored, which matches the alignment padding
some writers add.

`local_header` parses the fixed 30 bytes. `header_length` includes the name
and extra, so a member's data starts `header_length` bytes after its local
header. When flag 8 is set, the local CRC and sizes are zero and the central
values apply. `modified` returns the extended-timestamp extra's (0x5455)
modification time when there is one. Otherwise it reads the DOS fields as
UTC, where a zero month or day reads as 1.

## Writing rules

Every member written has flag 8: its CRC and sizes come after the data, in a
data descriptor (signature, CRC, then 4-byte sizes, or 8-byte sizes when the
member is ZIP64). An archive can therefore go to a pipe in one pass.
`Member.zip64` gives the local header 0xffffffff sizes and a zeroed ZIP64
extra; set it when the data might reach 4 GiB. In the central header, a
value moves to the ZIP64 extra when it is 0xffffffff or more, or when the
member is ZIP64 (then all three move). The version needed is 10 for stored,
20 for deflate and 45 for anything ZIP64. The version made by is Unix,
APPNOTE 4.5. Names over 65,535 bytes are `Bounds`. Flag 2048 marks UTF-8
names.

When `0 <= mtime < 2^31`, both headers carry an extended-timestamp extra with
the exact UTC modification time. Info-ZIP's `unzip` prefers it over the DOS
fields. `dos_time` converts Unix seconds to DOS fields in UTC and clamps to
1980-01-01 and 2107-12-31. zipfile and Info-ZIP write local time in the DOS
fields instead, so archives that lack the timestamp extra show their DOS
times shifted by the reader's UTC offset.

`write_end` writes the ZIP64 end record and locator before the classic end
record when there are 65,535 or more entries, or when the directory's offset
or size reaches 0xffffffff, or when `force_zip64` is set. The classic fields
then hold the marker values. The archive comment is empty.

## The zip tool

```text
zip -c [-L 0-3 | -0] [--zip64] -f ARCHIVE|- [-C DIR] PATH...
zip -t -f ARCHIVE          # verify every member, then print names
zip -x -f ARCHIVE [-C DIR] # verify every member, then extract
```

Creating walks each path in order, as `tgz` does. It writes directories
(with a trailing `/` and the MS-DOS directory attribute), regular files and
symbolic links, the last stored with their target as data in Info-ZIP's
form. Other file types return the unsupported error. Members are deflated
at level 2 by default. `-L 0` selects the default fixed-block encoder and
`-L 1`-`3` the [dynamic Huffman levels](extended-streaming-deflate.md#dynamic-huffman-levels).
Empty files, directories, links and every member under `-0` are stored.
Files of 3.5 GiB or more get ZIP64 local headers automatically, since their
deflate output could pass 4 GiB. `--zip64` forces ZIP64 headers and end
records for every member. Output streams through 64 KiB buffers. Only one
fixed-size record and the name per member stay in memory.

Reading needs a seekable file; `-f -` is a usage error. The tool reads the
end records and the whole central directory (at most 512 MiB). It then makes
a verifying pass over every member before it lists or writes anything. For
each member it:

- rejects encryption flags (1, 64, 8192), patched data (32), versions newer
  than 6.3 and methods other than stored and deflate;
- requires the stored size to equal the compressed size;
- checks that the local header matches the central name and method;
- refuses members that overlap the next local header (found by sorting the
  offsets) or that share a local header;
- decodes the data. A deflate stream must use exactly the compressed size
  and produce exactly the declared size, and the CRC-32 must match.

Extraction uses `tgz`'s path guard. Names lose a leading `./` and trailing
`/`. Absolute names, empty components, `.`, `..`, backslashes and NUL are
refused. A parent that is already a symbolic link or a file is refused, and
an existing non-directory leaf is replaced, never followed. Files are
created exclusively with `O_NOFOLLOW`. Symbolic link members need a
relative target of at most 4 KiB. Modes come from Unix external attributes,
and other creators get 0644 or 0755. Times come from `modified`. Directory
modes and times are applied last, deepest first. Validation that depends on
the filesystem (an archive symlink followed by a member beneath it) is
caught during extraction, so earlier members may already exist then.

Exit status is 0 on success; 2 for arguments, format, unsafe names,
unsupported members, CRC mismatches and limits; 3 for I/O; 4 for
allocation.

## Executable evidence

`python3 -I tests/fixtures/extended/zip_oracle.py ZIP WORKDIR` (seeded, about
65 s) passes **8,662 cases with 0 failures** against Python 3.12 `zipfile`
and Info-ZIP `unzip` 6.0:

| Group | Cases | What agrees |
| --- | ---: | --- |
| Sample writes | 40 trees × 3 checks | `zipfile` reads every name, kind, byte, mode, link target and DOS time at the default level, `-L 0`-`3`, `-0` and `--zip64`, to files and to pipes. Every member has a descriptor, ZIP64 versions appear exactly when forced, and the methods are as described. `unzip -t` accepts all 40. The sample's own extraction restores data, modes, links and mtimes. |
| zipfile writes | 60 archives × 2 | Stored and deflate members at compress levels 0-9, empty members, directories and UTF-8 names. Archives are written seekable or streamed (so they have data descriptors), plain or with `force_zip64`, and some have comments, including one that holds a false end signature, which `zipfile` itself cannot reopen. Listings match, and extraction matches the data, modes and DOS times written. |
| More than 65,535 entries | 2 | The sample lists `zipfile`'s 65,600-entry ZIP64 archive, and `zipfile` reads the sample's 65,601-entry archive, whose classic end record holds 0xffff. |
| Guards | 26 | Traversal, absolute, backslash and NUL names; symlink escapes; bzip2 and LZMA methods; the encryption flag; a changed CRC; stored size and local name mismatches; prepended data; empty and non-ZIP input; usage errors. Each exits 2 with nothing outside the destination touched, and with nothing written at all for format errors. An empty archive and reordered central headers are accepted. |
| Truncation | 5,994 | Every prefix of three sample archives (deflate, `-0`, `--zip64`) and every third prefix of a streamed `zipfile` ZIP64 archive exits 2. |
| Byte flips | 2,400 | Random 1-4 bit flips in the same four archives exit 0 or 2, never a signal or a hang. 2,075 are rejected. Every accepted flip is one `zipfile` also reads with the same names. |

With `--big`, the oracle also writes a sparse 4 GiB + 123,457 B file at
`-L 1`, and `zipfile` reads it back with ZIP64 sizes and a matching CRC. That
took 40 s. On this machine the sample creates 1 GiB of zeros in 5.4 s with
`-0` and 9.7 s with `-L 2`. Verifying it takes 4.0 s stored and 8.7 s
deflated. CRC-32 runs at about 280 MB/s. Creating 65,600 empty files takes
3.2 s, and listing them 1.5 s.

## Known limits

- Reading archives with prepended data, split archives, encryption and
  methods other than stored and deflate return errors.
- Archive comments are not written, and member comments are ignored.
- Stored members also use data descriptors. Java's `ZipInputStream` rejects
  that combination; `zipfile`, Info-ZIP and the central-directory reader
  here accept it.
- Hard links are archived as separate copies.
