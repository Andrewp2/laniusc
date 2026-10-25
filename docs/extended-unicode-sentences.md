# Unicode 17 default sentence boundaries

`ext::unicode_sentences` implements the complete default sentence boundary
rules SB1–SB998 in [UAX #29 revision 47, section 5.1](https://www.unicode.org/reports/tr29/tr29-47.html#Default_Sentence_Boundaries),
using the Unicode 17.0.0 `Sentence_Break` property data. Import it with the
optional `extended` source root. Production segmentation and property lookup
are Lanius and allocate no heap storage.

The default rules handle paragraph separators and CRLF, ignored Extend/Format
characters, ambiguous periods before numbers and initials, lowercase right
context, continuation punctuation, closing punctuation and trailing spaces.
They are language-independent defaults: for example, `Mr. Jones` can have a
boundary after `Mr. `, while `etc. leaders` does not. There is no abbreviation
dictionary, locale tailoring, normalization or linguistic sentence classifier.
All resulting spans are returned, including whitespace-only paragraph spans;
no bytes are trimmed or rewritten.

## Borrowed cursor API

```lanius
import core::option;
import ext::unicode_sentences;

// input is valid UTF-8 borrowed from a live, unchanged owner.
let scan = ext::unicode_sentences::cursor(input).unwrap();
while (true) {
    let next = scan.next();
    if (core::option::is_none(next)) { break; }
    let part = core::option::unwrap(next);
    // part.start..part.end are input-relative byte offsets.
    // part.text borrows exactly those original bytes.
}
```

| API | Meaning |
| --- | --- |
| `cursor(Text) -> Result<Cursor, Error>` | Cursor before the first span with default limits |
| `cursor_with_limits(Text, Limits)` | Same, with explicit input/work preflight |
| `Cursor.next() -> Option<Segment>` | Advance to the next nonempty span |
| `Segment { start, end, text }` | Half-open byte interval and borrowed `Text` |
| `count(Text) -> Result<i32, Error>` | Count all returned spans |
| `is_boundary(Text, index) -> Result<bool, Error>` | Test a byte offset using full input context |
| `default_limits() -> Limits` | Entire representable `Text` range and its conservative work reserve |

Types use `core::text::Text`, `core::result::Result` and `core::option::Option`.
Spans are contiguous and reconstruct the input byte for byte. Empty input has
no spans and count zero. After exhaustion, `next` always returns `None`.
Copying a cursor forks its position, prefix state and cached right context;
the two copies can advance independently. Cursor fields are implementation
state and must not be forged or mutated.

`is_boundary` returns false inside a UTF-8 scalar and `Error::Bounds` outside
`0..=input.byte_len()`. Both endpoints are accepted; the empty input has one
accepted endpoint at zero and no sentence spans. Each query scans from the
input's beginning; use a cursor to enumerate boundaries efficiently. Slicing a
`Text` creates a fresh input context. For example, `a.A` has no boundary before
`A` because of SB7, whereas the slice `.A` does.

As in the existing word and grapheme cursor APIs, input must already satisfy
the `Text` contract: valid UTF-8, physically backed selected bytes, and an owner
kept alive and unchanged while any cursor or returned span is used. Establish
this with `core::text::from_utf8` or `from_utf8_range` for untrusted input. The
constructor validates logical nonnegative/nonoverflowing `start` and `length`;
it cannot infer physical storage or make forged UTF-8 safe. Cursors and spans
borrow storage and require no destruction. This lifetime discipline is manual.

## Algorithm, bounds and errors

The cursor keeps raw-neighbor context for SB3/SB4, the last two nonignored
properties for SB6/SB7, and a suffix state for `SATerm Close* Sp*`. Paragraph
precedence is applied before ignoring marks. Consuming a paragraph separator
clears the suffix state, so marks after it do not propagate an old terminator
into later SB11 decisions. Rules after SB5 use the reduced property stream as
defined in [UAX #29 section 6.2](https://www.unicode.org/reports/tr29/tr29-47.html#Replacing_Ignore_Rules).

SB8 needs arbitrarily distant right context. A separate forward scan locates
the first letter, paragraph separator or sentence terminator and caches whether
it is Lower. Every candidate position up to that stopping scalar shares the
answer. A later search begins strictly after the previous stopping scalar;
long Close/Sp/ignored runs are not rescanned at each position. Each input
scalar is classified at most twice by iteration (including retry at a boundary)
and once by this lookahead. A complete scan is O(input bytes) with O(1) cursor
state and zero dynamic allocation. The static table contains 2,495 sorted
nondefault ranges, searched by binary search; its cost is fixed for this
Unicode version.

`Limits { max_bytes: i32, max_work: u64 }` is checked at construction:

- Negative/overflowing text metadata or negative `max_bytes`: `Bounds`.
- Input bytes exceed `max_bytes`: `InputLimit`.
- `3 * input.byte_len()` exceeds `max_work`: `WorkLimit`.

The work reservation is deliberately conservative. A unit represents one
UTF-8 scalar classification including its property lookup; it is **not** a
literal count of memory reads, bytecode operations or machine instructions.
At most three classifications per scalar are needed and the number of scalars
cannot exceed the byte length. Property lookup and UTF-8 decoding each have a
fixed bound per classification. The constructor does not revalidate UTF-8;
that earlier validation and the caller's processing of spans are outside this
budget. Once constructed, a cursor cannot fail partway through a scan. Each
copied cursor or new `count`/boundary query performs its own work; the reserve
is not a shared lifetime quota.

Default limits are `max_bytes = 2147483647` and `max_work = 6442450941`.
`count` cannot exceed the byte length, so its `i32` result cannot overflow.
An explicit work limit can reject a buffer even when an early stop would have
required less work. This is a preflight guarantee for a whole scan.

## Reproducible data and executed tests

[SentenceBreakProperty.txt](https://www.unicode.org/Public/17.0.0/ucd/auxiliary/SentenceBreakProperty.txt)
and [SentenceBreakTest.txt](https://www.unicode.org/Public/17.0.0/ucd/auxiliary/SentenceBreakTest.txt)
are vendored as sentence-family gzip files under `data/unicode/17.0.0` with
URLs, original/compressed SHA-256 hashes and the Unicode License v3 reference.
The generator verifies both datasets and creates
`extended/ext/unicode_sentences_data.lani`; no host Unicode database supplies
runtime properties. Generation does not use the conformance vectors to infer
rules. Reproduce or check with:

```sh
python3 tools/generate_unicode_sentences.py
python3 tools/generate_unicode_sentences.py --check
```

`tests/extended_unicode_sentences_execution.rs` compiles and executes native
Lanius fixtures. Its 8,589-case corpus includes all **512 official Unicode 17
sentence vectors**, a separate slow declarative rule oracle, 2,500 seeded
property-context strings, every property range's endpoints and neighbors,
paragraph/ignore/initial contexts and adversarial suffixes up to 90,003 bytes.
Long Close/Sp runs with both successful and failing lowercase lookahead exercise
the linear scan contract. The batch fixture checks view spans, byte reassembly,
counts, boundary queries, nonzero input offsets and permanent exhaustion while
`strace` denies every heap mapping and verifies that none is attempted.

A second fixture checks native strided bytes, packed literal/owned storage,
cursor forks, interior byte queries, sliced prefix context, empty input,
logical bounds and exact input/work limit thresholds. Verification covers
native x86_64 Linux emitted by the GPU compiler; other targets remain
unverified. Tests use Python only as an oracle, not for production behavior.
See [text-sentences](extended-text-sentences.md) for a real stream consumer.
