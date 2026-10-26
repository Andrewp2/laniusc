# Classic ZIP archives

`ext::zip` reads borrowed archive metadata, extracts checked owned payloads and
writes deterministic multi-entry archives. The implementation is Lanius and
uses `ext::deflate`, `ext::inflate`, `core::crc32` and `alloc::vec`. It performs
no filesystem extraction or path normalization.

The supported profile is classic single-disk ZIP with stored or DEFLATE
entries. Structural rules follow
[PKWARE APPNOTE 6.3.10](https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT),
particularly its local headers, descriptors, central directory, end record,
flags and extra fields. ZIP64, split archives, encryption, patched data,
unsupported compression methods and unsupported flag/version requirements
return explicit errors. This API does not claim general ZIP feature support.

Executable evidence covers **x86_64 Linux using the GPU compiler**. Other
hosts and GPU-kernel execution have not been established.

## API

```text
Method = Stored | Deflate
Limits { max_archive: i32, max_entries: i32, max_entry: i32,
         max_total: u64, max_work: u64 }

parse(input: View<u8>, limits: Limits) -> Result<Archive, Error>
extract(entry: Entry, max_output: i32) -> Result<alloc::vec::Vec<u8>, Error>
encode(entries: View<Source>, comment: View<u8>, limits: Limits)
    -> Result<alloc::vec::Vec<u8>, Error>
default_limits() -> Limits

Source { name: View<u8>, data: View<u8>, method: Method, utf8: bool }
Archive.len() -> i32
Archive.is_empty() -> bool
Archive.cursor() -> Cursor
Cursor.remaining() -> i32
Cursor.next() -> Option<Entry>
```

`Archive.comment` borrows the raw archive comment. Entries expose borrowed
`name`, `comment`, central `extra`, `local_extra` and compressed `data` views;
`method`, `utf8`, raw `flags`, `crc32`, compressed and uncompressed sizes;
raw DOS modification time/date and external attributes; and the local record
offset and end. Offsets are relative to the selected archive view, even when
that view starts inside larger or strided storage.

The cursor visits central-directory order, including duplicate names, and
remains exhausted after its last entry. It does not choose a winner for a
duplicate name. A cursor copy has independent iteration position. Archive,
entry and cursor values borrow the original input: keep it live and unchanged
for their complete use. Metadata values come from `parse`; forged or modified
records are outside that established structure contract.

## Parsing and integrity

`parse` validates the complete central directory and every referenced local
record before returning an archive. Local and central names, required version,
method, flags, DOS time/date and non-descriptor sizes/checksum must agree.
Extra fields may differ between local and central records and are exposed
separately. Stored sizes must agree. Data descriptors with and without their
optional signature are accepted and checked against central sizes/checksum.
For a descriptor entry, each local checksum/size may be zero or agree with its
central value. The descriptor itself must supply the exact values.

Local byte spans cannot overlap, even when central-directory order differs
from local-record order. The directory must end immediately before its end
record; the comment must reach exactly the end of supplied input. Digital
signature records, ZIP64 end records and extra trailing bytes are unsupported.
A complete end-record-shaped sequence inside a comment does not prevent
finding the earlier valid end record.

Only referenced local records are audited. Unreferenced prefixes, gaps and
orphan bytes before the central directory are permitted. They are neither
executed nor exposed as entries. This lets a valid archive use an adjusted
prefix without treating arbitrary prefix content as a library program.

Parsing validates metadata, **not payload integrity**. Listing an archive does
not decompress its entries. `extract` allocates the declared uncompressed
size, decodes or copies the selected entry, then validates its exact decoded
length and CRC-32. A DEFLATE stream must consume its entire declared compressed
span. No payload prefix or partial owner is returned on failure. Parsing a
structurally valid but corrupted payload can therefore succeed while extracting
it fails explicitly.

## Names and extra fields

`validate_name(name, utf8)` checks the writer's name policy without constructing
an archive. It returns the byte length or `Bounds`, `Name` or `Encoding`, and
allocates nothing. Its checks share the writer's private name and encoding
helpers. Whether a name ending in `/` has an empty payload is checked later by
`encode`; name validation does not provide filesystem extraction safety.

Names and comments retain their bytes. With the UTF-8 flag set, both are
validated as UTF-8. Without it, bytes retain their legacy encoding, conventionally
CP437; the library performs no conversion. Unknown extra-field TLVs are checked
for bounds and retained. InfoZIP Unicode path/comment fields are retained as
raw extras and do not override the exposed name or comment. ZIP64, AES, strong
encryption and patch descriptors are explicitly rejected.

The reader preserves names containing absolute syntax, backslashes, NUL or
parent components and does not interpret symlinks or file-type attributes.
Applications that extract to a filesystem must impose their own pathname,
file-type and ownership policy. This module only returns bytes.

The writer preserves supplied relative forward-slash names. It rejects NUL,
backslash, a leading slash and a drive-style second-byte colon. A name ending
in slash requires empty data. An empty name is supported for a nameless entry;
duplicate names and literal `.`/`..` components remain permitted. These are
archive names, and no operation follows or resolves them. With `utf8 = true`,
the writer validates the supplied name and sets the encoding flag. Otherwise
it writes raw legacy bytes.

## Deterministic writing and ownership

The writer supports multiple stored and DEFLATE entries in caller order. It
uses DOS date 1980-01-01 and time zero, required/made-by version 2.0, zero
attributes, no extras or per-entry comments, and no data descriptors. It writes
correct local and central checksums/sizes after measuring compressed payloads.
The raw compressor's fixed-Huffman LZ77 or stored-block policy is documented in
[the DEFLATE module](extended-deflate.md). The same inputs produce the same
archive bytes. The caller supplies the final raw archive comment.

Writer input views remain borrowed and unchanged. A successful writer or
extractor result owns independent packed bytes. Keep one active owner and call
`destroy()` once when finished; copying a vector aliases ownership. Every error
destroys all internal partial owners.

`parse` and cursor traversal allocate nothing. Extraction uses one exact-size
result allocation, except for empty output. Writing reserves one metadata
vector, one shared 32,768-entry `i32` compressor scratch vector if needed, and
one exact-size result. Allocation failure may precede discovering an eventual
compressed archive-size limit. Empty archives need only their result allocation.

## Limits and work

Defaults are 64 MiB archive bytes, 4,096 entries, 64 MiB per decoded entry,
128 MiB total decoded bytes and 16,777,216 work units. Parsing applies archive,
entry-count, per-entry and declared-total limits before extraction. Extraction
also applies its own `max_output` bound. Writing applies these limits to the
final archive, input entry count, each source payload and aggregate payloads.
Exact limits succeed. Negative signed limits return `Bounds`.

The parser's work budget charges end-record search positions, central-record
bytes plus one per record, local header/name/extra bytes and each pairwise
overlap comparison. The overlap audit is quadratic in entry count, with a
constant amount of checked work per comparison and an explicit budget. This
supports reordered directories without allocating an index. A 1,024-entry
directory is tested with the defaults; a deliberately smaller budget stops
validation. Cursor traversal does not repeat the pairwise audit.

Writing charges comment bytes plus one, then each source payload byte, name
byte and 100 units per entry during preflight. Consequently a caller writing
more than the default work budget's input size must increase `max_work` even
if the result compresses to a small archive. Raw compression also has its own
bounded per-byte algorithm; these units are resource counters, not elapsed
time or processor-instruction guarantees.

All archive offsets and individual sizes must fit nonnegative `i32`. Classic
ZIP64 sentinel fields and ZIP64 extras are rejected, including ZIP64 selected
for small data. At most 65,534 entries can be written. Logical view bounds are
checked; the caller must still supply enough physical backing and maintain
read-only lifetimes. These contracts are not enforced by the language.

## Errors and executable evidence

Errors distinguish invalid metadata (`Bounds`, `Truncated`, `Signature`,
`HeaderMismatch`, `Descriptor`, `Overlap`), explicit unsupported features
(`Zip64`, `MultiDisk`, `Encryption`, `UnsupportedMethod`, `UnsupportedFlags`,
`UnsupportedVersion`, `UnsupportedExtra`), names/encoding (`Name`, `Encoding`),
integrity (`Checksum`, `SizeMismatch`, `TrailingData`), limits (`ArchiveLimit`,
`EntryLimit`, `TotalLimit`, `WorkLimit`, `OutputLimit`, `SizeOverflow`),
`AllocationFailed`, and underlying `Deflate(...)`/`Encode(...)` errors. When
several contracts fail, the first validation reached determines the error.

`tests/extended_zip_execution.rs` covers Python `zipfile` interoperability in
both directions, deterministic empty/multi-entry output, stored and DEFLATE
payloads through 65,537 bytes, binary and Unicode data, both descriptor forms,
reordered directories, legacy raw names and Unicode extras, comment signature
ambiguity, overlap rejection, native strided views, fused cursors, malformed
headers and truncations, unsupported features, integrity errors, exact limits,
1,024-entry work bounds and every observed allocation failure. Each successful
allocation is checked against its release. Python and Rust are independent test
machinery and do not supply production behavior.

The public `validate_name` helper also passes the focused native archive
contract, including UTF-8 and raw names, nonzero strided subviews, invalid view
metadata, NUL and rejected path syntax. That contract passed in 6.79 seconds:
`target/stdlib-work/http-batch-zip-name-contracts.log`. This receipt covers the
shared name policy; the broader archive cases above retain their separate
execution evidence.
