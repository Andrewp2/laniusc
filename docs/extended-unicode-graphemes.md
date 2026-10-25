# Unicode 17 grapheme clusters

`ext::unicode_graphemes` segments borrowed UTF-8 text into default extended
grapheme clusters using Unicode 17.0.0 and
[UAX #29 revision 47, section 3.1](https://www.unicode.org/reports/tr29/tr29-47.html#Grapheme_Cluster_Boundaries).
It implements GB1–GB999, including CR/LF and controls, conjoining Hangul and
Kirat Rai sequences, extending and spacing marks, prepend characters, Indic
conjuncts (GB9c), emoji ZWJ sequences, and regional indicator pairing.

These are the default rules with the complete Unicode 17 property repertoire.
There is no locale tailoring, legacy grapheme mode, normalization, word or
sentence segmentation. A grapheme cluster approximates a user-perceived
character; it does not describe font glyphs or display width.

```lanius
import core::option;
import core::result;
import core::text;
import ext::unicode_graphemes;

// `text` is a valid core::text::Text borrowed from a live owner.
let scan: ext::unicode_graphemes::Cursor =
    core::result::unwrap(ext::unicode_graphemes::cursor(text));
let current: core::option::Option<ext::unicode_graphemes::Cluster> = scan.next();
while (core::option::is_some(current)) {
    let cluster: ext::unicode_graphemes::Cluster = core::option::unwrap(current);
    // cluster.start and cluster.end are byte offsets relative to `text`.
    // cluster.text borrows exactly that cluster from the same backing storage.
    current = scan.next();
}
```

| API | Behavior |
| --- | --- |
| `cursor(text) -> Result<Cursor, Error>` | Start before the first cluster. |
| `Cursor.next() -> Option<Cluster>` | Return one nonempty cluster, then advance. |
| `Cluster { start, end, text }` | Half-open byte span and borrowed cluster text. |
| `count(text) -> Result<i32, Error>` | Count all clusters by scanning from the start. |
| `is_boundary(text, index) -> Result<bool, Error>` | Scan from the start to test a byte offset with its full prefix context. |

The actual signatures use `core::text::Text`, `core::result::Result`, and
`core::option::Option`. Empty input yields no clusters and a count of zero.
`next()` returns `None` repeatedly after exhaustion. Copying a cursor forks
its position and context; either copy can advance independently. Returned
spans are contiguous and reassemble the input without changing any bytes.

`is_boundary` returns `false` at interior UTF-8 bytes and `Error::Bounds`
outside `0..=text.byte_len()`. The start and end are boundaries, including
the single offset zero for empty text. Repeating boundary queries rescans
the prefix; use a cursor to enumerate many boundaries efficiently. A sliced
`Text` is a new text whose context starts at that slice's beginning.

The cursor and both queries allocate nothing. A full scan takes O(bytes)
time with fixed Unicode 17 tables and O(1) cursor state. Each scalar is
decoded at most twice. Regional indicator parity, emoji prefixes, and Indic
conjunct prefixes use bounded state; long Extend, ZWJ, and RI runs do not
rescan earlier input. Property lookup uses binary search over 833 disjoint
ranges held in a read-only ASCII string; modern Hangul syllables use an
arithmetic lookup. There are no per-query initialized property arrays.

Input must obey the `core::text::Text` contract: valid UTF-8, live physical
backing for the selected byte range, and an owner kept unchanged during all
cursor and cluster uses. Construct untrusted input with
`core::text::from_utf8` or `from_utf8_range`. The cursor constructor rejects
negative or overflowing logical metadata with `Error::Bounds`; it cannot
infer physical backing or validate forged UTF-8 metadata. Cursor fields are
implementation state and must not be forged or changed. Lanius does not yet
enforce these borrow and immutability rules.

The implementation is entirely Lanius. The build-time generator
`tools/unicode17/generate_graphemes.py` transforms the vendored
`GraphemeBreakProperty.txt.gz`, `DerivedCoreProperties.txt.gz` (`InCB`), and
`emoji/emoji-data.txt.gz` (`Extended_Pictographic`) under
`data/unicode/17.0.0/`. That directory includes the official source URLs,
SHA-256 hashes, and Unicode license. No host Unicode database, ICU, regex
engine, or Python library is used by the implementation. Regenerate and
check the table with:

```sh
python3 tools/unicode17/generate_graphemes.py
python3 tools/unicode17/generate_graphemes.py --check
```

`tests/extended_unicode_graphemes_execution.rs` executes all 766 official
Unicode 17 `GraphemeBreakTest` vectors, plus long context sequences, cluster
reassembly, native and packed views, nonzero input offsets, cursor copying,
empty input, repeated exhaustion, and logical bounds errors. A traced corpus
run rejects every attempted heap mapping and confirms there are none.
Executable verification covers native x86_64 Linux emitted by the GPU
compiler; GPU execution and other targets are unverified.
