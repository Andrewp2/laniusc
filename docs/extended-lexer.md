# Bounded UTF-8 lexing

`ext::lexer` compiles ordered token rules and scans borrowed UTF-8 input. It uses
the canonical [regular expression engine](extended-regex.md), with a new anchored
longest-prefix operation in its existing ordered Thompson/Pike search loop.
There is no second matcher or host regex implementation in production.

The selection rule follows the [Flex matching specification](https://westes.github.io/flex/manual/Matching.html):
choose the rule consuming the most input, then the earliest declared rule on a
tie. This module returns an error for unmatched input. Skip rules consume their
match and continue without returning a token. Rule ids are arbitrary `i32`
values; duplicate ids are permitted, and every token also carries its declaration
index.

## API

```lani
let rule = ext::lexer::Rule { id: 1, pattern: pattern, skip: false };
let rules: [ext::lexer::Rule;1] = [rule];
let lexer = ext::lexer::compile(
    core::slice::view<ext::lexer::Rule>(rules,1).unwrap(),
    ext::regex::options(),ext::lexer::default_build_limits()).unwrap();
let cursor = lexer.scan(input,ext::lexer::default_scan_limits()).unwrap();
// Repeated next() transfers borrowed tokens; handle Err before unwrapping.
let first = cursor.next();
cursor.destroy();
lexer.destroy();
```

`pattern` and `input` above are `core::text::Text`. Applications should handle
construction, scan and `next` failures explicitly.

| API | Contract |
| --- | --- |
| `Rule { id, pattern, skip }` | Borrowed rule specification; declaration order resolves equal-length matches. |
| `compile(View<Rule>, regex::Options, BuildLimits)` | Return an owned `Lexer`, or release every partially compiled owner. One regex configuration applies to all rules. |
| `Lexer.borrow()` | Borrow the compiled owner for helpers. |
| `Lexer.rule_count()`, `state_count()` | Rule count and total compiled instructions. |
| `Lexer.scan(Text, ScanLimits)` | Validate input once and return a borrowed `Cursor`. |
| `Cursor.borrow()`, `position()`, `usage()` | Borrow the cursor; inspect committed byte position and monotonically charged usage. |
| `Cursor.next()` | `Result<Option<Token>, Error>`; return one visible token, ordinary EOF, or a terminal error. |
| `Cursor.destroy()` | Fuse the cursor. No borrowed owner is released. |
| `Lexer.destroy()` | Destroy each compiled regex and the outer rule allocation. Repeat destruction through the actual owner is harmless. |

`Token { rule: i32, id: i32, span: regex::Span, text: Text }` owns no allocation.
Its half-open byte offsets are relative to the selected input Text, including
when that Text starts inside a larger backing allocation. `text` selects the
same range. Every endpoint is a Unicode scalar boundary. Captures are not part
of a token.

Compilation owns the programs and class terms. The rule array and pattern
backing may be released after successful compilation. Keep the Lexer and input
backing alive and unchanged until the cursor is done. Keep input backing alive
while reading any returned token; tokens remain readable after the cursor and
Lexer are destroyed. Copying a Lexer aliases its single manual owner. A cursor
has one active handle; copies must not be advanced independently. Do not forge
or mutate internal fields, reuse a destroyed Lexer, or release inactive aliases.

## Anchored longest-prefix matching

The regex module exposes this reusable boundary:

| API | Contract |
| --- | --- |
| `regex::input(Text) -> Result<Input, regex::Error>` | Validate logical bounds and UTF-8 once; borrow the complete selected Text. |
| `Regex.longest_prefix_in(Input, start)` | Match exactly at `start`, returning the longest endpoint or None. Check the start range/scalar boundary without rescanning input. |
| `Regex.longest_prefix_from(Text, start)` | Validate raw Text, then perform the same anchored match. |
| `Regex.longest_prefix(Text)` | Convenience form starting at byte zero. |

Each successful match owns its capture array and must be destroyed once, just
like a `find` result. `Input` owns no storage. Its backing must remain alive and
immutable, and its fields must not be forged. The lexer stores this validated
descriptor and reuses it for all rule probes.

The existing `find`, `find_from` and `Matches` APIs retain leftmost-first
behavior. Longest-prefix mode starts its Pike threads only at the supplied
boundary, keeps all viable consuming threads after an accept, and replaces a
candidate only at a later endpoint. On equal endpoints it retains the existing
Pike branch/capture priority. Thus `a|ab` and lazy `a+?` can consume more text
than their ordinary `find` results. `(a|aa)(a?)` on `aa` returns the whole `aa`,
with captures `a` and `a`. This is longest whole matching with priority ties;
it does not maximize POSIX subcaptures.

This shares [Cox's ordered Pike machinery](https://swtch.com/~rsc/regexp/regexp2.html).
The distinction between first-match cutoff and longest endpoint retention also
appears in the [Go regex execution loop](https://go.dev/src/regexp/exec.go).
The regex dialect and nullable-cycle capture convention remain those of the
canonical engine.

Assertions always see the entire selected input, including text before and
after `start`. A nonzero start does not turn `\A` into a suffix anchor; `\b`
sees the preceding scalar, and `$` sees the real remaining suffix. The lexer
does not slice suffixes before matching. Scalar-boundary checks are constant
time on validated input.

## Progress and terminal states

At each non-EOF position, the cursor probes **all rules**. A later rule error
aborts selection even if an earlier rule already matched. Each owned `Match`
is destroyed immediately after extracting its span, including losing, tied,
skipped and winning matches. No capture owner survives between `next` calls.

A positive-length match wins over an empty one. If the selected winner is
empty, `EmptyMatch(rule, position)` terminates the cursor without advancing.
Nullable rules are therefore allowed at construction; context-dependent empty
matches such as word boundaries are handled where they occur. There is no
synthetic scalar advance or implicit unknown-character token.

EOF returns None before any rule call or budget charge, even for empty input
and nullable rules. No EOF token is generated. An unmatched non-EOF position
returns `NoMatch(position)`.

Selection and limit checks complete before the current token step commits.
Successful skipped steps commit immediately and continue inside the same
`next`. If that call later fails, its position retains those completed skips.
Calls and reserved work already charged during a failed selection never roll
back. Earlier returned tokens remain valid. None, error and destroy fuse the
cursor; subsequent `next` calls return None with unchanged usage.

## Limits and accounting

`default_build_limits()` returns:

| Field | Default | Accepted range |
| --- | ---: | --- |
| `max_rules` | 128 | 0..1024 |
| `max_pattern_bytes` | 1048576 | 0..16777216 |
| `max_states` | 65536 | 0..1048576 |

At least one rule is required. Rule view bounds and aggregate pattern bytes
are checked before owned allocation or pattern UTF-8 validation. The outer
rule storage is reserved before compiling leaves. Each pattern also obeys
the supplied regex Options, including its per-pattern limits and compile
frame bound. The total state cap is checked after each bounded rule compile;
temporary construction can include that one rule's parser/program storage
in addition to the accepted prefix. Rejection destroys both the new program
and the compiled prefix.

`default_scan_limits()` returns:

| Field | Default | Meaning |
| --- | ---: | --- |
| `max_input_bytes` | 16777216 | Reject longer input before UTF-8 validation. |
| `max_steps` | 1000000 | Committed rule matches, including skips. |
| `max_tokens` | 1000000 | Committed visible tokens. |
| `max_calls` | 4000000 | Attempted rule searches. |
| `max_work` | 1000000000000 | Sum of reserved per-search VM allowances. |

All scan fields must be nonnegative. The first four are `i32`; `max_work` is
`i64`. Zero caps are valid. Empty input finishes with zero usage. A zero token
cap still permits skipped input to reach EOF; a visible winner instead fails
without consuming that token. A step cap is checked before evaluating the
next position. No limit is represented as clean EOF with unconsumed input.

`Usage { steps, tokens, calls, reserved_work }` records those counters.
Before **every** attempted rule search, the cursor reserves that regex's full
`Options.max_work`. This includes searches returning None, allocation failure,
or the regex's own WorkLimit. A call/work cap can fail partway through a rule
list; no partial winner is committed. Reservations use subtraction checks,
so accepted counters cannot overflow their types.

Reserved work bounds the existing VM counter, which charges epsilon and
consuming state visits and tested class terms. It is not a measurement of
actual work or total CPU. Input validation occurs once. Scratch initialization,
capture copying, seen-array clearing, Unicode table operations and allocator
cost remain outside that VM counter. Per-rule pattern/state/capture caps and
the input/call caps bound their dimensions.

Each probe currently allocates the canonical scratch vectors and releases
them before the next probe. No reusable scratch workspace is retained. The
number of rule attempts for successful steps is `rules × steps`, plus any
partial failing selection. Longest-prefix resolution can scan beyond the
eventual winning token: a short rule competing with a long failing alternative
can rescan suffixes. There is no linear whole-tokenization claim. Use explicit
input, call and work budgets for untrusted workloads.

Text and rule metadata must physically back their claimed ranges, as in
`core::text` and `core::slice`. Logical bounds and UTF-8 are checked; this
language cannot establish a forged slice's true allocation length.

## Errors

| Error | Meaning |
| --- | --- |
| `Bounds` | Invalid rule-view integer metadata. |
| `InvalidLimits` | Invalid build/scan limits. |
| `RuleLimit` | No rules, or too many rules. |
| `PatternLimit(rule)`, `StateLimit(rule)` | Aggregate construction cap exceeded at that declaration index. |
| `InputLimit` | Input byte cap exceeded before validation. |
| `AllocationFailed` | Outer compiled-rule storage allocation failed. |
| `Pattern(rule, regex_error)` | Rule compile or pattern validation failed. |
| `Input(regex_error)` | Input bounds/UTF-8 validation failed. |
| `Search(rule, position, regex_error)` | An attempted rule search failed, including OOM or per-search WorkLimit. |
| `NoMatch(position)` | No rule matches this non-EOF position. |
| `EmptyMatch(rule, position)` | The maximal winning span is empty. |
| `StepLimit(position)`, `TokenLimit(position)` | The next step/token cannot commit. |
| `SearchCallLimit(rule, position)`, `SearchWorkLimit(rule, position)` | The next rule attempt cannot reserve its allowance. |

Rule indices and input positions are zero based. Nested regex error offsets
retain the regex module's pattern/input-relative meaning.

## Executable acceptance

All **five driver groups** passed actual GPU compilation and native x86_64
Linux execution through these separate receipts. Times describe each complete
invocation, including the fixture failures noted below.

| Accepted scope | Invocation time | Receipt under `target/stdlib-work/` |
| --- | ---: | --- |
| Contract group | 7.43 s | `lexer-contract-first.log` |
| Admission and all 120 reached allocation failures | 13.21 s | `lexer-expanded-first.log` |
| Independent model: 576 cases | 7.06 s | `lexer-model-tables-expression-arms.log` |
| Explicit tables: 63 cases | 7.16 s | `lexer-explicit-tables-syntax-offset.log` |

The contract group exercises maximal endpoints versus ordinary find/Matches,
lazy and nullable patterns, capture ties, full-input assertions, reusable Input
and UTF-8 start checks, declaration ties and duplicate ids, skipped input,
borrowed token lifetime, independent pattern ownership, EOF, call/work/step/token
boundaries, and failure of a later rule after an earlier candidate. Admission
checks exact and exceeded aggregate caps, valid maximum settings, invalid limits,
logical range overflow and validation order. Both groups check exact mapping
cleanup under `strace`.

The five allocation-failure stages were input backing, pattern backing,
compiled rules, first scan and recovery/probe scan, with counts **[1, 1, 10,
54, 54]**. Each run injects one reached `mmap` failure and balances every live
address and requested mapping length. Search failures also rescan intact source
owners after the failure. Both scan stages exercise a later rule failing after
an earlier winning candidate.

The model compares 288 anchored-prefix cases and 288 lexer scans against
independent Python matching, across native strided, packed Vec and raw packed
storage. Its zero-width endpoint constraint preserves full input context; it
does not slice input or supply production matching. Explicit tables cover
Pike nullable captures, strict EOF assertions, Unicode boundaries, byte offsets,
invalid UTF-8, construction errors and scan limits separately.

The expanded invocation initially stopped two protocol groups at unsupported
fixture block match arms. Replacing those with scalar expressions preserved the
encoded fields. The model then passed while one explicit table expected the
wrong unclosed-group offset: the canonical parser reports the opening `(` byte
(zero), rather than EOF (one). Correcting that expectation produced the final
63-case pass. These were harness corrections; production matching was unchanged.

Production source uses portable Lanius text, Unicode and allocation modules.
Executable acceptance currently covers x86_64 Linux only; no other target or
unbounded throughput claim follows from these finite tests.
