# Borrowed UTF-8 text

`core::text::Text` is an allocation-free view of valid UTF-8. It stores a byte
slice, a start offset and a byte length. Subviews keep the original slice stride,
so both stack arrays and packed owned bytes work. No metadata reinterpretation,
NUL scan or copy is needed. Validation follows the existing scalar codec and
[RFC 3629 sections 3–4](https://www.rfc-editor.org/rfc/rfc3629.html#section-3).

## Construction and lifetime

- `from_utf8(bytes, count)` validates a prefix and returns `Result<Text, Error>`.
- `from_utf8_range(bytes, offset, count)` validates only the selected range;
  bytes outside it need not be UTF-8. Negative or overflowing integer ranges
  return `Bounds`. `InvalidUtf8(index)` reports the malformed sequence's starting
  byte relative to that range, including truncated sequences.
- The caller must provide physical backing through `offset + count`. The
  compiler does not expose the slice length, so a physical overclaim reaches
  native slice bounds checks and traps rather than returning `Bounds`.
- `from_utf8_unchecked(bytes, offset, count)` is a low-level constructor for
  owners that already maintain UTF-8 validity. It checks integer bounds with
  assertions but does **not** validate encoding or physical backing. Its caller
  must establish those preconditions. `String.as_text()` uses this path in O(1).

Keep the backing storage alive and unchanged while using a view, subview or
iterator. Copying Text copies the view, not the storage. No destruction is
needed. These lifetime and immutability rules are conventions; Lanius does not
yet enforce them. In particular, bytes used as hash-map keys must remain
unchanged until their entries are removed or the map is destroyed.

## Operations

| Operation | Contract |
| --- | --- |
| `byte_len`, `is_empty` | Constant-time stored length queries |
| `byte_at(index)` | `Option<u8>`; negative and past-end indices return None |
| `is_char_boundary(index)` | True at scalar starts and the end; false outside the view |
| `slice(start, end)` | Half-open borrowed subview; Bounds or NotCharBoundary on invalid endpoints |
| `scalar_at_byte(index)` | `Option<u32>`; None inside a scalar or outside the text |
| `scalar_count()` | Count Unicode scalars, not grapheme clusters |
| `equals`, `compare` | Exact byte equality and lexicographic ordering (-1, 0, 1) |
| `starts_with`, `ends_with` | Exact prefix/suffix matches; empty patterns match |
| `find`, `rfind` | Optional byte offsets; empty patterns match at 0 and byte_len respectively |
| `match_indices(needle)` | Forward nonoverlapping `Pair<i32, Text>` matches; [contract and accepted evidence](stdlib-text-replacement.md) |
| `trim_ascii()` | Borrowed subview trimming HT, LF, VT, FF, CR and space |
| `scalars()` | Iterator of `Scalar { byte_index, value: u32 }`, relative to this view |
| `split(separator)` | Iterator of borrowed fields, preserving empty fields |
| `split_ascii_whitespace()` | Iterator of nonempty borrowed words, separated by HT/LF/VT/FF/CR/space |
| `lines()` | Borrowed LF/CRLF partition, excluding terminators and a phantom final line; shared forward/backward traversal |
| `parse_u8/u16/u32/u64/usize/i8/i16/i32/i64/isize()` | Checked decimal parsing with errors relative to this view |

`Scalars.next()`, `Split.next()` and `SplitAsciiWhitespace.next()` return Option and remain exhausted after
returning None. Copies of an iterator have independent cursor positions and
borrow the same storage. A nonempty split separator consumes nonoverlapping
matches. An empty separator yields a leading empty field, each Unicode scalar,
then a trailing empty field; empty text therefore produces two empty fields.
These concrete cursors already implement the shared `core::iter::Iterator`
protocol, with `borrow()` for generic adapters and consumers. See
[scalar and byte integration](stdlib-collection-iterators.md) and
[split integration](stdlib-text-split-iterators.md) for their existing evidence.
The new [bidirectional text increment](stdlib-bidirectional-text.md) adds Lines
and `DoubleEndedIterator` for Lines, Scalars and SplitAsciiWhitespace. It uses
one common remaining sequence and original Text-relative scalar indices.
All seven new library gates and the four line-summary groups/102 native cases
pass on native Linux x86_64. Generic reverse callers require both iterator
bounds. None of these three cursor families promises ExactSizeIterator.

NUL, BOM and noncharacters are retained. There is no implicit normalization,
locale ordering, case folding or Unicode whitespace trimming. The six-character
ASCII whitespace definition is shared by `core::u8`, `core::char`
and String trimming. This expands the earlier four-character helper to include
vertical tab and form feed; format parsers keep their own whitespace grammar.

Equality, ordering and hashing traits allow Text in generic collections.
Hashing is the same deterministic FNV-1a byte hash as String, independent of
backing storage or offsets. It is not cryptographic or keyed. Search uses a
direct scan with O(haystack length × pattern length) worst-case work. Scalar
traversal, hashing and comparison are linear; subviews allocate nothing and do
not revalidate already valid text.

## Owned and extended-library integration

`alloc::string::from_text(view)` makes an independent owned copy.
The [literal replacement increment](stdlib-text-replacement.md) adds bounded
whole-result `replace`/`replacen` using the same match cursor. All five library
groups and four literal-rewrite groups/94 cases pass on native Linux x86_64.
The [composition APIs](stdlib-text-composition.md) join or repeat Text views
into independent Strings, or append them atomically to an existing String.
`String.try_append_text(view)` accepts a subview of the destination itself,
retaining old storage until copying finishes if it grows. Allocation failure
preserves the original owner, contents and source view. A successful mutation
invalidates prior borrowed views.

`ext::csv::Table.field(row, column)` returns a borrowed Text. Its existing
`try_field` operation still provides an independent owned String. The CSV
report parses numeric fields directly from views and uses Text keys to query
its hash map. It copies a group name only when a new group is inserted; group
Strings own the storage and outlive the map.

## Execution evidence

The focused tests execute native x86_64 Linux binaries produced by the GPU
compiler. GPU execution of user programs and other targets remain unverified.
The implementation uses portable indexing/scalar operations and no allocator or
host bindings of its own.

`tests/stdlib_text_execution.rs` covers:

- Stack-backed and packed views, offsets, nested subviews, bounds errors,
  scalar boundaries, comparison/hash traits, generic hash-map lookup, numeric
  conversion and growing/in-capacity self-appends.
- 270 deterministic input/separator pairs compared with Rust UTF-8 validation,
  scalar indices, split/search results, boundaries, trimming and FNV-1a hashes.
  Cases include all scalar widths, combining marks, NUL, malformed/truncated
  encodings, surrogates and out-of-range values.
- Every allocation failed in turn while copying and appending views; syscall
  traces check complete cleanup and fixtures check unchanged source/owner data.
- Physical overclaims terminating at the native slice bound with exit 101.

All four groups passed across focused runs on 2026-10-22. This historical
receipt predates the bidirectional cursor state and Lines; current regression
receipts belong to the [bidirectional guide](stdlib-bidirectional-text.md).
The final contract fixture also checks independent iterator cursor copies and
empty owned copies. The existing String (three groups), decimal (two), CSV
(three) and report (two) suites also passed after integration, including their
allocation and I/O fault cases.

```sh
timeout --kill-after=2s 100s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 \
  CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --locked --test stdlib_text_execution -- --nocapture
```

Native `str` conversion without an explicit count still needs compiler length
access. Shared iteration is integrated. Unicode normalization, grapheme
operations and formatting have separate guides and finite evidence in the
[library roadmap](library-roadmap.md). Generic slice segmentation has its own
[increment and evidence](stdlib-slice-segmentation.md), outside these Text
receipts. Wider text policies, broader targets and enforced lifetimes remain
separate work.
