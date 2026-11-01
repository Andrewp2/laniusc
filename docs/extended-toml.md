# TOML 1.1.0

`ext::toml` parses UTF-8 TOML into an immutable owned indexed document and
encodes that document as deterministic TOML. The implementation follows the
[TOML 1.1.0 specification](https://toml.io/en/v1.1.0) and
[1.1.0 ABNF](https://github.com/toml-lang/toml/blob/1.1.0/toml.abnf).
It includes the 1.1 additions: `\e` and `\xHH` escapes, omitted seconds,
and multiline inline tables with comments and trailing commas.

The parser and encoder are Lanius algorithms. They use `alloc::string`,
`alloc::vec`, the exact `core::float_decimal` binary64 converter, and checked
`core::calendar` constructors. They do not call a host TOML, JSON, numeric, or
date parser. Native execution has been checked on x86_64 Linux. Allocator
services are required; execution on a user GPU has not been established.

## Ownership and input

`parse(input: alloc::string::String, options: Options)` and
`parse_text(input: core::text::Text, options: Options)` return
`Result<Document, Error>`. Both borrow the caller's input. The parser validates
UTF-8 and copies the selected input range into temporary owned storage. Decoded
keys, strings, numbers, and temporal spellings are owned independently by the
result. The input can be destroyed immediately after either call returns.
Every returned parse error destroys the temporary input, pending keys and
strings, frame storage, and all nodes constructed so far.

A successful document has one active owner. Copies of a `Document` record share
that allocation and do not create additional owners. Call `document.destroy()`
exactly once through the active owner. Calling it again on that same reset owner
is harmless; calling it through an earlier shallow copy is invalid. Lanius does
not enforce this ownership convention. `borrow()` returns `&Document` for
helpers that use a borrowed reference.

`NodeId` is an `i32` borrowing its document. IDs and borrowed `Text` views remain
valid until the document is destroyed. The API exposes no edits. Do not mutate
`Text.bytes` through its currently writable backing view. `copy_string`,
`copy_number`, `copy_temporal`, and `copy_key` return independent owned strings
and report allocation failure explicitly.

`Text` bounds must name physically backed storage. Negative or overflowing
logical ranges are rejected. Lanius cannot verify that an arbitrary supplied
slice physically backs a claimed count; an overclaim violates the slice
precondition and may trap.

## Query API

All node queries return `Result<..., Error>`. An invalid ID produces `Bounds`;
a query for the wrong TOML type produces `WrongKind`.

| Query | Result payload |
| --- | --- |
| `root()` | `Option<NodeId>`; root is `0` for every parsed document, including empty input |
| `node_count()` | `i32`, including the root table and intermediate tables |
| `kind(id)` | `Kind` |
| `child_count(id)` | `i32`, for tables and arrays |
| `first_child(id)` | `Option<NodeId>`, for tables and arrays |
| `next_sibling(id)` | `Option<NodeId>` |
| `element(array, ordinal)` | `Option<NodeId>`; negative ordinal is `Bounds`, exhaustion is `None` |
| `member(table, String)` / `member_text(table, Text)` | `Option<NodeId>`; key bytes compare exactly |
| `key_view(id)` / `copy_key(id)` | Borrowed / owned key for a table member |
| `string_view(id)` / `copy_string(id)` | Borrowed / owned decoded Unicode text |
| `integer_i64(id)` | Lossless signed 64-bit integer |
| `float64(id)` | IEEE 754 binary64 value |
| `boolean(id)` | `bool` |
| `number_view(id)` / `copy_number(id)` | Canonical integer or floating spelling |
| `temporal_view(id)` / `copy_temporal(id)` | Original complete temporal spelling |
| `temporal(id)` | `Temporal` with checked calendar values and exact fraction view |

`root()` and `node_count()` themselves return their payload directly.
`Kind` has `Table`, `Array`, `String`, `Integer`, `Float`, `Boolean`,
`OffsetDateTime`, `LocalDateTime`, `LocalDate`, and `LocalTime` variants.
An array of tables has kind `Array`; each element has kind `Table`. Table
iteration retains first-definition order, and array iteration retains element
order. No ordering commitment is imposed on TOML tables by the format itself.
Member lookup is linear in table width. Repeated ordinal lookup is linear in
the ordinal; use sibling iteration for a whole array.

`Temporal` contains:

- `date: Option<core::calendar::Date>`;
- `time: Option<core::calendar::TimeOfDay>`;
- `offset: Option<core::calendar::UtcOffset>`;
- `fraction: core::text::Text`, borrowing all fractional digit bytes without the dot.

Omitted seconds become zero. `TimeOfDay.nanos` truncates after nine decimal
digits and pads shorter fractions with zeros. `fraction` retains every original
digit, so callers can use arbitrary precision without information loss.
`-00:00` produces `UtcOffset { minutes: 0, known: false }`; `Z`, `z`, and
`+00:00` have a known zero offset. All date years are four digits, `0000` through
`9999`, and Gregorian month/day validation includes year zero and century rules.
Seconds `60` retain leap-second syntax, consistently with `core::calendar`;
this module does not assert that an actual leap second was announced or convert
that syntax to a Unix timestamp. Local times and datetimes have no implicit
zone or offset.

## Grammar and table semantics

All four TOML string forms are supported, including multiline delimiter quote
runs, Unicode scalar escapes, line continuation trimming, and LF normalization
of CRLF newlines. Invalid UTF-8, surrogate escapes, out-of-range escapes,
unknown escapes, prohibited controls, and bare CR newlines are rejected.
Quoted keys use single-line basic or literal strings; bare keys use the TOML
ASCII grammar. Empty quoted keys are valid. Dotted keys compare decoded bytes,
so quoted and bare spellings of the same key collide.

Tables track implicit super-tables, explicit headers, dotted definitions,
self-contained inline definitions, and arrays of tables separately. Duplicate
keys, repeated explicit headers, reopening dotted tables as explicit headers,
mutating an inline table from outside its braces, converting a scalar or table
to an array of tables, and appending headers to a static array are errors.
Headers beneath an array of tables select its most recent table element.
Mixed arrays, nested arrays, empty tables, empty arrays of values, multiline
inline tables, and trailing commas in arrays and inline tables are supported.

Integers accept decimal signs and separators and unsigned hexadecimal, octal,
and binary prefixes. All results must fit signed 64-bit range. Overflow is
`NumberOutOfRange`; values never wrap or silently round. Finite floats use the
exact nearest-even converter, including subnormal boundaries, ties, signed zero,
underflow to signed zero, and overflow to signed infinity. `inf`, `+inf`, `-inf`,
`nan`, `+nan`, and `-nan` are accepted; signed NaN is retained by this parser.
The exact converter accepts at most 768 significand digit characters; exceeding
that implementation resource bound is an explicit `NumberLimit` error.

## Encoding

The [resumable serializer](extended-toml-streaming.md) now defines one shared
byte machine for all output paths; all five library gates pass on Linux x86_64
CPU output from the GPU compiler.
`document.encoded_len()` replaces free `measure(document)` and returns the exact
u64 output byte count without allocating. `document.encoding()` admits a
borrowed canonical `Read` cursor. `encode(document)` still returns an independent
owned String or an explicit error.

`encode_into(document, output: core::slice::View<u8>)` returns the written byte
count. Logical metadata, semantic/output preflight, caller capacity and replay
work are checked before writing. Its capacity error is `OutputLimit`; every
returned error leaves the complete destination unchanged. The new path fills
the admitted prefix directly without a temporary String or output allocation.
Bytes outside that prefix are unchanged. Document backing stays immutable/live
and disjoint from cursor and destination storage throughout serialization.

Encoding emits one quoted root key, equals sign, value, and LF per root member.
Nested tables become inline tables and arrays of tables become arrays of inline
tables. Empty input encodes to empty output. This preserves TOML value kinds
without needing JSON transport or distinguishing source header styles.

All strings and keys use basic quoted strings with Unicode scalar content and
escaped control bytes. Integers use decimal notation. Floats use the exact
converter's shortest binary64 spelling, with `.0` appended when needed to retain
`Float` kind; infinity and signed NaN use lowercase TOML spelling. Negative zero
encodes as `-0.0`. Temporal output uses uppercase `T`/`Z`, explicit seconds,
fractions with trailing zeros removed, and `Z` for known zero offset. Unknown
zero offset remains `-00:00`. Arbitrarily long nonzero fractional tails remain
exact. Parsing and encoding the output again is idempotent.

The normal form retains table insertion order and temporal offset identity.
It is not an ordering or timezone-equivalence comparison API. Comments, spacing,
source radix, original string delimiter style, and original header layout are
not part of the value model.

## Resource limits and diagnostics

`default_options()` returns these explicit bounds:

| Option | Default | Unit |
| --- | ---: | --- |
| `max_input_bytes` | 16,777,216 | selected UTF-8 input bytes |
| `max_nodes` | 1,000,000 | root, intermediate tables, containers, and scalar nodes |
| `max_depth` | 128 | parent edges from the root; a root member is depth one |
| `max_string_bytes` | 16,777,216 | each decoded key/string or original temporal token |
| `max_number_bytes` | 1,024 | each original numeric token, including signs and underscores |
| `max_output_bytes` | 67,108,864 | encoded UTF-8 bytes |
| `max_work` | 1,000,000,000 | conservative operation work units |

Negative signed options produce `InvalidOptions`. Zero is a meaningful bound.
A zero node bound rejects even empty input because the document requires its
root table. The depth bound applies to every node, including scalars and the
additional table element beneath an array of tables. Arrays and inline tables
use an explicit allocated frame stack. Parsing, encoding, and destruction do
not recurse through the native call stack.

Parsing charges selected input length before UTF-8 validation, charges scanning
and node insertion, and charges key-comparison bytes to bound adversarial wide
tables. A floating conversion reserves one million work units for the bounded
exact converter; non-NaN formatting reserves a further million. These are
conservative charges, not measurements of elapsed processor time. Serializer
work W counts emitted bytes, nonroot node visits, scanned fraction digits and
trimmed trailing-zero digits. `encoded_len()` admits W; reader construction,
owned `encode` and direct `encode_into` admit 2W for preflight plus replay.
This deliberately replaces old owned encode's W and old encode_into's
2W + output-byte-copy charge. Allocator/collector work and host calls are outside
this serializer budget. See the [work contract](extended-toml-streaming.md#work-accounting).
Preflight reports the first exhausted bound in generator order: each emitted
byte checks output capacity before its byte-work charge, while node/fraction
work is charged where encountered. Simultaneously insufficient caps can select
a different error from the earlier scalar/raw-chunk implementation; there is
no whole-pass output-over-work precedence.
Public value queries operate on an already bounded immutable document and do
not consume parser or encoder budgets.

`Error { kind: ErrorKind, offset: i32 }` reports a byte offset relative to the
selected input range. Query and encoder errors use offset `-1`. Invalid options
and logical input bounds also use `-1`. Invalid UTF-8 reports the malformed
sequence's exact starting offset. Resource exhaustion reports the point where
the bound was detected; diagnostics do not claim that every syntax error points
to the first causative character.

`error_kind_text(kind)` returns a static borrowed lowercase diagnostic name for
every `ErrorKind`. Kinds distinguish unexpected end/byte, invalid UTF-8, escape,
number or date/time, integer range, duplicate key, table redefinition, each
resource limit, allocation failure, invalid options, bounds, and wrong kind.

## Executable evidence

The historical receipts below predate the shared resumable serializer. Its
[current acceptance](extended-toml-streaming.md#status-and-dependencies) covers
five library groups, including the independent state model and selected
owned-output allocation failures. Parser corpus coverage and old
output/allocation observations retain their original source scope.

`tests/fixtures/extended_library/toml_smoke.lani` checks native parsing, signed
64-bit minimum, negative floating zero, TOML 1.1 escapes, checked leap-day and
unknown-offset values, missing seconds, dotted inline data, arrays of tables,
exact measure, encoding, and reparsing. Independent execution coverage in
`tests/extended_toml_execution.rs` uses the pinned official TOML test corpus,
typed value expectations, generated roundtrips, malformed UTF-8, public query
bounds, resource boundaries, and allocator fault injection. The corpus and
fixtures are test data; production TOML behavior resides in Lanius.
