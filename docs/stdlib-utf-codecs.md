# UTF-8, UTF-16 and transcoding

These five portable modules encode, validate, search and edit caller-backed
Unicode buffers without allocation or host services:

| Module | Public functions | Purpose |
| --- | ---: | --- |
| [`core::utf8`](../stdlib/core/utf8.lani) | 25 | Scalar UTF-8 codec, `[u8]` validation and indexing, and `[i32]` byte-code operations |
| [`core::utf8_view`](../stdlib/core/utf8_view.lani) | 12 | Validated `[u8]` comparison, search and scalar edits |
| [`core::utf16`](../stdlib/core/utf16.lani) | 17 | Scalar codec and validation over `[u16]` code units |
| [`core::utf16_bytes`](../stdlib/core/utf16_bytes.lani) | 19 | Explicit UTF-16LE and UTF-16BE over `[u8]` |
| [`core::transcode`](../stdlib/core/transcode.lani) | 10 | Complete UTF-8/UTF-16 conversions into a separate destination |

The formats use Unicode scalar values: `0..=0x10ffff`, excluding
`0xd800..=0xdfff`. UTF-8 uses one to four bytes; UTF-16 uses one BMP unit or a
high/low surrogate pair. The defining formats and well-formedness constraints
are in [Unicode 17, Chapter 3, §§3.9–3.10](https://www.unicode.org/versions/Unicode17.0.0/core-spec/chapter-3/).
Unassigned scalar values, noncharacters, NUL and U+FEFF are accepted. Encoding
validity does not imply a printable character, grapheme boundary or terminal
width. See [Unicode properties](stdlib-unicode.md),
[graphemes](extended-unicode-graphemes.md) and
[terminal width](extended-terminal.md) for those separate operations.

## Storage, lengths and failures

All views borrow existing storage. Copying a view preserves its aliases;
these functions neither extend its lifetime nor free it. A read requires at
least `len` readable elements; a mutation with a `capacity` argument requires
that many writable elements. Lengths, offsets, capacities and scalar ordinals
are `i32`, except scalar-codec widths and byte indices explicitly typed `u32`.
All positions are zero-based. Each operation uses its supplied logical prefix,
not the unused tail of the backing array.

Logical checks cannot establish physical backing. An overstated view or
length can trap when indexing reaches unavailable storage. Existing native
trap fixtures expect exit 101. Such a trap is not a returned bounds error and
does not promise rollback of writes already performed. The same applies to
invalid raw pointers. See [counted view backing contracts](stdlib-slice-views.md).

Normal returned failures from the mutating routines below leave the destination
unchanged, assuming valid physical backing and the stated alias rules. Success
does not append a terminator or clear unused storage. Keep the returned length
as the new logical length; shrinking an edit leaves the old tail outside it.
Read-only operations permit aliases. In-place UTF-8 edits deliberately shift
their own buffer; other aliases observe those writes. During any call, callers
must keep the backing live and prevent conflicting mutation.

An `_or` function returns the caller's fallback unchanged on rejection or a
missing result. The fallback may itself be a valid result. Negative fallbacks
distinguish nonnegative lengths and indices; `0xffffffff` distinguishes scalar
values. Boolean validation is available when a fallback would be ambiguous.
These APIs do not repair malformed input or substitute U+FFFD.

## UTF-8 scalar codec

The six scalar operations in `core::utf8` do not access a buffer:

| Function | Result |
| --- | --- |
| `is_scalar(value)` | Whether a `u32` is in the scalar range above |
| `is_continuation_byte(value)` | Whether a `u8` is `0x80..=0xbf` |
| `sequence_len_or(first, fallback)` | 1 for `00..7f`, 2 for `c2..df`, 3 for `e0..ef`, 4 for `f0..f4`; fallback otherwise |
| `encoded_len_or(value, fallback)` | Scalar's UTF-8 byte count, or fallback for a non-scalar |
| `encoded_byte_or(value, index, fallback)` | One encoded byte; fallback for a non-scalar or `index >= encoded length` |
| `decode_or(first, second, third, fourth, length, fallback)` | Scalar decoded from exactly `length` bytes, or fallback |

`sequence_len_or` classifies only the lead byte; it does not establish a
well-formed sequence. `decode_or` requires `length` to equal that lead's width
and checks all required continuation bytes, shortest encoding, surrogate
exclusion and the scalar maximum. Lengths outside 1–4 are rejected. Arguments
after the requested sequence are ignored: decoding one ASCII byte does not
inspect `second`, `third` or `fourth`.

## UTF-8 views: bytes, scalar ordinals and boundaries

`core::utf8` accepts two representations. `[u8]` stores actual bytes. In the
older `[i32]` byte-code representation, **each element is one byte code in
0..=255**, not a Unicode scalar or UTF-32 unit. Negative or larger codes make
that complete view invalid. The following pairs have the same indexing rules:

| `[u8]` function | `[i32]` function | Meaning |
| --- | --- | --- |
| `bytes_are_valid` | `codes_are_valid` | False for negative length or malformed UTF-8; empty input is valid |
| `byte_scalar_count_or` | `scalar_count_or` | Number of scalar values; empty input gives 0 |
| `byte_view_offset_of_scalar_or` | `byte_offset_of_scalar_or` | Scalar boundary ordinal to byte offset; ordinal equal to scalar count gives `len` |
| `byte_view_scalar_index_of_byte_or` | `scalar_index_of_byte_or` | Byte boundary offset to scalar ordinal; `len` gives scalar count |
| `byte_view_scalar_at_or` | `scalar_at_or` | Scalar at an ordinal strictly below scalar count |

The positional functions reject negative indices, indices beyond their domain,
and byte positions inside a multibyte encoding. They validate the entire logical
input, including a malformed suffix after the requested scalar. A length that
ends halfway through a scalar is invalid; a shorter prefix ending at a scalar
boundary is a separate valid view.

For the UTF-8 bytes of `A¢€😀`, scalar count is 4, byte length is 10, and the
scalar boundaries are byte offsets `0, 1, 3, 6, 10`. Ordinal 4 maps to boundary
10, but scalar-at ordinal 4 fails. Byte offset 2 is inside `¢` and fails the
byte-to-ordinal conversion. Neither index counts user-perceived characters.

### Comparison and search

Every operation below validates both complete inputs, where applicable.
Malformed or negative-length inputs give false for the Boolean operations and
fallback for the others, even if an early prefix would match. Two valid empty
views are equal. No normalization, case folding or locale collation is applied.

| `core::utf8` on `[i32]` | `core::utf8_view` on `[u8]` | Contract |
| --- | --- | --- |
| `equal_codes` | `byte_view_equal` | Exact complete-byte equality |
| `starts_with_codes`, `ends_with_codes` | `byte_view_starts_with`, `byte_view_ends_with` | Exact prefix/suffix; valid empty pattern matches every valid view |
| `compare_codes_or` | `byte_view_compare_or` | Lexicographic encoded-byte order, returning -1, 0 or 1; a proper prefix sorts first |
| `index_of_codes_byte_or`, `last_index_of_codes_byte_or` | `byte_view_index_of_bytes_or`, `byte_view_last_index_of_bytes_or` | First/last matching **byte offset**; valid empty needle matches at 0/`len` |
| `index_of_scalar_or`, `last_index_of_scalar_or` | `byte_view_index_of_scalar_or`, `byte_view_last_index_of_scalar_or` | First/last matching **scalar ordinal**; non-scalar needle or absence gives fallback |

Lexicographic order of valid UTF-8 follows scalar-value order. A nonempty valid
needle cannot match starting in a continuation byte. Byte-subsequence search
still reports bytes, whereas a scalar search reports ordinals: searching `€`
in the example above gives byte offset 3 or scalar ordinal 2, respectively.

### Append, insert, remove and replace

`core::utf8::append_scalar_or(values, len, capacity, value, fallback)` appends
one scalar to a valid `[i32]` byte-code prefix and returns its new byte length.
It requires `0 <= len <= capacity`, valid existing UTF-8, a valid scalar and
enough room for that scalar's complete encoding.

The four `[u8]` edits belong to `core::utf8_view`:

| Function | Index and success result |
| --- | --- |
| `byte_view_append_scalar_or(values, len, capacity, scalar, fallback)` | Append at the end; return new byte length |
| `byte_view_insert_scalar_or(values, len, capacity, scalar_index, scalar, fallback)` | Insert before an ordinal in `0..=scalar_count`, including the end boundary; return new byte length |
| `byte_view_remove_scalar_or(values, len, scalar_index, fallback)` | Remove an ordinal in `0..scalar_count`; return reduced byte length |
| `byte_view_replace_scalar_or(values, len, capacity, scalar_index, scalar, fallback)` | Replace an ordinal in `0..scalar_count`; return the possibly changed byte length |

All require valid complete existing UTF-8. Capacity-bearing edits also require
`0 <= len <= capacity` and enough room for the final encoding. Remove has no
capacity argument and only shifts within the original logical prefix. Invalid
indices, malformed input, non-scalars or insufficient logical room return
fallback before writing. An insert into empty input at ordinal 0 is valid;
remove and replace on empty input fail. Growth shifts the tail right, shrinkage
shifts it left, and no edit cuts a scalar's bytes in half. Other stored scalar
ordinals and byte offsets may change after an edit.

## UTF-16 units and result statuses

`core::utf16` works with `[u16]` units, independent of byte serialization.
`is_high_surrogate`, `is_low_surrogate` and `is_surrogate` recognize
`d800..dbff`, `dc00..dfff` and their union. `is_scalar` uses the shared scalar
definition. `encoded_len_or` returns 1 for BMP scalars or 2 for supplementary
scalars, and fallback for a non-scalar.

Five `i32` constants are defined in this module and reused by the byte codec
and transcoder:

| Constant | Value | Meaning |
| --- | ---: | --- |
| `STATUS_OK` | 0 | Successful operation |
| `STATUS_BOUNDS` | 1 | Invalid logical length, capacity, offset or required byte alignment |
| `STATUS_INVALID_SCALAR` | 2 | Requested scalar to encode is invalid |
| `STATUS_SHORT` | 3 | Not enough destination space, or incomplete input for one scalar |
| `STATUS_MALFORMED` | 4 | Malformed source encoding |

`write_scalar(units, capacity, offset, scalar)` returns `Utf16Write { status,
next }`. Checks occur in order: nonnegative capacity and `0 <= offset <=
capacity`; scalar validity; room for 1 or 2 units. A returned failure writes
nothing and retains the original offset in `next`. Success writes one complete
scalar and makes `next` the following unit offset. It does not validate units
before or after the write. Writing a valid scalar at `offset == capacity`
returns `SHORT`, not `BOUNDS`.

`decode_next(units, len, offset)` returns `Utf16Decode { status, scalar,
next }`. It requires `len >= 0` and `0 <= offset < len`, otherwise `BOUNDS`.
A non-surrogate unit succeeds immediately. A leading low surrogate gives
`MALFORMED`; a high surrogate at the end gives `SHORT`; a high surrogate
followed by a non-low unit gives `MALFORMED`. Success advances by 1 or 2 units.
Failure stores scalar 0 and the original offset. This reads **one scalar**;
it does not validate the rest of the view. The end offset is not a successful
EOF result.

`validate(units, len)` checks the complete input; negative length is false,
empty input is true. `scalar_count_or` returns its scalar count or fallback.
`scalar_at_or(units, len, ordinal, fallback)` validates the complete input and
returns the requested scalar only for `0 <= ordinal < count`.

Use `write_succeeded`, `write_status` and `write_next_or` to inspect writes;
`decode_succeeded`, `decode_status`, `decode_scalar_or` and `decode_next_or`
inspect decodes. The `_or` accessors expose payloads only when status is OK.
The success predicates themselves only compare `status` with zero; they do not
validate a caller-constructed result record.

## UTF-16 bytes and byte order

`core::utf16_bytes` provides explicit LE/BE serialization. All lengths,
capacities and `next` fields are **bytes**, and scalar ordinals still count
scalars. There is no byte-order detection and no BOM added or removed. A
leading encoded U+FEFF is an ordinary returned scalar. The endian choice is
supplied by the function name.

| Functions | Contract |
| --- | --- |
| `byte_len_for_scalar_or` | 2 or 4 bytes for a scalar; fallback for a non-scalar |
| `unit_count_or(byte_len, fallback)` | `byte_len / 2` for nonnegative even byte lengths; fallback otherwise; does not inspect or validate storage |
| `write_scalar_le`, `write_scalar_be` | Scalar write to `[u8]`, returning `Utf16ByteWrite { status, next }` |
| `read_next_le`, `read_next_be` | One-scalar decode from `[u8]`, returning `Utf16ByteDecode { status, scalar, next }` |
| `validate_le`, `validate_be` | Complete-view validation; negative or odd byte length is false |
| `scalar_count_or_le`, `scalar_count_or_be` | Complete-view count, or fallback |
| `scalar_at_or_le`, `scalar_at_or_be` | Complete-view validation then scalar at an ordinal, or fallback |

Single-scalar read/write offsets must be even relative to the passed view's
start. This is byte-position alignment, not a raw pointer alignment promise.
Write checks `0 <= offset <= capacity` and even offset before checking the
scalar and remaining space. Capacity itself may be odd; only complete 2- or
4-byte encodings are written. Returned logical failures leave bytes unchanged.

A single-scalar read requires `0 <= offset < len` and even offset. It returns
`SHORT` if fewer than two bytes remain, or fewer than four after a high
surrogate; malformed surrogate combinations follow the unit codec's statuses.
It can read a complete scalar from the front of an odd-length view. Whole-view
validation still rejects that view because of its trailing incomplete unit.

The byte module has its own `write_succeeded`, `write_status`, `write_next_or`,
`decode_succeeded`, `decode_status`, `decode_scalar_or` and `decode_next_or`
accessors with the same success/fallback rules as the unit module. A failed
decode stores scalar 0 and the original byte offset. This module defines no
second set of status constants; use `core::utf16::STATUS_*`.

## Complete transcoding and progress

Every converter takes `(source, source_len, destination, capacity)` and
returns `TranscodeResult { status, read, written }`. Source and destination
must have **nonoverlapping backing**, even for the byte-to-byte variants.
That requirement is not dynamically checked. The source must remain unchanged
through validation, sizing and writing.

| Function | Source elements and `read` | Destination elements and `written` |
| --- | --- | --- |
| `utf8_to_utf16` | `[u8]`, bytes | `[u16]`, units |
| `utf16_to_utf8` | `[u16]`, units | `[u8]`, bytes |
| `utf8_to_utf16le`, `utf8_to_utf16be` | `[u8]`, UTF-8 bytes | `[u8]`, UTF-16 bytes |
| `utf16le_to_utf8`, `utf16be_to_utf8` | `[u8]`, UTF-16 bytes | `[u8]`, UTF-8 bytes |

The converters reject a negative source length or destination capacity with
`BOUNDS`. They then validate the entire source: malformed or truncated UTF-8,
malformed or truncated UTF-16, and odd UTF-16 byte lengths all give
`MALFORMED`. Thus an incomplete source is not a resumable `SHORT` result here.
Only after validation do they size the complete output; insufficient logical
destination capacity gives `SHORT`. A malformed source takes precedence over
too little destination space. No converter returns `INVALID_SCALAR` for a
normally returned source-validation failure.

Validation and sizing finish before writing begins. Every returned logical
failure leaves the destination unchanged and sets both `read` and `written`
to 0. These are complete conversions, with no partial-consumption cursor or
required-output-length result. Success reports `read == source_len` and the
actual destination length. Empty input with nonnegative capacity succeeds
without writing, including capacity 0. Bytes or units after the output are
untouched. BOMs, NULs and scalar sequences are preserved; no normalization or
newline translation occurs.

Use `succeeded(result)` and `status(result)` to inspect the outcome.
`read_or(result, fallback)` and `written_or(result, fallback)` return their
counts only on success; otherwise they return fallback, not the stored zero.
As with the other result records, these accessors trust the supplied status.

Capacity checks use subtraction before increasing the required count, so a
required output larger than the greatest `i32` capacity is rejected as `SHORT`
before that count can overflow. If callers use a coarse upper bound to size
storage, their own multiplication must be checked: UTF-8 to UTF-16 units needs
at most `source_len` units; UTF-8 to UTF-16 bytes at most `2 * source_len`;
UTF-16 units to UTF-8 at most `3 * source_len` bytes; UTF-16 bytes to UTF-8 at
most `3 * (source_len / 2)` bytes. These bounds assume valid input and are not
additional allocation or size-query APIs.

## Work and existing native evidence

Scalar codecs and one-scalar UTF-16 operations use constant work and storage.
Complete validation, scalar counting/indexing, scalar search, comparison,
prefix/suffix checks and individual edits are linear in the supplied input
lengths. Positional and edit helpers can make more than one validation pass;
repeated scalar-at calls do not form a constant-time iterator. Substring search
uses a direct nested scan with worst-case `O(n * m)` work for input and needle
lengths. Transcoding makes validation, sizing and write passes with linear
work and constant auxiliary storage. There is no caller work budget or hidden
allocation; callers needing a resource bound must limit logical input sizes.

The existing drivers below compile production modules and execute generated
x86_64 ELFs on their supported native test hosts. Expected positive exits are
0 and physical backing traps are 101, with the stated output checks. This
guide audits their assertions; it does not report a new test run.

| Existing driver and fixtures | Assertions represented |
| --- | --- |
| [`stdlib_foundation_execution.rs`](../tests/stdlib_foundation_execution.rs), `core_utf8.lani` | UTF-8 scalar width transitions and scalar limits; overlong, surrogate, bad-continuation and truncated rejection; `[i32]` byte-code range checks; boundary mappings, complete-tail validation, scalar/byte searches and append sentinels |
| [`stdlib_utf8_bytes_execution.rs`](../tests/stdlib_utf8_bytes_execution.rs), `core_utf8_bytes`, `core_utf8_byte_search`, `core_utf8_byte_append`, `core_utf8_byte_edit` and matching `_bounds` fixtures | Byte-backed validation and mappings; first/last searches and empty patterns; insert/remove/replace growth and shrinkage; unchanged sentinels on rejected edits; physical backing traps; exact `utf8_text_report` sample output |
| [`stdlib_utf16_execution.rs`](../tests/stdlib_utf16_execution.rs), `core_utf16_complete`, `core_utf16_matrix`, `core_utf16_bounds` | All status values, returned-offset accessors, strict surrogate rules, whole-tail validation and unchanged write sentinels; all 65,536 BMP values plus 3,072 supplementary samples across all high-surrogate blocks; physical backing trap |
| [`stdlib_utf16_bytes_execution.rs`](../tests/stdlib_utf16_bytes_execution.rs), `core_utf16_bytes_complete`, `core_utf16_bytes_bounds` | Exact LE/BE bytes, misaligned offsets, odd lengths, short and malformed input, scalar indices, BOM preservation, write sentinels and physical backing trap |
| [`stdlib_transcode_execution.rs`](../tests/stdlib_transcode_execution.rs), `core_transcode_complete`, `core_transcode_byte_views` and four backing-bound fixtures | Six conversions, exact mixed-width encodings and round trips, all ASCII unit round trips, maximum scalar, empty input, malformed suffixes, short output, error accessors, destination sentinels and source/destination backing traps |
| Sample tests in the UTF-16 and transcode drivers | Real stdin to `utf16le_scalar_count` and `utf8_to_utf16_summary`; empty, mixed-width, malformed, truncated, maximum permitted and oversized inputs; exact stdout, status codes and `/dev/full` output failure |

The UTF-16, byte-UTF-16 and transcode drivers also require a fixture call for
each public function; the foundation inventory supplements UTF-8 coverage in
the same way. Such source-call inventories establish discoverability, not
correct execution by themselves. The directed fixtures and sampled matrix do
not establish exhaustive malformed-sequence coverage, overlapping-transcode
behavior, or execution on Wasm and other targets. This guide makes no broader
target or conformance claim.
