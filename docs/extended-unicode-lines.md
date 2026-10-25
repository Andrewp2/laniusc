# Unicode line break opportunities

`ext::unicode_lines` implements the **complete Unicode 17.0.0 default line
breaking algorithm**, UAX #14 revision 55, rules LB1–LB31. It reports legal
opportunities; it does not measure glyphs, choose line lengths, insert hyphens,
shape text, or discover a terminal's behavior.

```lani
let scan: ext::unicode_lines::Cursor = ext::unicode_lines::cursor(
    text,ext::unicode_lines::default_limits()).unwrap();
// scan.next() returns Option<Opportunity { offset, kind }>.
```

Offsets are input-relative UTF-8 byte offsets. `Kind::Allowed` is a soft
opportunity; `Kind::Mandatory` follows a hard separator or denotes end of text.
There is no opportunity at the start of nonempty text. End of text is returned
exactly once, including `Mandatory` at offset zero for empty text. Repeated calls
after exhaustion return `None`. The EOT marker does **not** prescribe adding a
newline byte; line fitting and output formatting decide that separately.

`opportunity_at(text,offset,limits)` performs at most one full scan. It returns
`None` for a prohibited position or an interior UTF-8 byte, and a kind for a
legal boundary. Out-of-range positions are `Bounds`. Calling it separately at
every input position would repeat prefix scans; use the cursor for a full pass.

## Default behavior

The implementation preserves rule order, including CR×LF and all mandatory
breaks, zero-width spaces and joiners, combining sequences, space-sensitive
punctuation and quotations, numeric expressions, Hangul, Indic orthographic
syllables (AK/AP/AS/VF/VI and dotted circle), RI parity, and emoji modifiers.
Raw-neighbor rules precede combining-mark reduction. Marks ignored by LB9 keep
their base's class **and auxiliary properties**; remaining CM/ZWJ receive all
the properties of U+0041 as required by LB10.

Default LB1 resolution maps AI/SG/XX to AL, CJ to NS, SA with Mn/Mc category to
CM and other SA to AL. Thus this is the specified default without language
tailoring or dictionary analysis, including for Thai and similar SA scripts.
Unresolved CB retains its default break-before/break-after behavior. This API
does not apply CLDR, CSS, locale, normalization, or emergency-breaking tailoring.

## Limits, lifetime, and complexity

`Limits { max_bytes, max_scalars, max_work }` defaults to 4,194,304 selected input
bytes, 1,048,576 scalars and 134,217,729 work units. Byte/scalar limits must be
nonnegative and at most `MAX_BYTES = 67,108,864`. `work(byte_length)` exposes
the exact charge `32*byte_length+1`, checked before decoding. These are abstract
policy units, **not physical read counts or CPU instructions**. Equality with
each limit succeeds. UTF-8 validation and scalar counting occur during cursor
construction, so byte/work/scalar/encoding failures happen before iteration.

Each complete pass is O(input bytes) with constant state and no heap allocation.
Static range lookups have a fixed version-specific bound. Prior effective
tokens, non-space context, initial-quote state, a numeric suffix and RI parity
are retained. Lookahead is bounded to at most three significant tokens and
skips mark runs; only a fixed number of preceding significant bases can inspect
any run. No rule repeatedly scans an unbounded prefix or space/numeric run.

Copying a cursor forks its position and retained context. A work limit bounds
one construction plus complete iteration; copying/restarting cursors permits
additional passes and does not share a consumable global budget.

The selected `Text` is revalidated as UTF-8, including fabricated metadata.
Logical start/length must be nonnegative with their sum fitting `i32`. The caller
must still provide live physical backing for the entire range, unchanged for
the cursor's lifetime. Logical checks cannot prove backing or lifetime. Cursor
fields are implementation state: construct through `cursor` and do not mutate
them. Errors are `Bounds`, `InvalidLimits`, `ByteLimit`, `ScalarLimit`,
`WorkLimit`, and `InvalidUtf8(input_relative_offset)`.

## Data and verification

Primary sources are [Unicode 17 UAX #14 revision 55](https://www.unicode.org/reports/tr14/tr14-55.html),
especially §§6.1–6.2, the normative [DerivedLineBreak](https://www.unicode.org/Public/17.0.0/ucd/extracted/DerivedLineBreak.txt),
[General_Category](https://www.unicode.org/Public/17.0.0/ucd/extracted/DerivedGeneralCategory.txt),
[EastAsianWidth](https://www.unicode.org/Public/17.0.0/ucd/EastAsianWidth.txt), and
[emoji properties](https://www.unicode.org/Public/17.0.0/ucd/emoji/emoji-data.txt).
Nested `@missing` defaults are applied before explicit assignments. Static data
includes default LB1 class resolution, East_Asian_Width F/W/H, Pi/Pf categories,
unassigned Extended_Pictographic and U+25CC; Hangul classes use exact arithmetic.

All source files, the complete corpus, rule chart and specification are retained
under `data/unicode/17.0.0/unicode-lines-*`, with the original notices,
`LICENSE.txt`, exact uncompressed SHA-256/size/URL manifest, and deterministic
gzip timestamps. `python3 tools/generate_unicode_lines.py --check` verifies
hashes and reproduces `unicode_lines_data.lani` offline. The generator transforms
static data only; production segmentation is Lanius.

Native tests execute **all 19,338 official** [Unicode 17 LineBreakTest](https://www.unicode.org/Public/17.0.0/ucd/auxiliary/LineBreakTest.txt)
vectors, check mandatory status independently, and cover empty input, limits,
UTF-8 errors, offset views, cursor forks and long combining/quotation/space/
numeric/Indic/RI contexts. Allocation denial confirms that cursor operations
allocate no heap storage. [Text wrapping](extended-text-wrap.md) composes these
opportunities with the existing terminal width policy.
