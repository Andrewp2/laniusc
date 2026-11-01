# Generic diff, hunks and fuzzy unified patches

`ext::seqdiff` diffs any two sequences of comparable items with linear-space
Myers or patience diff and groups the edit script into hunks.
`ext::unidiff` writes and parses unified diffs and applies them with GNU-style
offset and fuzz, reporting each rejected hunk with a typed reason. Import both
with `--source-root extended --stdlib-root stdlib`. The sample programs
`sample_programs/library/seq_diff.lani` (`diff -u` style) and
`sample_programs/library/seq_patch.lani` (`patch` style) use them on real files.

These modules sit beside the older exact-position pair
[`ext::diff`](extended-diff.md)/[`ext::patch`](extended-patch.md), which keep
their byte-line API, strict application and saved-trace Myers.

## Diff engine (`ext::seqdiff`)

| function | bound on `T` | result |
| --- | --- | --- |
| `myers(a, b, limits)` | `core::cmp::Eq<T>` | minimal script, linear space |
| `diff(a, b, algorithm, limits)` | `Eq<T>` and `core::hash::Hash<T>` | classify items, then Myers or patience |
| `classify(a, b, limits)` | `Eq<T>` and `Hash<T>` | `Classes { before, after, count }`: dense ids, equal items share one id |
| `patience_classes(a, b, classes, limits)` | ids in `[0, classes)` | patience script |
| `split_lines(bytes, limits)` / `diff_lines(a, b, algorithm, limits)` | `Line` | byte lines, each keeping its LF |

`a` and `b` are `core::slice::View<T>`. `Line { bytes }` implements `Eq`
(exact byte equality) and `Hash` (FNV-1a), so files go through the same generic
path as caller types; a caller type supplies its own `Eq`/`Hash` impls, and the
contract fixture uses a struct whose equality ignores one field. Hashes only
choose buckets; `Eq` decides every class.

`Script` exposes `len()`, `distance()` (insertions plus deletions),
`before_len()`, `after_len()` and `step(i) -> Result<Edit, Error>`.
`Edit { kind, before, after }` uses kind 0 equal, 1 delete (advances `before`)
and 2 insert (advances `after`); positions are zero-based. Within a change,
deletions come before insertions. Call `destroy()` on scripts, classes and
returned vectors.

**Myers.** This is Myers' linear-space refinement (*An O(ND) Difference
Algorithm and Its Variations*, 1986, section 4b), shaped like diff-match-patch's
`bisect`. Each range first trims its common prefix and suffix. Forward and
reverse furthest-reaching frontiers then advance until they overlap, and the
range splits at the overlap point. Ranges sit on an explicit stack, not in
recursion. Matches go into one `pair[before] = after` table, and the script is
read off that table at the end. The frontier rows and the match table hold
`O(N+M)` integers. Time is `O((N+M)·D)`. The script is always minimal; tie
breaking can differ from GNU diff's.

**Patience.** After trimming, the algorithm finds the items that occur exactly
once in both ranges, takes the longest increasing run of their positions
(patience sorting, `O(k log k)`), and uses those items as anchors. It then
repeats on the gaps between anchors. A gap with no unique common item falls back
to Myers, as git does. Patience scripts are valid but not always minimal.

**Hunks.** `hunks(script, context)` returns `Vec<Hunk { before, before_count,
after, after_count, first, count }>`. `first` and `count` give the hunk's slice
of script steps. Each hunk keeps up to `context` equal steps on each side, and
two changes separated by at most `2*context` equal steps share a hunk, as in
GNU diff.

**Limits and errors.** `Limits { max_items, max_work }` (default 4,000,000
items, 4·10⁹ work units) bound each sequence's length and the item comparisons
plus frontier work. `Error` is one of `InvalidLimits`, `Bounds`, `ItemLimit`,
`WorkLimit` or `AllocationFailed`. A failure publishes no partial script and
frees every temporary buffer.

## Unified diffs (`ext::unidiff`)

`write_unified(a, b, script, hunks, old_name, new_name, max_output)` produces
GNU `diff -u` hunk syntax. A count of one is omitted (`-3` rather than `-3,1`),
and an empty range names the line before it (`-4,0`). An incomplete final line
gets `\ No newline at end of file`. With no hunks the output is empty. Labels
must be nonempty and contain no NUL, CR or LF. Lines must be LF-terminated
except the last. Errors: `InvalidLine`, `InvalidHeader`, `OutputLimit`,
`AllocationFailed`.

`parse(input, max_lines)` reads the first file section of a unified diff.
Preamble lines before the `--- `/`+++ ` pair (such as `diff -u a b` or
`index ...`) are skipped. A TAB and timestamp end a header name. Text after the
closing `@@` (as from `diff -p`) is ignored. An empty body line counts as empty
context, and a `\` marker line strips the previous line's LF. Parsing stops at
the first line after the hunks that is not a hunk header; `Patch.end` records
that byte offset, so callers can continue with further file sections. Errors
are `ParseError { kind, offset }`, with `kind` one of `MissingHeader`,
`BadHunkHeader` (malformed numbers, or a nonempty range starting at 0), `BadLine`
(unknown prefix or too many lines for the counts), `BadMarker`, `Truncated`,
`LineLimit` or `AllocationFailed`. Empty input is a patch with no hunks.

`apply(base, patch, options)` returns `Applied { output, reports, rejected }`.
Hunks that do not match are reported, not fatal; their regions stay unchanged.
The search follows GNU patch 2.7:

- A hunk's expected line is its declared old start plus the previous hunk's
  final offset. Positions are tried nearest first (+1, -1, +2, ...), up to
  `max_offset`.
- Fuzz rises from 0 to `min(max_fuzz, context)`, where `context` is the
  larger of the hunk's leading and trailing context counts. At fuzz `f`, the
  algorithm ignores `f + lead - context` leading and `f + trail - context`
  trailing context lines. While the shorter side's count is negative, a hunk
  starting at line 1 must match at the start of the file, and a hunk with short
  trailing context must match at the end.
- A match may not start before the end of the previously applied hunk.
- Fuzzed-away context lines keep the base's text.

Each `HunkReport { index, status, reason, line, offset, fuzz }` has a
`HunkStatus` of `Exact`, `Offset`, `Fuzzed` or `Rejected`. A rejected hunk's
`RejectReason` is `NoMatch`, or `Overlap` when the hunk matched only before the
previous hunk's end. `line` is the one-based base line where the hunk applied,
or the expected line for a rejected hunk. `ApplyOptions { max_fuzz, max_offset,
max_lines, max_output, max_work }` defaults to fuzz 2 and unlimited offset.
Fatal `ApplyError`s are `InvalidOptions`, `LineLimit`, `WorkLimit`,
`OutputLimit` and `AllocationFailed`. Set `max_fuzz = 0` and `max_offset = 0`
for strict application.

## Sample programs

```sh
seq-diff [-U N] [--patience] OLD NEW           # exit 0 same, 1 differ, 2 error
seq-patch [-F N] [--max-offset N] BASE PATCH    # exit 0 applied, 1 rejects, 2 error
```

`seq-diff` writes `--- OLD` / `+++ NEW` and the hunks to stdout. `seq-patch`
writes the patched file to stdout and one GNU-worded line per hunk to stderr,
for example `Hunk #2 succeeded at 14 with fuzz 1 (offset 3 lines).` or
`Hunk #3 FAILED at 20 (no-match).`

## Verification

`tests/extended_seqdiff_execution.rs` compiles the contract fixture
`tests/fixtures/extended/seqdiff_contracts.lani` (generic `i32` and caller-type
sequences, patience anchors, hunk boundaries, exact writer bytes, parse error
kinds, offset/fuzz/reject statuses, limits) and both tools. It then runs
`tests/fixtures/extended/seqdiff_oracle.py`, which uses only independent
checkers:

1. **Minimality:** the Myers edit length equals an O(N·M) Python LCS distance.
2. **Round trip:** GNU `patch` and `seq-patch` turn the base into the target
   using our diffs (Myers at -U3 plus a random -U0/1/5, and patience).
3. **Interoperability:** `seq-patch` applies real GNU `diff -a -u`, `-U0` and
   `-U5` output.
4. **Offset and fuzz:** over files of distinct lines, bases with lines prepended, context lines edited, or
   blocks deleted give the same output bytes and the same rejected-hunk sets as
   GNU `patch -F0` and `-F2`.
5. **Scale:** 2,000-, 20,000- and 100,000-line pairs round-trip, and their edit
   length equals GNU `diff --minimal`'s.

Receipt for the 1,000-pair run (generated pairs over four line dictionaries,
including NUL, CRLF, non-UTF-8 bytes, diff-control-looking lines, missing final
LF and empty files), seed 20261031:

| check | count |
| --- | ---: |
| Myers edit length == O(N·M) LCS (differing pairs) | 878 |
| identical pairs with empty output and exit 0 | 122 |
| GNU patch reproduced target from our Myers -U3 diff | 878 |
| seq-patch reproduced target from our Myers -U3 diff | 878 |
| extra-context round trips -U0 / -U1 / -U5 (both patch tools) | 285 / 292 / 301 |
| patience valid (≥ LCS) and reproduced by both tools | 878 (867 also minimal) |
| GNU diff -u / -U0 / -U5 output applied exactly by seq-patch | 878 each |
| offset/fuzz cases agreeing with GNU patch -F0 (output and rejects) | 333 (135 with rejects) |
| offset/fuzz cases agreeing with GNU patch -F2 (output and rejects) | 333 (77 with rejects) |
| scale pairs, both algorithms, edit length == GNU --minimal | 3 sizes × 2 |

The registered Rust test runs the same oracle with 200 pairs. The 1,000-pair
receipt above came from running the two compiled tools directly
(`seqdiff_oracle.py SEQ_DIFF SEQ_PATCH WORKDIR 1000`) in 45 s; nearly all of
that time is process startup and the Python LCS.

**Speed.** The 100,000-line (1.6 MB) scale pair takes 0.85 s with Myers and
1.0 s with patience; GNU diff takes 0.05 s. Reading the 1.6 MB base through
`std::stream::copy` alone takes about 0.24 s, so per-byte code generation
dominates both I/O and line hashing. Comparisons themselves are on class ids.

Verified execution is x86_64 Linux output from the GPU compiler. Other targets
have not been verified.
