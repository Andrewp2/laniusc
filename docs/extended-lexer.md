# Bounded UTF-8 lexing

`ext::lexer` compiles ordered token rules and scans borrowed UTF-8 input. It uses
the canonical [regular expression engine](extended-regex.md), with a new anchored
longest-prefix operation in its existing ordered Thompson/Pike search loop.
There is no second matcher or host regex implementation in production.

The current source prepares one fixed span-only regex workspace per nonempty
cursor. All six current lexer tests passed native x86_64 Linux execution,
including independent cursor ownership, unchanged matching/budget contracts,
and all 30 reached allocation-failure positions. Older per-probe allocation
receipts are retained separately below.

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
| `Lexer.scan(Text, ScanLimits)` | Validate input once, prepare a cursor-owned span workspace for nonempty input, and return a `Cursor` borrowing the programs/input. |
| `Cursor.borrow()`, `position()`, `usage()` | Borrow the cursor; inspect committed byte position and monotonically charged usage. |
| `Cursor.next()` | `Result<Option<Token>, Error>`; return one visible token, ordinary EOF, or a terminal error. |
| `Cursor.destroy()` | Release this cursor's workspace once and fuse it; borrowed programs/input remain alive. |
| `Lexer.destroy()` | Destroy each compiled regex and the outer rule allocation. Repeat destruction through the actual owner is harmless. |

`Token { rule: i32, id: i32, span: regex::Span, text: Text }` owns no allocation.
Its half-open byte offsets are relative to the selected input Text, including
when that Text starts inside a larger backing allocation. `text` selects the
same range. Every endpoint is a Unicode scalar boundary. Captures are not part
of a token.

Compilation owns the programs and class terms. Each nonempty cursor owns its
own mutable workspace; independent scans can be advanced in any order without
sharing scratch. The rule array and pattern backing may be released after
successful compilation. Keep the Lexer and input
backing alive and unchanged until the cursor is done. Keep input backing alive
while reading any returned token; tokens remain readable after the cursor and
Lexer are destroyed. Copying a Lexer aliases its single manual owner. A cursor
has one active owning handle; copies must not be advanced or destroyed
independently. Do not forge
or mutate internal fields, reuse a destroyed Lexer, or release inactive aliases.

## Anchored longest-prefix matching

The regex module exposes this reusable boundary:

| API | Contract |
| --- | --- |
| `regex::input(Text) -> Result<Input, regex::Error>` | Validate logical bounds and UTF-8 once; borrow the complete selected Text. |
| `Regex.longest_prefix_in(Input, start)` | Match exactly at `start`, returning the longest endpoint or None. Check the start range/scalar boundary without rescanning input. |
| `Regex.longest_prefix_from(Text, start)` | Validate raw Text, then perform the same anchored match. |
| `Regex.longest_prefix(Text)` | Convenience form starting at byte zero. |
| `regex::workspace(states, groups)` | Allocate fixed canonical VM scratch; the lexer requests the maximum actual rule state count and one group. |
| `Regex.longest_prefix_span_with(Input, start, &Workspace)` | Reuse that workspace and return only a copied group-zero `Span`; no Match allocation or capture transfer. |

The capture-returning prefix methods produce owned `Match` values that must be
destroyed once, like a `find` result. The span-only workspace method returns a
plain copied `Span` with no cleanup duty. `Input` owns no storage. Its backing must remain alive and
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
aborts selection even if an earlier rule already matched. Every probe uses the
same cursor-owned workspace and returns only a copied span. Losing, tied,
skipped and winning candidates create no `Match` owner.

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
back. Earlier returned tokens remain valid. None, error and destroy release the
workspace once and fuse the cursor; subsequent `next` calls return None with
unchanged usage and no further release.

## Cursor workspace ownership

After scan limits, logical bounds, input byte cap and UTF-8 validation succeed,
`Lexer.scan` eagerly allocates scratch for a nonempty input. Its state capacity
is the largest actual `Regex.state_count()` among the compiled rules, rather
than their aggregate state count or a configured upper bound. Group capacity
is one: the same VM still visits subgroup Save instructions but ignores their
register writes during span-only search. More capturing groups do not enlarge
lexer scratch or remove those visits from the work counter.

The workspace has fixed capacities with no reserve or growth operation.
Construction and requested-byte accounting belong to the canonical regex
module. A cursor retains it across rules, tokens and skips. Normal `next`
calls returning a token perform no allocation or deallocation. A terminal
None/error or explicit `destroy` releases scratch; tokens borrow only input
and remain readable while that input backing lives.

Separate `scan` calls own separate scratch, even when they borrow the same
Lexer. No mutable scratch lives in the compiled Lexer. Copying a cursor aliases
that cursor's one manual owner and does not create an independent scan.
Internally, a borrowed local workspace descriptor is stored back after each
probe so its list swaps, result metadata and work counter remain current.

Workspace construction failures occur in `scan`, before a rule attempt or
usage charge. OOM returns `AllocationFailed` after all partial workspace owners
are released; any other constructor error is retained as `Workspace(error)`.
The compiled Lexer and input are unchanged and can be scanned again. Every
valid nonempty input prepares scratch even if a zero step/call/work cap will
later stop its first attempt. Empty input stores no workspace, performs no
workspace allocation and finishes with zero usage.

Before each search the canonical workspace invalidates its old result and
resets active execution state, including failed/seen state and per-search work.
The current regex supplies its own work limit. A probe does not inherit a
previous rule's program, group count, result or remaining work. Capacity errors
are explicit failures; they do not allocate, grow scratch or become NoMatch.

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
`Options.max_work`. This includes searches returning None or the regex's own
WorkLimit. Cursor construction allocates before any such reservation.
A call/work cap can fail partway through a rule
list; no partial winner is committed. Reservations use subtraction checks,
so accepted counters cannot overflow their types.

Reserved work bounds the existing VM counter, which charges epsilon and
consuming state visits and tested class terms. It is not a measurement of
actual work or total CPU. Input validation occurs once. Scratch initialization,
capture copying, seen-array clearing, Unicode table operations and allocator
cost remain outside that VM counter. Per-rule pattern/state/capture caps and
the input/call caps bound their dimensions.

Probes reuse the fixed workspace prepared by `scan`; they create no capture
owner. The number of rule attempts for successful steps is `rules × steps`, plus any
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
| `AllocationFailed` | Outer compiled-rule storage or eager cursor workspace allocation failed. |
| `Pattern(rule, regex_error)` | Rule compile or pattern validation failed. |
| `Input(regex_error)` | Input bounds/UTF-8 validation failed. |
| `Workspace(regex_error)` | A cursor workspace constructor returned an error other than OOM. |
| `Search(rule, position, regex_error)` | An attempted span search failed, including per-search WorkLimit or an explicit workspace capacity error. |
| `NoMatch(position)` | No rule matches this non-EOF position. |
| `EmptyMatch(rule, position)` | The maximal winning span is empty. |
| `StepLimit(position)`, `TokenLimit(position)` | The next step/token cannot commit. |
| `SearchCallLimit(rule, position)`, `SearchWorkLimit(rule, position)` | The next rule attempt cannot reserve its allowance. |

Rule indices and input positions are zero based. Nested regex error offsets
retain the regex module's pattern/input-relative meaning.

## Current workspace executable acceptance

All six current tests passed GPU compilation followed by native x86_64 Linux
execution in two separate serialized invocations:

| Current scope | Tests | Elapsed | Receipt under `target/stdlib-work/` |
| --- | ---: | ---: | --- |
| Independent cursor owners, build/input admission, longest-prefix and lexer contracts | 3 | 12.79s | `lexer-workspace-owners-contracts-admission-first.log` |
| Every reached allocation failure, explicit edge tables, independent full-context model | 3 | 11.88s | `lexer-workspace-model-tables-oom-first.log` |

Accepted source SHA256 values are
`9eddce441eaed36cb38dc9eebbc6f332a4c1df173107b484c1ede1282508c8ab`
for the lexer and
`4520d1fc663432af975dd774d07da0f3b747f2164c2465b8e62ff4b6b08e1659`
for the canonical regex module. The independent read-only ownership review at
that lexer freeze found no blocker.

The owner fixture interleaves two separately constructed cursors over different
inputs. It checks distinct live scratch mappings, matching and usage through
skips, group-bearing rules with group-zero-only scratch, held Token text after
workspace reuse/retirement, explicit destruction, EOF, NoMatch and a partial
rule-list call-limit failure. Empty input and invalid input perform no scratch
allocation. Exact verified full-width source-allocation sites and requested
lengths are checked at process-held ACK checkpoints before exit.

All `next` phases make zero source allocations. Normal token-returning phases
also make zero frees. EOF/error/destroy release only the appropriate cursor's
workspace; fused calls and repeated destruction perform no further source
operation. The final checkpoint requires every program/workspace mapping to
have been explicitly released before process exit, rather than crediting OS
teardown.

The allocation campaign passed **30** reached ENOMEM positions, classified as
**[1, 1, 10, 9, 9]**: input backing, pattern backing, compiled rules, first cursor
workspace construction, and a second cursor construction. Constructor failures
return typed `AllocationFailed` from `scan`; healthy recovery scans verify that
the original programs and input remain intact. The nine scratch allocations
are made once per nonempty cursor, and are not repeated by later rule probes.
These are one-fault-per-reached-baseline-position cases, not simultaneous faults.

The current semantic gates retain **63** explicit assertion/capture/admission/
error-order cases and **576** independent full-context cases: 288 anchored-prefix
and 288 lexer scans across native strided, Vec and raw packed input. The
canonical workspace module's separate 839-model-case, nine-constructor-OOM and
owner-contract receipts belong to the [regex guide](extended-regex.md); they
are not added to these lexer counts.

All five `lex_scan` application gates also pass, including its 4,096-token
resource observation. Those separate whole-program receipts and exact cost
scope belong to the [application guide](extended-lex-scan.md). No other
target's runtime behavior is established.

## Historical executable acceptance

The earlier implementation's **five driver groups** passed actual GPU
compilation and native x86_64 Linux execution through these separate receipts.
Times below describe each historical complete invocation, including the fixture
failures noted below. Their 120 OOM positions are not the current workspace
campaign's 30 positions.

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
