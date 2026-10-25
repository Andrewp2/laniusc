# Bounded regex splitting and replacement

`ext::regex_text` provides borrowed splitting and owned literal or numeric
capture replacement. It consumes the existing [`ext::regex`](extended-regex.md)
`Matches` cursor. It adds no matcher, capture algorithm or host regex call.
The source preserves the Regex and input on success and recoverable failure.

All six focused groups passed on Linux x86-64 through the GPU compiler on
2026-10-25, in separate contract, reference, allocation and sample program
gates. The algorithms use existing Lanius text, regex and owned-storage APIs;
execution on other targets has not been established.

## API and limits

```lanius
pub struct SearchLimits {
    max_matches: i32,
    max_calls: i32,
    max_work: i64
}
pub struct ReplaceLimits {
    search: SearchLimits,
    max_output_bytes: i32,
    max_replacement_bytes: i32
}
pub struct Usage { matches: i32, calls: i32, reserved_work: i64 }

split(&ext::regex::Regex, core::text::Text, SearchLimits)
    -> Result<Split,Error>
replace_literal(&ext::regex::Regex, core::text::Text, core::text::Text, ReplaceLimits)
    -> Result<Replacement,Error>
replace_template(&ext::regex::Regex, core::text::Text, core::text::Text, ReplaceLimits)
    -> Result<Replacement,Error>
```

`default_search_limits()` permits 1,024 matches and 1,025 search calls with
10,250,000,000 reserved VM work units. `default_replace_limits()` adds a
16 MiB output cap and a 1 MiB replacement-input cap. All byte sizes count UTF-8
bytes, including NUL. Accepted search limits are `max_matches` from zero
through 1,000,000, `max_calls` from zero through 1,000,001, and nonnegative
`max_work`. Output bytes must be nonnegative; replacement bytes must be from
zero through 1 MiB.

`max_matches` is a normal truncation count. After that many delimiters or
replacements, the remaining input is kept unchanged without another search.
Zero performs no search: split yields the whole input once, and replacement
returns an independent unchanged copy. Limits and input UTF-8 still undergo
validation. Replacement metadata, size and UTF-8 also undergo validation, and
template syntax and capture references are checked even with zero matches.

### Conservative search accounting

`Regex.search_work_limit()` returns the existing configured `Options.max_work`
per-search VM cap. Before each attempted matcher search, this module reserves
that entire allowance from `SearchLimits.max_work` and charges one call. A
no-match result, allocation error or matcher WorkLimit still consumes the
reservation. The next search is rejected before invocation if either budget
would be exceeded. Equality with either cap is allowed. Call exhaustion is
checked before work exhaustion when both apply.

`Usage.reserved_work` reports reserved allowances rather than measured VM
transitions. For example, a regex configured for 100 work units and an
aggregate cap of 200 can attempt two searches even if the first used only five
units; it cannot admit a third. A fused EOF or match-count truncation performs
no search and consumes no allowance. Each operation has its own limits and
usage; limits passed to separate operations do not form a shared mutable pool.

The underlying VM counter excludes UTF-8 validation, scratch initialization,
seen-array clearing and capture copying. This module also performs template
preflight, token replay and String copies outside that counter. Search count,
match count, replacement-input size and output size bound those additional
sizes and repetitions. These limits are not a count of all CPU instructions
or a clock deadline, and iteration can rescan suffixes. No linear bound is
claimed for the sum of all searches.

## Borrowed split cursor

`Split` exposes `borrow()`, `next() -> Result<Option<Text>,Error>`, `usage()`
and `destroy()`. Each returned Text borrows the original selected input range;
it owns no allocation. Capture groups in delimiters are excluded from fields.
Leading, adjacent and trailing empty fields are retained. Empty input always
has a final field, including when there is no delimiter search.

The Regex and input backing must stay alive and immutable until the cursor is
finished or destroyed. Returned fields remain valid after cursor destruction
while the original input remains valid. Cursor copies must not be advanced
independently. The cursor retains no Match or allocation between calls. It
destroys every acquired capture owner before returning a field. Error, explicit
destruction and exhaustion fuse it; later `next()` calls return None without
another search. At match-count truncation or ordinary absence, the final tail
is emitted exactly once.

### Empty matches use the existing cursor policy

After an empty match, `Matches` advances one Unicode scalar rather than one
byte. It suppresses a nonempty alternative beginning at that same position.
An empty match immediately following a nonempty match's end is allowed, and a
final empty match at EOF is returned once. This module preserves that sequence
for both split and replacement. It does not adopt Python's default empty-match
split/substitution rules.

| Pattern | Input | Split fields | Literal replacement `X` |
| --- | --- | --- | --- |
| empty | `é🙂` | `"", "é", "🙂", ""` | `XéX🙂X` |
| empty | empty | `"", ""` | `X` |
| `\|a` | `a` | `"", "a", ""` | `XaX` |
| `a*` | `a` | `"", "", ""` | `XX` |
| `a*` | `ba` | `"", "b", "", ""` | `XbXX` |

The table's `\|a` denotes the pattern `|a`, an empty alternative followed by
`a`; the backslash only escapes Markdown's table separator.

## Owned replacement and template grammar

`Replacement` contains `output: alloc::string::String` and `usage: Usage`.
Success transfers one independent owner to the caller, including when no
matches were replaced. The input, replacement Text and Regex may then be
released. `Replacement.destroy()` releases and resets its actual output owner
and zeroes its usage; repeated calls on that reset owner are harmless. Copied
descriptors remain inactive aliases, following the existing
[manual ownership conventions](library-api-conventions.md).

Literal replacement interprets every replacement byte literally. Dollar and
backslash have no special meaning in that mode. Template replacement accepts:

| Form | Expansion |
| --- | --- |
| `$$` | One literal dollar |
| `$0` | Whole match |
| `$N` | Capture N; consume the entire decimal digit sequence |
| `${N}` | Capture N with an explicit closing brace |

Numbers permit leading zeros. `$12` selects group 12, rather than group 1
followed by a literal `2`. An existing but unmatched optional capture expands
to empty text. A matched empty capture also expands to empty text. A group
number outside `Regex.group_count()` is an error before matching or output,
even if no match would exist.

Backslash is an ordinary template character. Named references, defaults,
conditionals, callbacks and backslash escapes are unsupported. A dollar must
begin one of the listed forms: `$`, `$name`, `${}`, `${1`, `${1:-x}` and
overflowing decimal references are rejected. Other text, including Unicode
and NUL, passes through literally. Template diagnostic offsets count bytes
relative to the selected replacement Text.

Replacement validates limits and input first. It then checks replacement
logical metadata and the replacement byte cap before scanning replacement
UTF-8. This bounds accepted replacement validation by that cap. Template mode
preflights the complete grammar and every capture reference before allocating
tokens, searching or constructing output. Tokens borrow validated template
ranges and select capture numbers; every token allocation is released.

On any recoverable failure, the helper releases tokens, all acquired Matches,
partial output and temporary search owners. No partial replacement is
returned. Each String append checks the output cap before growing storage.
This all-or-nothing result contract preserves the borrowed sources. It does
not provide automatic cleanup for a trap, invalid physical backing or caller
ownership violations.

The helper performs O(template bytes) preflight and token construction, then
O(matches × tokens) template replay plus copied byte work. Replay can remain
large even when every capture is empty and output is small; the separate
match and replacement-byte caps bound that product. Searches retain the
matcher guide's per-call costs and can rescan suffixes. Live scratch, token
and output memory is bounded by their respective engine and byte capacities;
there is no aggregate allocation quota.

## Errors

`Error` distinguishes `InvalidLimits`, `Text(core::text::Error)`,
`Regex(ext::regex::Error)`, `Template(byte_offset)`,
`Capture(byte_offset,group)`, `SearchCallLimit`, `SearchWorkLimit`,
`OutputLimit`, `ReplacementLimit` and `AllocationFailed`.
Text validation preserves its exact error; matcher failure preserves its exact
error, including the matcher's own per-search WorkLimit and AllocationFailed.
The convenience module's AllocationFailed covers token/output storage.
Oversized replacement input returns ReplacementLimit after metadata checks
and before UTF-8 scanning. No bound establishes physical backing for a forged
Text; callers must supply initialized storage for every selected byte.

## Stdin rewrite program

[`sample_programs/library/regex_replace.lani`](../sample_programs/library/regex_replace.lani)
uses the existing `ext::cli` parser and these helpers:

```sh
regex-replace literal|template PATTERN REPLACEMENT [OPTIONS]
```

Named options are `--max-input`, `--max-output`, `--max-matches`, `--max-calls`
and `--max-work`; each accepts a nonnegative decimal integer, either attached
with `=` or in the next argument. Duplicate options and extra operands are
errors. `--` ends option parsing; `--help` or `-h` alone prints usage.

Defaults are 4 MiB input, 16 MiB output and the library's search defaults. The
sample keeps the existing Regex default per-search cap of 10,000,000 VM units.
Its aggregate `--max-work` reserves those complete allowances. Input and output
options accept at most 64 MiB; matches and calls retain the library's ranges.
Pattern and replacement remain ordinary UTF-8 arguments with a total snapshot
cap of 131,072 bytes and a fixed 65,536-byte replacement cap. Native argv cannot
contain NUL; NUL in stdin is valid text. Shell quoting supplies literal dollar,
backslash and space characters; the program adds no custom escape language.

The program reads bounded whole UTF-8 stdin, builds the complete owned result,
releases input and Regex owners, then writes only result bytes without an added
newline. A parse, resource or allocation failure occurs before stdout is
written. Output I/O failure can leave an accepted prefix; successful result
construction does not make stdout publication atomic. Standard stream copying
and write-all retry Interrupted without an attempt cap. Search `--max-calls`
does not count I/O attempts. Callers supply an external deadline for blocking
or interrupted I/O.

Exit status is 0 for success, 2 for arguments/text/pattern/resource errors,
3 for I/O failure, and 4 for allocation failure. Diagnostics go to stderr with
stage, code and an available byte offset. All ordinary error branches release
the active manual owners; SIGPIPE is explicitly ignored so write failures can
return through cleanup.

## Focused verification

[`tests/extended_regex_text_execution.rs`](../tests/extended_regex_text_execution.rs)
and the [fixture directory](../tests/fixtures/extended/regex_text) provide six
focused groups:

- Direct contracts for borrowed UTF-8 subranges, NUL, native and packed strides,
  exact empty-match progress, final tails, zero/truncated limits, fused failures,
  template preflight, independent output and actual-owner release.
- A deterministic 288-case Python `re` reference over nonempty shared-subset
  matches across three input layouts and all three operations. A checked
  32-case axis schedule makes every atom visit all four match caps and both
  pattern branches, and includes every input Text. Seed `0x6ab17a31` chooses
  replacements using upper PRNG bits. The Python matcher supplies independent
  matches/captures; it is test infrastructure only.
- An independent 89-case table for zero-width behavior, numeric templates,
  optional captures, malformed text, and exact/exceeded budgets. These tables
  specify differences from Python's empty-match behavior explicitly.
- All 77 reached baseline allocations in a bounded compile/template/split
  fixture. A single ENOMEM is injected per run; recovery probes verify source
  Regex/input usability. Exact mapping address/length ledgers require complete
  release, including partial scratch, token and String owners.
- Twenty-four sample CLI cases covering exact binary output, Unicode/NUL,
  normal and zero match truncation, named flags, resource errors and help.
- All 43 reached sample allocations plus single read/write EINTR and EIO
  schedules, checking status, stdout policy and exact owner release.

Each executable uses the unchanged strict native transfer validator. Native
processes have ten-second outer timeouts. Accepted receipts are:

| Gate | Native result | Log |
| --- | --- | --- |
| Direct contracts | 1/1 passed in 6.65 seconds | `target/stdlib-work/regex-text-contract-first.log` |
| Library allocation failures | 1/1 passed in 7.20 seconds; all 77 reached positions, with setup/compile/replacement/split/probe counts `1/8/32/27/9` | `target/stdlib-work/regex-text-allocation-first.log` |
| Reference and explicit tables | 2/2 passed in 7.80 seconds; 288 Python cases and 89 independent table cases | `target/stdlib-work/regex-text-model-tables-final.log` |
| CLI behavior, allocation and I/O | 2/2 passed in 8.33 seconds; nine exact binary cases, 14 rejections, help, all 43 reached OOMs and four single read/write EINTR/EIO schedules | `target/stdlib-work/regex-replace-program-typed.log` |

These were separate focused runs rather than one whole-suite timing. The
production library remained unchanged after its first accepted contract gate.
The final model has durable axis coverage assertions. Review found no
remaining ownership or oracle issue. The finite cases do not establish every
regex, allocation schedule, I/O interruption sequence or execution target.

The focused suite, after the required compiler build, is:

```sh
timeout --kill-after=2s 110s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 \
  CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --locked --test extended_regex_text_execution -- --nocapture --test-threads=1
```

### Confirmed nested-view compiler boundary

The CLI's original nested generic expression
`view(typed_slice_from_raw_parts(...), count).unwrap()` was rejected with
`LNC0047 GenericInstantiationBoundary`, detail 3. The
[untyped reduced fixture](../tests/fixtures/extended/regex_text/compiler_boundary/nested_view_untyped.lani)
reproduces compile exit 1. The paired
[typed control](../tests/fixtures/extended/regex_text/compiler_boundary/nested_view_typed.lani)
uses an explicit `[u8]` intermediate and explicit `<u8>` arguments; it compiled
and executed with exit 0, checking byte 120. The actual sample uses that typed
shape and passed its native gates.

Both the intermediate declaration and generic arguments changed in the
control. The evidence establishes those two source shapes; it does not isolate
a more specific inference cause or establish a compiler fix. No compiler
source changed for this vertical. Receipts are
`target/stdlib-work/regex-nested-view-untyped.log`,
`target/stdlib-work/regex-nested-view-typed.log` and
`target/stdlib-work/regex-nested-view-typed-native.log`. The wider
[context-inference dependency guide](library-context-inference-dependencies.md)
records this boundary alongside the other reduced inference controls.
