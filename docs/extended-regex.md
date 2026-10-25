# UTF-8 regular expressions

`ext::regex` compiles and executes regular expressions in Lanius. It uses an
ordered Thompson/Pike NFA, with no backtracking or host regex calls. Native
execution is verified on x86_64 Linux. The algorithms use portable text, Unicode
and allocation modules; other targets have not been verified.

The implementation follows [Russ Cox's VM and Pike matching description](https://swtch.com/~rsc/regexp/regexp2.html),
including prioritized epsilon expansion, first-arrival state deduplication,
and retaining a candidate match until higher priority threads fail. Its syntax
is a documented subset of [RE2 syntax](https://github.com/google/re2/wiki/Syntax).
Nullable stars use `(body+)?`, as in the
[Go regexp compiler](https://go.dev/src/regexp/syntax/compile.go), to preserve
priority when a repeated body can match empty text.

## API and ownership

```lani
let config: ext::regex::Options = ext::regex::options();
let regex: ext::regex::Regex = core::result::unwrap(ext::regex::compile(pattern, config));
let matched: bool = core::result::unwrap(regex.is_match(input));
let found: core::option::Option<ext::regex::Match> = core::result::unwrap(regex.find(input));
// Destroy a returned Match exactly once when Some; it owns its capture spans.
regex.destroy();
```

`pattern` and `input` are `core::text::Text`. Compilation copies its program
and class terms, so the pattern backing may be released after compilation.
Search retains no input storage in a returned `Match`. Each `Regex` and `Match`
has one manual owner: copying a record aliases its allocations. `destroy()`
releases those allocations; it is not automatic or compiler-enforced.

| API | Contract |
| --- | --- |
| `compile(Text, Options) -> Result<Regex, Error>` | Compile an independent owned program. |
| `Regex.borrow() -> &Regex` | Borrow the compiled owner for helper calls. |
| `Regex.group_count() -> i32` | Number of captures **including group 0**. |
| `Regex.state_count() -> i32` | Number of compiled NFA instructions. |
| `Regex.search_work_limit() -> i32` | Configured per-search `Options.max_work`; used by aggregate-budget adapters. |
| `Regex.find(Text) -> Result<Option<Match>, Error>` | First match, or ordinary absence. |
| `Regex.find_from(Text, i32) -> Result<Option<Match>, Error>` | Search at or after a scalar boundary; anchors retain the whole input context. |
| `Regex.is_match(Text) -> Result<bool, Error>` | Search and release temporary capture storage. |
| `Regex.find_iter(Text) -> Result<Matches, Error>` | Validate input and create a cursor borrowing input and compiled storage. |
| `Match.group_count() -> i32` | Same count as the compiled regex, including group 0. |
| `Match.span(i32) -> Option<Span>` | Capture `{start,end}` or None for an absent group or invalid group number. |
| `Matches.next() -> Result<Option<Match>, Error>` | Transfer a newly owned capture set to the caller, or return None/error. |
| `Regex.destroy()`, `Match.destroy()` | Release the owned allocations. |
| `Matches.destroy()` | Fuse the cursor; it retains no allocation between calls. |

[Bounded splitting and replacement](extended-regex-text.md) consume the same
Matches cursor. Their guide defines borrowed fields, numeric replacement
templates, owned output and conservative aggregate search accounting.

Spans are half-open **byte** offsets relative to the supplied input Text, not
its underlying allocation. Every endpoint is a Unicode scalar boundary. Group
0 is the whole match; other groups are numbered by opening parenthesis. An
unmatched optional group is None, distinguishable from a matched empty group.
A repeated capture records the last participating traversal retained by Pike
priority; groups skipped in a later traversal retain their earlier values.

The cursor searches from the preceding match end. After an empty match it
advances by **one Unicode scalar**, or becomes exhausted after the final empty
match at EOF. Consequently `|a` on `a` yields `[0,0]` and `[1,1]`; it does not
also yield a nonempty match at the same position as that empty match. After a
nonempty match, an empty match at its end is permitted. `next` is fused after
None, error, or destroy. Every returned Some has independent capture storage,
which the caller destroys. Cursor copies fork their positions and share the
borrowed compiled and input storage. Keep both backing owners alive and
unchanged until all cursors are done. Calling `next` does not revalidate that
borrowed input.

Text metadata must physically back its claimed range, just as in
`core::text`. Compilation, find/find_from/is_match and find_iter validate
logical bounds and UTF-8, including forged logical Text records. Native
strided slices and packed storage both work. A physically overstated slice
can trap; this language cannot establish a slice's real allocation length.
Do not forge or mutate internal program, match, or cursor fields, or use a
destroyed regex/match. Public fields do not imply a stable storage format.

## Dialect

Matching is leftmost-first: prefer the earliest start, then the left branch of
alternation and the preferred branch of each quantifier. Greedy quantifiers
prefer more repetitions; a trailing `?` reverses that preference. This is not
POSIX leftmost-longest matching. No implicit normalization or casing occurs.

| Syntax | Meaning |
| --- | --- |
| UTF-8 scalar, including NUL | Literal scalar, except metacharacters below. |
| `xy`, `x|y` | Concatenation, alternation (prefer x). Empty branches are valid. |
| `(x)`, `(?:x)` | Numbered capture, noncapturing group. |
| `x?`, `x*`, `x+` | Zero/one, zero/more, one/more. |
| `x{n}`, `x{n,}`, `x{n,m}` | Exact, at least, or inclusive bounded count; decimal digits and no whitespace. |
| `x??`, `x*?`, `x+?`, `x{n,m}?` | Lazy forms, also valid for exact and open counts. |
| `.` | One scalar, excluding LF unless `dot_matches_newline` is true. |
| `[abc]`, `[^abc]`, `[a-z]` | Union, complement, inclusive scalar range. |
| `^`, `$` | Start/end of text; also after/before LF when multiline is true. |
| `\A`, `\z` | Absolute start/end of text. |
| `\b`, `\B` | ASCII word boundary and its complement, including EOF/BOF. |
| `\d`, `\D` | ASCII `[0-9]` and complement. |
| `\s`, `\S` | ASCII HT, LF, FF, CR and space, and complement (VT is excluded). |
| `\w`, `\W` | ASCII letters, digits and underscore, and complement. |
| `\a \f \t \n \r \v` | Bell, form feed, tab, LF, CR and vertical tab literals. |
| `\xHH`, `\x{H...}` | Exactly two hex digits, or one to six braced digits; must encode a Unicode scalar. |
| `\` + ASCII punctuation | Escaped literal punctuation, e.g. `\[`, `\-`, `\\`. |
| `\pL`, `\p{Lu}`, `\P{Alphabetic}` | Unicode property or complement. |

Quantifiers bind more tightly than concatenation, which binds more tightly
than alternation. Quantifiers can apply to assertions or empty groups as well
as consuming expressions. Class terms can be literals, escaped literals,
ranges whose endpoints are literals, or shorthand/property classes. A class
must contain at least one term. `]` must be escaped inside a class. A trailing
hyphen is literal; a hyphen following a literal and preceding another term
introduces a range. Ranges include all scalar code points between their
endpoints, including supplementary planes; surrogate values can never occur
in valid input. A nested unescaped `[` is unsupported.

`$` without multiline is a strict end-of-text assertion: it does not match
before a final LF. CR is an ordinary scalar for dot and anchors. Multiline
adds only LF boundaries. Flags are set through Options; inline flag syntax is
unsupported. ASCII boundary semantics also mean `\b` does not surround a
standalone non-ASCII letter. `\B` matches the empty input's sole boundary.

Unicode properties use **Unicode 17.0.0** from `core::unicode`. Names are case
sensitive. Supported exact general categories are:

```text
Cn Lu Ll Lt Lm Lo Mn Mc Me Nd Nl No Pc Pd Ps Pe Pi Pf Po
Sm Sc Sk So Zs Zl Zp Cc Cf Cs Co
```

The aggregates `L M N P S Z C` and binary properties `Alphabetic`,
`White_Space`, `XID_Start`, `XID_Continue` are supported. `Cs` has no matches
in valid UTF-8; Cn and Co include unassigned scalars and private use scalars.
Unknown properties, script properties and long category aliases are
unsupported. `\P` complements a single property; `[^...]` complements the
whole union. Binary properties and general categories retain their distinct
Unicode meanings.

The VM suppresses repeated visits to the same instruction at a single input
position. Empty cycles terminate without another traversal of that state.
Thus `(a*)*` on `aa` captures `aa`, and `(a?)*` captures its final `a`, rather
than Python's additional final empty iteration. At EOF, a new search can
capture the empty group. This is the documented Pike cycle convention. It can affect whole match
spans as well: `(?:a?|b)*` on `ab` matches both scalars, while Python stops
after `a`. These whole-match and capture choices follow this implementation's
RE2/Pike cycle policy.
Nullable branch priority still matters: `(?:|a)*` and `(?:|a)+` prefer an
empty match on `a`.

Unsupported constructs return an explicit error: lookaround, backreferences
(including numeric and named forms), named groups, inline flags, possessive
quantifiers, atomic groups, comments, POSIX named classes, script properties,
byte-mode `\C`, octal escapes, `\Q...\E`, `\Z`, and unknown alphanumeric
escapes. They are never accepted as literal approximations. Unbalanced groups,
malformed classes/ranges/counts/hex escapes, stray metacharacters and repeated
quantifiers return Syntax. Escape literal metacharacters
`.*+?()[]{}^$|\` to match them literally.

## Limits, errors and complexity

| Options field | Default | Accepted range |
| --- | ---: | --- |
| `multiline` | false | bool |
| `dot_matches_newline` | false | bool |
| `max_pattern_bytes` | 65536 | 0..65536 |
| `max_states` | 4096 | 4..65536 |
| `max_depth` | 64 | 1..256 |
| `max_captures` | 16 | 0..128, excluding group 0 |
| `max_repeat` | 1000 | 0..1000000 |
| `max_work` | 10000000 | 1..2147483647 |

`max_depth` limits only parenthesis nesting and native parser recursion.
Concatenation, alternation and compilation use loops or explicit frames.
`max_states` independently limits AST nodes, compilation frame count, and
expanded instructions. Counted repetitions expand their bodies subject to
this limit. Compilation also stops after `32 * max_states` frame steps, so
huge nested repetitions of empty expressions cannot bypass bounds by emitting
few instructions. `max_repeat` limits every explicit minimum/maximum count;
unbounded `*`/`+` do not use a numeric repeat count.

`max_work` applies separately to each find/find_from/is_match or iterator
next. It charges each newly visited epsilon/consuming state and each tested
class term. UTF-8 validation, scratch initialization, per-boundary seen-array clearing,
and capture copying are
outside that counter; their sizes are bounded separately. A limit error does
not imply a partial match. Earlier matches already returned by a cursor stay
valid if a later next hits a limit.

| Error | Meaning |
| --- | --- |
| `Syntax(byte_offset)` | Invalid grammar, offset relative to the pattern. |
| `Unsupported(byte_offset)` | Recognized unsupported syntax or unknown property/escape. |
| `Limit(byte_offset)` | Invalid options or compile resource bound; offset is 0 when no single source location identifies expansion failure. |
| `AllocationFailed` | Compilation/search storage allocation failed; partial owners have been released. |
| `Bounds` | Invalid Text integer metadata or non-boundary/out-of-range find_from index. |
| `InvalidUtf8(byte_offset)` | Malformed selected Text range; offset relative to pattern or search input for the failing operation. |
| `WorkLimit` | Search exhausted its VM work budget. |

For fixed compiled pattern, each search scales linearly with input length.
Unanchored search adds a lower priority start at each scalar boundary in the
same pass; it does not restart a whole-input scan at each position. Each PC is
visited once per boundary. With S instructions, C capture slots, P stored
class terms and T the sum of class-term counts over compiled instructions,
search is O(N * (S*C + T)) and uses O(S*C + P) scratch/program storage.
Counted repetitions can share stored terms, so T can be larger than P.
Scalar validation is O(N). Each next performs a new bounded search;
a whole iteration can rescan suffixes while resolving greedy alternatives,
so no linear bound is claimed for the sum of all next calls. Matching uses
an explicit bounded stack, never native recursion.

The focused native tests compare over a thousand grammar-generated/shared
cases with Python `re`, with byte-span conversion and the same scalar progress
policy. Additional cases cover Unicode properties, nullable priority/capture
semantics, native strides, malformed UTF-8, subviews, ownership, all resource
bounds, long nested repetitions, and injected allocation failures with release
accounting. See `tests/extended_regex_execution.rs` and the executable
`regex_contracts`/`regex_input` fixtures.
