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
let regex = ext::regex::compile(pattern,ext::regex::options()).unwrap();
let checked = ext::regex::input(input).unwrap();
let scratch = ext::regex::workspace(regex.state_count(),1).unwrap();
let found = regex.find_span_with(checked,0,scratch.borrow()).unwrap();
// A Some(Span) is a copied pair of byte offsets, with no cleanup duty.
scratch.destroy();
regex.destroy();
```

`pattern` and `input` are `core::text::Text`. Compilation copies its program
and class terms, so pattern backing may be released after compilation. `Input`
borrows validated immutable text. Keep that backing alive and unchanged for
every search or cursor; do not forge its fields. Raw-Text convenience APIs
validate logical bounds and UTF-8 before searching. The reusable Input APIs
check each start range and scalar boundary without rescanning the full input.

Every `Regex`, `Workspace`, `Search`, `Matches` and returned `Match` has one
manual owner. Copying these records aliases their allocations; copies cannot
fork cleanup authority or cursor positions. Destroy the active owner explicitly.
Repeat destruction through that same owner is harmless. Internal fields are
public because the language lacks opaque fields; they are not a stable storage
format and must not be forged or mutated.

### Compiled programs and fixed workspaces

| API | Contract |
| --- | --- |
| `compile(Text, Options) -> Result<Regex, Error>` | Compile an independent owned program. |
| `Regex.borrow() -> &Regex` | Borrow the compiled owner for helper calls. |
| `Regex.group_count() -> i32` | Number of captures, including group 0. |
| `Regex.state_count() -> i32` | Number of compiled NFA instructions. |
| `Regex.search_work_limit() -> i32` | Configured per-search `Options.max_work`, for aggregate-budget adapters. |
| `input(Text) -> Result<Input, Error>` | Validate one borrowed input for repeated searches. |
| `workspace(states, groups) -> Result<Workspace, Error>` | Allocate fixed capacity; states is 1..65536, groups is 1..129 including group 0. |
| `Workspace.borrow() -> &Workspace` | Borrow the sole scratch owner for one search at a time. |
| `Workspace.state_capacity()`, `group_capacity()` | Inspect fixed logical capacity. |
| `Workspace.owned_bytes() -> u64` | Requested bytes held by its nine Vec allocations. |
| `Workspace.group_count() -> i32` | Published group count after a successful match; zero after absence, error, or destruction. |
| `Workspace.span(group) -> Option<Span>` | Copy a published capture span; None for an unmatched or invalid group, or an invalidated result. |
| `Workspace.work_used() -> i32` | Existing VM ticks from the last attempted search. |
| `Workspace.destroy()` | Release all scratch allocations and invalidate results/capacities. |

A workspace retains no program or input borrow between calls. Reuse it across
programs and inputs within its selected capacities. Capacity never grows or
shrinks during search. There is no hidden allocation in a reusable search.
To run a larger program, construct a larger workspace explicitly.

| Reusable Regex method | Contract |
| --- | --- |
| `find_with(Input, start, &Workspace) -> Result<bool, Error>` | Leftmost-first search at or after start; publish all captures on true. |
| `longest_prefix_with(Input, start, &Workspace) -> Result<bool, Error>` | Anchored longest whole match; publish all captures on true. |
| `find_span_with(Input, start, &Workspace) -> Result<Option<Span>, Error>` | Leftmost-first search retaining only group 0. |
| `longest_prefix_span_with(Input, start, &Workspace) -> Result<Option<Span>, Error>` | Anchored longest whole span retaining only group 0. |

Every attempted call invalidates the preceding capture result and resets
`work_used()` to zero before checking start/capacity. Start errors return
Bounds; an insufficient state capacity, full-capture group capacity, or destroyed
workspace returns WorkspaceTooSmall. Span methods require one group regardless
of the program's subgroup count. Errors and absence publish no partial result.
Capacity remains reusable after Bounds, WorkspaceTooSmall or WorkLimit.

A successful full-capture result publishes the regex's complete group count.
Span mode publishes one group. Read workspace captures before the next attempted
search or destruction. Returned `Span` values are independent copied offsets;
they remain usable after the workspace, regex and input are released. Reading
bytes selected by those offsets still requires the original input backing.
Destruction preserves the last measured `work_used()`; a later direct search
attempt resets it even when rejected. Capacity and owned bytes become zero.

### Canonical search cursors and owned capture convenience

| API | Contract |
| --- | --- |
| `Regex.capture_iter(Input) -> Result<Search, Error>` | Create a cursor owning full-capture scratch and borrowing the program/input. |
| `Regex.span_iter(Input) -> Result<Search, Error>` | Create the same cursor with two-slot, group-0 scratch. |
| `Search.borrow() -> &Search` | Borrow the active cursor owner. |
| `Search.next() -> Result<Option<Span>, Error>` | Advance using canonical scalar progress; publish captures and return a copied whole span. |
| `Search.span(group)`, `group_count()`, `work_used()` | Inspect the current capture publication and last VM counter. |
| `Search.destroy()` | Free cursor scratch, invalidate captures, and fuse iteration. |
| `Regex.find(Text)`, `find_from(Text, start)` | Return `Result<Option<Match>, Error>` with independent owned captures. |
| `Regex.longest_prefix(Text)`, `longest_prefix_from(Text, start)` | Return an independent Match at the exact boundary and longest endpoint. |
| `Regex.longest_prefix_in(Input, start)` | Same owned-capture probe using validated input. |
| `Regex.is_match(Text) -> Result<bool, Error>` | Search with temporary group-0 scratch. |
| `Regex.find_iter(Text) -> Result<Matches, Error>` | Validate input and wrap a canonical capture Search. |
| `Matches.next() -> Result<Option<Match>, Error>` | Copy each successful publication into independent owned capture storage. |
| `Match.group_count()`, `span(group)` | Inspect independent captures, including group 0. |
| `Regex.destroy()`, `Match.destroy()`, `Matches.destroy()` | Release each owned allocation; destroying Matches also fuses its Search. |

`Search` allocates its nine scratch owners at construction and performs no
allocation in `next()`. `Matches` retains that same scratch and allocates one
independent capture Vec for each Some. A returned Match retains no input or
compiled storage and remains valid after cursor/program destruction. The
one-shot owned methods use a temporary workspace and transfer its candidate
allocation just before destroying the remaining scratch; public reusable
methods always retain their allocations.

The canonical Search searches from the preceding match end. After an empty
match it advances by one Unicode scalar, or marks completion after the final
empty match at EOF. Consequently `|a` on `a` yields `[0,0]` and `[1,1]`.
After a nonempty match, an empty match at its end is permitted. These rules are
shared by Search, Matches and the [text operations](extended-regex-text.md).

Each Search publication lasts until its next attempt or destruction. A final
successful empty EOF match retains its captures for the caller to inspect.
The following `next()` invalidates it, frees scratch, and returns None without
another VM search. Ordinary absence, error and explicit destruction free scratch
and fuse the cursor immediately. Fused calls return None without VM work and
preserve the last measured work counter. A failed Matches capture-copy allocation
also fuses/releases its Search; earlier independent Match values remain
valid. Both cursor types borrow the Regex and input until finished; both have
one active manual owner.

[Token lexing](extended-lexer.md) uses a per-cursor span workspace shared across
its rule probes. [Splitting and replacement](extended-regex-text.md) use canonical
Search progress; template expansion requires full captures, while splitting and
literal replacement need only group 0. Their guides define their own aggregate
budgets and borrowed/owned output lifetimes.

### Span and matching semantics

Spans are half-open byte offsets relative to the supplied input Text, including
subviews. Every endpoint is a Unicode scalar boundary. Group 0 is the whole
match; subgroups are numbered by opening parenthesis. An unmatched optional
group is None, distinguishable from a matched empty group. A repeated capture
records the last participating traversal retained by Pike priority; groups
skipped in a later traversal retain their earlier values.

Longest-prefix mode starts exactly at the supplied boundary and retains the
furthest endpoint. Equal endpoints retain ordered Pike capture priority. Lazy
quantifiers still participate in longest whole-span selection. Assertions
inspect the complete selected Text, including context before a nonzero start.

Span mode executes the same program and matching loop with two active capture
slots. Subgroup Save instructions still consume the same state visits, ticks
and priority decisions; only their writes are skipped. This follows the supported
dialect's absence of capture-dependent control flow: captures record earlier
execution in [Cox's Pike VM](https://swtch.com/~rsc/regexp/regexp2.html), and the
[Go executor](https://go.dev/src/regexp/exec.go) likewise guards capture writes by
the selected capture-slice length. This establishes the design argument; the
new implementation's executable acceptance is listed separately below.

Text metadata must physically back its claimed range, as in `core::text`.
Logical bounds and UTF-8 are checked, including forged logical Text records.
Native strided slices and packed storage work. A physically overstated slice
can trap because the language cannot establish its real allocation length.
Do not use a destroyed Regex or Match, or mutate borrowed input/program storage.

## Dialect

Ordinary `find`, `find_from` and `Matches` matching is leftmost-first: prefer the earliest start, then the left branch of
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

`max_work` applies separately to each actual search, including each searching
cursor next. It charges each newly visited epsilon/consuming state and each
tested class term. UTF-8 validation, workspace construction, per-search reset,
per-boundary seen-array clearing and capture copying are outside that counter;
their dimensions are bounded separately. `work_used()` reports these existing
VM ticks. Reusing a workspace with another Regex uses that Regex's per-search
cap and resets the counter. A limit error publishes no partial match. Earlier
independent Match values remain valid after a later cursor failure.

For state capacity S and group capacity G, let C = 2*G. The nine exact Vec
capacities hold `4*S + 3*S*C + 2*C` i32 elements. Requested bytes multiply that
count by `core::mem::size_of<i32>()`; the physical element width is not assumed.
Dimensions, matrix products, Vec byte limits and the total byte multiplication
are checked before allocation. Every partial allocation is released on failure.
For span storage G=1, the count is `10*S + 4` elements. Active capture matrices
use the current search's slot stride, and seen clearing visits the current
program's states rather than a larger reserved capacity.

| Error | Meaning |
| --- | --- |
| `Syntax(byte_offset)` | Invalid grammar, offset relative to the pattern. |
| `Unsupported(byte_offset)` | Recognized unsupported syntax or unknown property/escape. |
| `Limit(byte_offset)` | Invalid options/workspace dimensions or compile resource bound; offset is 0 when no single source location identifies expansion failure. |
| `AllocationFailed` | Program/workspace/cursor/owned-capture allocation failed; partial owners have been released. |
| `Bounds` | Invalid Text integer metadata or non-boundary/out-of-range search start. |
| `InvalidUtf8(byte_offset)` | Malformed selected Text range; offset relative to pattern or search input for the failing operation. |
| `WorkLimit` | Search exhausted its VM work budget; no capture result is published. |
| `WorkspaceTooSmall` | Reusable search exceeds the supplied state/group capacity, or the workspace was destroyed. |

For fixed compiled pattern, each search scales linearly with input length.
Unanchored search adds a lower priority start at each scalar boundary in the
same pass; it does not restart a whole-input scan at each position. Each PC is
visited once per boundary. With S instructions, C capture slots, P stored
class terms and T the sum of class-term counts over compiled instructions,
search is O(N * (S*C + T)); span calls use C=2. Program storage is O(S+P),
and fixed workspace storage follows the capacity formula above, which can exceed
the active program dimensions. Counted repetitions can share stored terms, so T
can be larger than P.
Scalar validation is O(N). Each next performs a new bounded search;
a whole iteration can rescan suffixes while resolving greedy alternatives,
so no linear bound is claimed for the sum of all next calls. Matching uses
an explicit bounded stack, never native recursion.

## Executable acceptance

The fixed Workspace, four reusable search methods and canonical Search cursor
passed all three focused driver groups on source SHA256
`4520d1fc663432af975dd774d07da0f3b747f2164c2465b8e62ff4b6b08e1659`.
These are actual GPU-compiler builds followed by native Linux x86_64 execution.
No other user-program target or general throughput claim is established.

| Accepted scope | Invocation time | Receipt under `target/stdlib-work/` |
| --- | ---: | --- |
| Workspace/Search contract fixture: 1 native process | 6.12 s | `regex-workspace-contracts-first.log` |
| Constructor baseline plus all 9 reached allocation failures: 10 native processes | 9.19 s, within a mixed invocation | `regex-workspace-model-and-oom-first.log` |
| Independent full-capture/span model: 839 cases | 6.99 s | `regex-workspace-model-exhaustive-offset-retry.log` |

The constructor group passed inside a command whose model group failed before
native execution. The 9.19-second receipt accepts only the constructor group;
it is not an all-pass command. Two model attempts stopped before native
execution at fixture match-binding errors. The corrected protocol then passed
all 839 cases; production matching and the oracle cases were unchanged.

The contract fixture checks exact, insufficient and maximum state/group
capacities; smaller-program reuse after rejection; full/span/full transitions;
unmatched capture reset; repeated work counters; equal full/span tick and
WorkLimit boundaries; recovery after miss, WorkLimit and invalid starts;
nonzero native strided UTF-8; independent Match lifetime; interleaved cursor
owners; final empty EOF capture lifetime; and terminal cleanup/work retention.
Its first two stdout/ACK checkpoints bracket explicit workspace probes with
zero source allocation or release. All source owners are released before the
final pre-exit checkpoint.

The constructor gate rejects invalid dimensions before allocation, verifies
live requested bytes against `owned_bytes()`, and separately denies each of
the nine actually reached allocation sites. Every partial owner is released
before the host ACK permits exit. Runtime instruction sites, syscall arguments,
requested source mappings and `/proc` observations bind the resource oracle.
The independent semantic model reuses one Workspace across all 839 cases,
checking ordinary and longest-prefix modes, captures and spans, packed and
native strided inputs, nonzero backing offsets, scalar starts, flags,
nullable-priority tables and reuse after failure. See the
[fixture guide](../tests/fixtures/extended/regex_workspace/README.md) and
`tests/extended_regex_workspace_execution.rs` for exact scope.

Both existing base-regex driver tests also pass on the current source in
10.50 seconds: `target/stdlib-work/regex-workspace-existing-regressions-first.log`.
Their scope includes the independent Python reference, Unicode and limits;
native views, borrowed owners, independent capture lifetimes, bounds and fused
iteration. The model test retains its original allocation-failure probe. That
is legacy-gate evidence, separate from the new strict nine-site workspace
ledger above. The `regex_contracts` fixture additionally compiled and exited
zero through the CLI:
`target/stdlib-work/regex-workspace-contracts-explicit-guards.log`.

The six lexer groups and seven regex-text groups also pass; their scopes and
receipts are recorded in the [lexer guide](extended-lexer.md) and
[regex-text guide](extended-regex-text.md). All five lex-scan application gates
also pass; the [application guide](extended-lex-scan.md) records its exact
output, failure cleanup and resource observation. The selected
[workspace/consumer increment](library-regex-workspace-plan.md) is accepted on
native Linux x86_64; the broader library goal remains open.

### Compiler propagation dependency

The initial new module used question-mark propagation at its wrapper boundaries.
GPU lowering failed with SSA dominance reason 17, including when the module was
only imported by an otherwise empty main. An equivalent full-module control
using explicit result/error branches compiles:
`target/stdlib-work/regex-workspace-all-explicit-control.log`. This revision
uses those explicit branches with identical APIs, matching, error order and
manual cleanup. All six smaller constructor/arithmetic/propagation controls
compile and exit zero; no single failing expression has been established.
`tests/fixtures/stdlib_compiler_state/regex_workspace_admission/` preserves a
five-line unused-import entry and compact patch restoring the exact original
module in a temporary source root, with verified original/control hashes.
This dependency is scoped to the new module shape; earlier module migrations
and their question-mark execution receipts remain separate evidence. No compiler
change or reduced regex capability is part of this adaptation.

### Historical engine coverage

Before workspace reuse, the focused native tests compared over a thousand
grammar-generated/shared cases with Python `re`, with byte-span conversion and
the same scalar progress policy. Additional cases covered Unicode properties,
nullable priority/captures, native strides, malformed UTF-8, subviews,
ownership, resource bounds, long nested repetitions and injected allocation
failures. Those prior receipts describe earlier source revisions.

After sharing the engine with anchored longest-prefix search, both existing
regex groups passed in 9.70 seconds:
`target/stdlib-work/regex-longest-mode-regression.log`. The earlier
[lexer guide](extended-lexer.md) also records 576 endpoint/tokenization model
cases, 63 edge tables and allocation-failure gates for that revision. Historical
receipts are not additional current-revision acceptance.
