# Unicode 17 word boundaries

`ext::unicode_words` segments borrowed UTF-8 text using the default word
boundary rules in [UAX #29 revision 47, section 4.1](https://www.unicode.org/reports/tr29/tr29-47.html#Default_Word_Boundaries)
and the complete Unicode 17.0.0 property data. It implements WB1–WB999,
including newlines, emoji ZWJ sequences, horizontal spaces, ignored marks
and formatting characters, letters, Hebrew quotes, numeric punctuation,
Katakana, connecting punctuation and regional indicator pairing.

Every segment is returned, including spaces and punctuation. For example,
`can't stop!` yields `can't`, ` `, `stop`, `!`. `count` therefore counts
segments. Applications that need a count of lexical words must choose their
own criteria for including segments. There is no dictionary analysis,
locale tailoring, normalization or sentence segmentation.

```lanius
import core::option;
import core::result;
import core::text;
import ext::unicode_words;

// `text` is valid core::text::Text borrowed from a live owner.
let scan: ext::unicode_words::Cursor =
    core::result::unwrap(ext::unicode_words::cursor(text));
let current: core::option::Option<ext::unicode_words::Segment> = scan.next();
while (core::option::is_some(current)) {
    let segment: ext::unicode_words::Segment = core::option::unwrap(current);
    // segment.start and segment.end are byte offsets relative to `text`.
    // segment.text borrows exactly those bytes from the same backing storage.
    current = scan.next();
}
```

| API | Behavior |
| --- | --- |
| `cursor(text) -> Result<Cursor, Error>` | Start before the first segment. |
| `Cursor.next() -> Option<Segment>` | Return one nonempty segment and advance. |
| `Segment { start, end, text }` | Half-open byte span and borrowed text. |
| `count(text) -> Result<i32, Error>` | Count all segments. |
| `is_boundary(text, index) -> Result<bool, Error>` | Test an input byte offset with its full prefix context. |

The actual types use `core::text::Text`, `core::result::Result` and
`core::option::Option`. Empty input returns no segments and a count of zero.
After exhaustion, every `next()` returns `None`. Copying a cursor forks its
position and retained context; either copy can advance independently. The
returned spans are contiguous and reassemble the input byte for byte.

`is_boundary` returns `false` inside UTF-8 scalars and `Error::Bounds` for
offsets outside `0..=text.byte_len()`. Start and end are boundaries, including
the single offset zero for empty input. Each query scans from the start;
use a cursor to enumerate many boundaries efficiently. A sliced `Text` is
a new input with fresh context. For example, slicing a regional indicator
run can change its pairing.

All three operations allocate nothing. A cursor retains the immediate
previous property, the last two nonignored properties and regional indicator
parity. Rules before WB4 use immediate neighbors; rules after WB4 use the
stream with Extend, Format and ZWJ ignored as specified in section 6.2.
Punctuation rules look ahead to the next nonignored property. Each scalar
is examined at most twice in the main iteration and at most once by
lookahead. A full scan therefore uses at most three scalar examinations per
input scalar, O(bytes) time and O(1) cursor storage. Long ignored runs are
never rescanned from their beginning for each mark. A caller that charges
scalar examinations can conservatively reserve `3 * byte_len` for one full
scan; this excludes its own work and counts a property lookup as one
examination. Lookups search 1,258 disjoint ranges in a read-only ASCII
string, with a fixed maximum cost for this Unicode version.

Input must obey the `core::text::Text` contract: valid UTF-8, live physical
backing for the selected range, and an owner kept alive and unchanged during
all cursor and segment uses. Use `core::text::from_utf8` or `from_utf8_range`
to validate untrusted bytes. The constructor rejects negative or overflowing
logical metadata with `Error::Bounds`; it cannot infer physical backing or
validate forged UTF-8 metadata. Cursor fields are implementation state and
must not be forged or changed. Lanius does not enforce these lifetime and
immutability rules.

The implementation and property lookup are Lanius. The build-time generator
`tools/unicode17/generate_words.py` transforms the vendored
`auxiliary/WordBreakProperty.txt.gz` and `emoji/emoji-data.txt.gz` under
`data/unicode/17.0.0/`. It checks their original and compressed SHA-256 hashes
against that directory's manifest. The directory also records source URLs
and the Unicode license. No host Unicode database, ICU, regex engine or
Python Unicode library supplies runtime behavior. Regenerate or verify with:

```sh
python3 tools/unicode17/generate_words.py
python3 tools/unicode17/generate_words.py --check
```

`tests/extended_unicode_words_execution.rs` executes all 1,944 official
Unicode 17 `WordBreakTest` vectors and adversarial long Extend, Format, ZWJ,
regional indicator and punctuation sequences. It checks span reassembly,
counts, byte boundary queries, native strided and packed backing, nonzero
input offsets, sliced context, cursor copies, empty input, repeated
exhaustion and logical bounds errors. The corpus executes with every heap
mapping denied and checks that no allocation is attempted. Verification
covers native x86_64 Linux emitted by the GPU compiler; GPU execution and
other targets remain unverified.
