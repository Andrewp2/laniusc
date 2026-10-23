# Text parsing cursors

`ext::parse` is a reusable allocation-free foundation for hand-written parsers.
It operates on counted UTF-8, returns borrowed lexemes and source spans, and
provides concrete scanners without function values or closure combinators.
`sample_programs/library/expr_calc.lani` demonstrates a checked integer expression parser
using the cursor and caller-backed stacks.

## Input and storage

`new(text, limits)` checks logical `Text` bounds and validates every UTF-8
sequence, including text constructed with `from_utf8_unchecked` or a record
literal. `from_utf8_range(bytes, start, count, limits)` does the same directly
from a counted byte view. Invalid UTF-8 reports the malformed sequence's start
relative to the selected range. NUL is an ordinary scalar and never terminates
input. Negative starts/counts, overflowing start plus count, negative scan
limits, and source lengths of `i32::MAX` are rejected. The last restriction
keeps one-based line and column arithmetic representable.

As with `core::text` and `core::slice`, the caller must provide physically backed
storage for the claimed logical range. An overclaim that passes logical checks
can trap during native indexing. The module cannot inspect physical slice
length metadata. Both native arrays and raw byte views are supported with
their own strides. Keep backing storage alive and unchanged while a cursor,
checkpoint or span is used. Lanius does not enforce these lifetime and
immutability rules yet.

The module imports only `core` modules. It does not allocate, own, copy or free
source storage. A `Cursor` value copy forks its position and work budget;
`borrow()` lets helpers operate on the actual cursor. `Span.text` borrows the
original source. `Span.bytes()` returns a `core::slice::View<u8>` over that
lexeme for existing counted-byte algorithms.

## Position, lookahead and failure

`Location { offset, line, column }` contains a zero-based byte offset and
one-based line and Unicode-scalar column. CR and LF each start a line; CRLF
starts one line, including when consumed across separate calls. After CR the
location is already on the next line at column one; consuming its following LF
keeps that location's line and column. Tabs, combining marks, NUL, Unicode line
separators and all other scalars each advance the column by one. Columns are
neither display cells nor grapheme counts.

`peek_scalar()` returns `Result<Option<u32>, Error>` without advancing input.
`take_scalar()` returns the same shape and advances one complete scalar.
`Ok(None)` means EOF; malformed input, scan limits and exhausted work are
errors. EOF is fused until a checkpoint is restored. `peek_byte()` is constant
lookahead of the first UTF-8 byte at the current scalar boundary; it returns
`None` at EOF and consumes no work.

Every failed consuming operation preserves the complete input position,
including line, column and CRLF state. A multi-scalar tag or number never leaves
a partial match consumed. `Error { kind, location }` identifies the failing
scalar or EOF, even though the cursor itself remains at the operation's start.
Exact matching uses `Expected` for a mismatch and `UnexpectedEnd` for EOF.
Empty required identifier/digit scans distinguish those cases too. Malformed
numeric syntax uses `InvalidNumber`; `integer_i64()` reports `Overflow` at the
first overflowing digit.

A checkpoint records position and CRLF state and is bound to the exact source
view: backing data pointer, stride, logical start and logical length.
`restore(mark)` rejects a mark from a different view with `ForeignCheckpoint`,
without changing position. Forks and independently constructed cursors over the
same exact source view can exchange marks. A mark is an opaque value; callers
must not edit its fields. Restore can move backward or forward among saved
positions, and returns the restored byte offset. Its range and scalar boundary
checks protect against invalid offsets; it does not revalidate forged cached
line/column fields.

## Concrete primitives

| Operation | Contract |
| --- | --- |
| `take_byte(byte)` | Require one ASCII scalar equal to `byte`; values above 127 are `Bounds`. |
| `tag(text)` | Require exact counted UTF-8 text. Empty tags succeed. No normalization or case folding. The expected text must be valid UTF-8. |
| `take_text(count)` | Require exactly `count` bytes ending at a scalar boundary. Negative counts or splitting a scalar are `Bounds`; insufficient input is `UnexpectedEnd`. |
| `whitespace()` | Consume a maximal possibly empty run of ASCII HT, LF, VT, FF, CR or space. |
| `identifier()` | Consume `[A-Za-z_][A-Za-z_0-9]*`, requiring at least one character. |
| `digits()` | Consume a maximal nonempty `[0-9]+` run, without conversion. |
| `integer()` | Consume `[+-]?[0-9]+` as a borrowed lexeme. |
| `decimal()` | Consume `[+-]?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?` as a borrowed lexeme. |
| `integer_i64()` | Scan the complete integer lexeme, then convert exactly with `core::text::Text.parse_i64()` / `core::decimal`. |
| `scan_until(scalar)` | Consume a maximal possibly empty run before the scalar, leaving the delimiter. EOF succeeds with the remaining text. Invalid delimiter scalars are `Bounds`. |

Scanners leave their first nonmatching scalar untouched. They choose the
longest prefix in their stated grammar, without a separate token-boundary
rule: `integer()` on `12abc` returns `12`, and `decimal()` on `1.2.3` returns
`1.2`. A recognized decimal point or exponent commits the lexical requirement
for subsequent digits: `1.`, `1e` and `1e+!` fail atomically, rather than
silently returning the earlier numeric prefix. Leading zeros and a leading
plus are accepted. `.5`, `NaN`, infinity, hexadecimal, digit separators,
Unicode digits and Unicode identifiers are outside these grammars. Unicode
whitespace remains ordinary input.

Numbers are scanned before conversion; a long overflowing integer still
requires a complete bounded token scan. Integer conversion reuses the core
checked parser and does not pass through floating point. Decimal scanning
preserves exact original spelling and does no rounding. For binary32/binary64
conversion, pass `Span.bytes()` to `core::float_decimal::parse_f32` or
`parse_f64` with the existing caller-provided scratch and conversion limits.
That codec owns its conversion errors and limits; the cursor owns lexical
errors and source positions.

## Bounds and work

`Limits { max_scan_bytes, max_work }` supplies a per-operation consumed-byte
ceiling and a total cursor work budget. Defaults are 1,048,576 bytes per scan
and 16,777,216 work units. A scanner reaching its ceiling succeeds if the next
scalar terminates its token or it reaches EOF; another accepted scalar causes
`ScanLimit` at that scalar, with input position unchanged. Zero permits empty
scans and EOF inspection. Exact tags and text takes use the same byte limit.
The constructor validates the whole selected source under the work budget;
it is not restricted by the per-operation scan ceiling.

Decoding charges the scalar's UTF-8 byte width, including lookahead that
terminates a scan. Checking a tag also charges its compared expected bytes;
integer conversion charges the token byte length before calling the core
converter. EOF probes, metadata access, `peek_byte`, checkpoint creation and
restore consume zero work. A scalar read with insufficient remaining work
returns `WorkLimit` at that scalar and exhausts the remaining budget.

Work consumption persists on errors and restore. Input state is atomic;
resource spending is monotonic. Repeated failed alternatives cannot reset their
work by restoring a mark. A new cursor or an explicit value copy has its own
budget, so callers must bound how many independent forks they create. The
module has no recursive parser machinery, exponent-sized loops or unbounded
search outside source/scanner limits. Complete scalar validation and scans
are linear in their inspected bytes; restoring a valid mark is constant work.

## Design sources and deliberate choices

The design follows the stream/checkpoint and non-consuming lookahead concepts
in the primary [Winnow `Stream` documentation](https://docs.rs/winnow/1.0.4/winnow/stream/trait.Stream.html)
and [`peek` documentation](https://docs.rs/winnow/1.0.4/winnow/combinator/fn.peek.html).
Winnow documents scalar tokens for string streams, byte-based slice offsets,
saved parse locations, and reset; its reset may panic for an invalid mark.
This cursor deliberately checks source provenance and returns explicit
errors, validates counted UTF-8 at construction, tracks locations, and makes
each concrete consuming primitive atomic. It has no streaming-incomplete
mode, closure combinators or implicit global backtracking/error modes.
[`opt`](https://docs.rs/winnow/1.0.4/winnow/combinator/fn.opt.html) informed the
separation of successful absence from parse failure; here absence is only
`Option` on scalar/byte EOF, while required tokens use `Result` errors.

## Native evidence

`tests/extended_parse_execution.rs` compiles real Lanius fixtures and executes
their native x86-64 output. The contract fixture covers exact i64 endpoints,
overflow offsets, malformed logical views/UTF-8, borrowed spans, failed token
atomicity, foreign marks, and work that remains exhausted after restore.
A separate Rust reference uses its UTF-8 decoder, prefix-based location
calculation and independent token selection to compare thousands of operation
sequences, including checkpoints across CRLF and multibyte scalars, NUL,
longest tokens, malformed numeric suffixes, and byte scan ceilings. Both
executables run under `strace` with all `mmap` requests denied and assert an
empty allocation trace.

Verified execution is x86_64 Linux output from the GPU compiler. Other targets
and user GPU kernels have not been verified.
