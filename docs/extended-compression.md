# Owned compression containers

`ext::compression` compresses and decompresses arbitrary byte views into owned
packed `alloc::vec::Vec<u8>` results. It uses the Lanius raw
[`ext::deflate`](extended-deflate.md) encoder and
[`ext::inflate`](extended-inflate.md) decoder. Production code does not call
Rust, Python, a host compression library or an external process.

The [resumable decoder](extended-streaming-inflate.md) adds borrowed fixed
workspace and chunked progress to this module and replaces owned member replay
with shared persistent state. All seven new raw/container library tests pass;
the atomic-file application also passes seven groups/98 native cases. The
streaming guide records selected current regressions separately.
Historical container receipts below retain their
original source/API scope.

Executable evidence covers **x86_64 Linux using the GPU compiler**. Other
hosts and GPU-kernel execution have not been established.

## API

```text
Format = RawDeflate | Zlib | Gzip
Limits { max_input: i32, max_output: i32, max_members: i32 }

encode(input: View<u8>, format: Format, max_output: i32)
    -> Result<alloc::vec::Vec<u8>, Error>
decode(input: View<u8>, format: Format, limits: Limits)
    -> Result<alloc::vec::Vec<u8>, Error>
default_limits() -> Limits
```

The default limits are 16 MiB of compressed input, 64 MiB of decoded output,
and 1,024 members. The exported constants are `DEFAULT_MAX_INPUT`,
`DEFAULT_MAX_OUTPUT` and `DEFAULT_MAX_MEMBERS`. All counts are bytes except
`max_members`. An exact fit succeeds. Negative limits return `Bounds`.
`max_members = 0` prevents decoding a member, including a raw or zlib stream.

The format is explicit; there is no automatic format guessing. `RawDeflate`
uses one RFC 1951 stream, `Zlib` uses one RFC 1950 stream, and `Gzip` accepts
one or more consecutive RFC 1952 members. Input following the complete raw or
zlib stream is `TrailingData`. For gzip, each following member must be valid:
padding, junk and a second stream of another format are rejected. A truncated
following gzip header remains an error. Empty gzip input is `Truncated`;
an encoded empty member is valid.

`encode` limits the complete encoded result, including its header and trailer.
`decode.max_input` limits all supplied compressed bytes. Its output limit is
cumulative across members, and each gzip member counts toward `max_members`,
including members whose decoded output is empty. A positive input bound alone
does not limit an expansion; set the decoded-output bound deliberately.

## Container validation

The zlib container follows
[RFC 1950 section 2](https://www.rfc-editor.org/rfc/rfc1950.html#section-2).
It checks the compression method, header check bits, declared window size,
and Adler-32 trailer. The declared window is enforced on DEFLATE distances,
including windows smaller than 32 KiB. All four compression-level indications
are accepted. Preset dictionaries are an explicit unsupported profile: a
complete dictionary identifier with `FDICT` returns `UnsupportedDictionary`.
There is no dictionary input API or implicit dictionary lookup.

The gzip container follows
[RFC 1952 section 2](https://www.rfc-editor.org/rfc/rfc1952.html#section-2).
It checks magic bytes, method, reserved flags, optional-field bounds, header
CRC when present, member CRC-32 and member decoded size. Extra bytes are skipped
according to `XLEN`; terminated original names and comments are accepted as
bytes. Their contents are not paths, output names or application instructions.
Text, time, extra flags and OS hints do not transform decoded bytes. Each
member starts with fresh DEFLATE history, while successful member output is
appended to the same result.

Encoding is deterministic. The raw compressor chooses fixed Huffman LZ77 or
stored blocks according to its documented size policy. Zlib output uses a
32 KiB window, no dictionary and header bytes `78 01`. Gzip output writes
`1f 8b 08 00 00 00 00 00 00 ff`: no optional fields, no timestamp, and OS
unspecified. Its trailer records the original bytes' CRC-32 and length. The
API does not expose a compression-level selector or promise minimal output.

## Ownership, allocation and failure

A successful result owns its bytes independently of input storage. Keep one
active owner and call `destroy()` once when finished. Copies of a `Vec` alias
ownership. Views borrowed from the result remain valid only while its owner
and storage remain live. The input is borrowed, never modified or destroyed.

Every error releases all internal owners. No decoded prefix is returned before
container checksums, trailers, member limits and end-of-input checks pass.
Callers can therefore validate a whole bounded input before publishing any
output. The lower-level raw and container streaming decoders deliberately report
partial progress. Their output is provisional until complete format validation;
see the [streaming contract](extended-streaming-inflate.md) before publishing it.

Encoding allocates a 32,768-entry `i32` scratch vector and one exact-size
result. It measures the raw encoding before allocating output. Consequently
an allocation error can precede discovery that an encoded result exceeds its
limit. The scratch vector is destroyed before returning the result.

Owned decoding allocates a 32,768-byte history ring and a 707-element i32
workspace once, then grows its result geometrically through the shared container
state. It rebuilds transient views after each possible move and resumes the
existing bit/tree/framing state instead of replaying a member. Each gzip member
resets logical history, so previous members never supply a backreference. A large
configured output limit does not preallocate that whole result; growth can
temporarily retain both old and replacement storage.

Complete input/limit metadata admission precedes allocation. Fixed workspace
allocation can now fail before later header/trailer validation, so
AllocationFailed can precede discovery of malformed compressed data. This
allocation-order change has its own runtime acceptance in the
[streaming guide](extended-streaming-inflate.md). All private workspace/output
owners retire on failure; success transfers only the independent result Vec.
Encoding keeps its earlier implementation and allocation order.

Logical metadata checks reject negative starts and lengths and overflowing
`start + length`. The caller must provide sufficient physical backing storage
and keep that storage live and unchanged during the call. Native strided byte
arrays and nonzero-offset views are supported. The language does not enforce
physical lengths, read-only borrowing or destruction for these APIs.

| Error | Meaning |
| --- | --- |
| `Bounds` | Invalid logical view metadata or a negative limit |
| `InputLimit` | Supplied compressed bytes exceed `max_input` |
| `OutputLimit` | Complete encoding or decoded bytes exceed the configured limit |
| `MemberLimit` | Another member would exceed `max_members` |
| `AllocationFailed` | A scratch or output allocation fails |
| `CapacityOverflow` | Owned-storage size cannot be represented |
| `Truncated` | Incomplete container field, trailer or DEFLATE stream |
| `Header` | Invalid magic, header check bits or reserved flags |
| `UnsupportedMethod` | Container compression method is not DEFLATE |
| `UnsupportedWindow` | Zlib declares a window above 32 KiB |
| `UnsupportedDictionary` | Zlib declares a preset dictionary |
| `Checksum` | Adler-32, gzip CRC-32 or gzip header CRC disagrees |
| `SizeMismatch` | Gzip member size disagrees with decoded bytes |
| `TrailingData` | Bytes follow the selected complete stream/member sequence |
| `Deflate(ext::inflate::Error)` | Raw decoding error, including references outside the declared window |
| `Encode(ext::deflate::Error)` | Raw encoder bounds, scratch, capacity or size error |

When an input violates several contracts, validation order determines which
error appears. Output bounds can be reached before a later malformed block
or trailer. Input-limit and logical-metadata failures occur before decoding.
These APIs provide explicit errors, rather than accepting corruption or
returning successful partial output.

## Executable evidence

`tests/extended_compression_execution.rs` historically passed seven focused
native groups for the earlier whole-buffer implementation. Current regression
receipts after decoder migration belong to the
[streaming guide](extended-streaming-inflate.md). The historical scope includes:

- Independent Python zlib streams using stored, fixed and dynamic blocks,
  multiple compression strategies, empty inputs and binary data through
  65,537 bytes.
- Deterministic owned encoding in all three formats, independent decoding,
  exact encoded limits and actual size reduction for repetitive data.
- All 32 gzip optional-flag combinations, Latin-1 names/comments, header CRC,
  eleven concatenated members and exact cumulative limits.
- Truncation at every byte of small streams, malformed headers, checksums,
  sizes, dictionaries, limits and trailing data.
- All eight zlib window indications and four level hints, plus a correctly
  checksummed stream whose long reference violates its changed window.
- Native strided source windows, ownership independence and malformed logical
  metadata.
- Every observed allocation denied in turn for encoding, successful growing
  decoding and a final checksum failure, with each successful allocation
  paired with its release and no returned partial result.

The Python and Rust code is test/reference machinery only. It does not supply
any production library behavior.

The [compress-bytes application](extended-compress-bytes.md) exercises both
modes through bounded binary stdin/stdout, explicit diagnostics and injected
allocation/I/O failures. See [runtime and compiler measurements](extended-compression-performance.md).
