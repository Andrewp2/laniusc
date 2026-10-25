# Terminal text width

`ext::terminal::width(text, policy)` measures a borrowed `core::text::Text` and returns `Result<i32, Error>`. `options()` selects grapheme mode, narrow ambiguous characters, and 1,048,576 work units. No allocation, terminal probing, locale lookup, escape parsing, or I/O occurs.

This is **Lanius terminal width policy 1, Unicode 17.0.0**. Actual fonts and terminals can render differently. Callers should choose this policy only when it fits their output environment. Unicode's East Asian Width property alone does not specify terminal layout.

## Policy

The scalar policy uses these rules in order:

1. Reject General Category `Cc`, `Zl`, and `Zp`, and the Unicode `Bidi_Control` property. This includes NUL, tabs, CR/LF, DEL, C1 controls, ESC, and bidirectional overrides and isolates. `Control(at)` reports the first control's relative byte offset. ANSI sequences, including incomplete or malformed sequences, fail at their ESC or C1 introducer. The API never silently strips them.
2. Give every General Category mark (`Mn`, `Mc`, `Me`), format character (`Cf`), default ignorable, Hangul GCB `V`/`T`, and emoji modifier width zero. The first rule takes precedence over this rule.
3. Give East Asian Width `W` and `F` width two. Give `A` width two when `ambiguous_wide` is true, otherwise one.
4. Give every remaining scalar width one, including unassigned, noncharacter, and private use scalars unless an earlier property rule applies.

`Mode::Scalars` adds those scalar widths. It does not combine variation sequences or emoji sequences. `Mode::Graphemes` uses the existing Unicode 17 default extended grapheme cursor and takes the maximum scalar width within each cluster, with three additions:

- A listed emoji variation base immediately followed by VS15 has width one; followed by VS16 it has width two. The selector still has width zero. Eligible bases come from Unicode 17 `emoji-variation-sequences.txt`.
- A cluster containing two Regional Indicators has width two. A lone Regional Indicator has width one.
- A cluster starting with `#`, `*`, or an ASCII digit and containing U+20E3 has width two, with or without VS16.

The maximum rule keeps ordinary combining sequences, Indic conjuncts, Hangul syllable clusters, modifier sequences, and emoji ZWJ clusters within one cluster's cell width. It deliberately applies to all default extended graphemes, including sequences outside the RGI emoji set. It does not validate RGI sequences or implement script-specific font ligatures across clusters. For example, `👩‍💻` measures two in grapheme mode and four in scalar mode; `⌚︎` measures one and two respectively. An isolated mark or emoji modifier measures zero. No normalization occurs, so precomposed ambiguous characters can differ from their decompositions when `ambiguous_wide` is true.

## Bounds, work, and borrowing

The selected byte range must have physical backing. Keep its owner alive and unchanged until return. Logical range errors return `Bounds`; an overstated physical range can trap on indexing. The function validates UTF-8 in the selected range and returns `InvalidUtf8(at)` for malformed bytes. It ignores bytes outside that range. Negative `max_work` returns `Bounds`.

The policy budget charges exactly six logical units per selected input byte before scanning. These abstract units are not a count of decoder byte reads, property comparisons or machine instructions: validation, scalar decoding and grapheme/selector lookahead can revisit bytes. Property lookup uses bounded binary searches of static ranges. `WorkLimit` rejects a range exceeding `max_work / 6` before scanning. The inherited Unicode grapheme cursor checks its integer metadata but has no separate work limit; this preflight bounds the complete input passed to it. Width overflow returns `Overflow`. Runtime is linear in input bytes with a fixed property lookup factor and constant scratch space.

## Sources and verification

The policy uses [Unicode 17 UAX #11](https://www.unicode.org/reports/tr11/tr11-44.html), [UAX #29 revision 47](https://www.unicode.org/reports/tr29/tr29-47.html), and [Emoji 17 UTS #51](https://www.unicode.org/reports/tr51/tr51-29.html) for properties and sequence terminology. The [unicode-width implementation's documented rules](https://github.com/unicode-rs/unicode-width/blob/master/src/lib.rs) informed the scalar/sequence distinction. This policy intentionally uses the simpler maximum-per-grapheme rule and rejects controls; it does not claim identical behavior to that library.

`tools/unicode17/generate_terminal.py` transforms pinned UCD data into `extended/ext/terminal_data.lani`; Python performs no production width calculation. See `data/unicode/17.0.0/terminal-SOURCES.md` for provenance. Run the generator with `--check` to verify reproducibility. Focused execution tests compare all property interval representatives against an independent source-data model, exercise sequence/control/invalid UTF-8 vectors and long clusters, and deny all allocations while measuring.
