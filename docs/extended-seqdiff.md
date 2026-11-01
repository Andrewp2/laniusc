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
| `split_classify(a, b, limits)` / `diff_split(split, algorithm, limits)` | two byte views | `Split`: both files' lines and their class ids in one pass; the script `diff_lines` would give |
| `classify_lines(a, b, limits)` / `myers_classes(a, b, limits)` | `Line` / class ids | the specialized paths `diff_lines` uses |
| `split_classify3(o, a, b, limits)` / `classify_lines3(o, a, b, limits)` | three byte views / three `Line` views | `Split3` / `Classes3 { base, ours, theirs, count }`: one id space over three inputs (used by [three-way merge](extended-merge3.md)) |
| `diff_classes(a, b, classes, algorithm, limits)` | ids in `[0, classes)` | the chosen algorithm over class ids |
| `line_starts(bytes, limits)` | byte view | `Vec<i32>` of line offsets (one more entry than lines), the lines `split_lines` finds without hashes or records |
| `copy_bytes(target, view)` | raw target with room | copies the view's bytes, 8 at a time from packed storage |
| `xdiff_classes(a, b, limits)` | non-negative ids | git's xdiff alignment (`Algorithm::Xdiff`; see [word diff and diffstat](extended-wordiff.md)) |
| `histogram_classes(a, b, limits)` | non-negative ids | git's `--histogram` alignment (`Algorithm::Histogram`) |
| `diff_split_indent(split, algorithm, limits)` | `Split` | for `Xdiff` and `Histogram`, the script `git diff` gives: compaction with git's default indent heuristic over the line text |
| `function_hunks(split, script, context)` | `Split` and its script | the hunks of `git diff -W` (`--function-context`): each change's whole function is shown |

`a` and `b` are `core::slice::View<T>`. `Line { bytes, hash }` caches a hash
of its bytes, read as little-endian 8-byte words (the last one zero-padded),
folded by xor-multiply and mixed with the length. Build lines with
`split_lines`, `line(bytes)` or `Split.before_lines()`/`after_lines()` so the
hashes agree; packed byte storage takes a word path and any other `[u8]` a byte
path, and both give the same value. It implements `Eq`
(hash, then exact bytes) and `Hash`, so files go through the same generic
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

**Histogram.** `histogram_classes` ports git 2.43's `xhistogram.c` with lines
numbered from 1, as there. Each step indexes the old range by class: one record
chain per hash bucket, and each record holds its class's earliest occurrence,
an occurrence chain and a count. Then, for every new line, it extends each
matching occurrence into a common run. It keeps the longest run whose rarest
line is rarest (the lowest count), and recurses on both sides of that run. A
range whose common lines all occur more than 64 times falls back to xdiff on
that range without compaction (`xdl_fall_back_diff`), with the range's lines
renumbered densely. Git reports an error when a bucket chain holds 64
classes; this port falls back to xdiff instead. Bucket order and ties match
git because the buckets hash git's class ids: dense, first-occurrence order
over old then new, as `split_classify` assigns them, under `XDL_HASHLONG`
(`(v + (v >> b)) & (2^b - 1)`). Compaction (`xdl_change_compact`) follows the
recursion, and `diff_split_indent` adds git's indent heuristic: a group that
can slide, and matches no change on the other side, is placed at the split
with the best indentation score within 100 lines.

**Hunks.** `hunks(script, context)` returns `Vec<Hunk { before, before_count,
after, after_count, first, count }>`. `first` and `count` give the hunk's slice
of script steps. Each hunk keeps up to `context` equal steps on each side, and
two changes separated by at most `2*context` equal steps share a hunk, as in
GNU diff.

**Function context.** `function_hunks(split, script, context)` ports xdiff's
`XDL_EMIT_FUNCCONTEXT`. A function line is one that starts with an ASCII
letter, `_` or `$` (git's default rule). Each hunk starts at the function line
at or above its first change, moved up over the non-blank lines just above it.
It ends before the blank lines that precede the next function line below its
last change, or at the end of the file. A change appended at the end of the old
file that adds a function line keeps plain context. Changes that a hunk's
function reaches, or that have no function line between them, join that hunk.
As in git, the hunks can have unequal leading and trailing context, so GNU
`patch` may reject them; they are for reading.

**Split and classify in one pass.** `split_classify(a, b, limits)` reads each
input once. It finds LFs eight bytes at a time, with an exact zero-byte test
on `word ^ 0x0A0A…`. Each line is hashed from 8-byte words as soon as it ends,
then hash-consed into one open-addressing table shared by both sides. Equal
bytes, compared word by word, decide each class, so equal lines share an id.
Ids are dense, in first-occurrence order, as `classify_lines` assigns them. The
table doubles and rehashes from stored hashes. The result keeps lines as
offsets, not `Line` records:

| `Split` member | meaning |
| --- | --- |
| `before_len()` / `after_len()` | line counts |
| `before_line(i)` / `after_line(i)` | line `i` as a view into the input |
| `before_lines()` / `after_lines()` | `Vec<Line>` as `split_lines` makes them |
| `classes` | `Classes` over both sides |
| `destroy()` | frees offsets and classes; the inputs stay borrowed and must outlive the split |

Later sides are mostly the first side's lines in order. So each later line is
first compared, word by word, with the first-side line after the last one
matched. Only when that differs is it hashed and looked up, and a line found
in the first side moves the guess there. Ids are the same either way, since
an equal line has the same class. `split_classify3` does the same for three
inputs, with `Split3 { base, ours, theirs, base_starts, ours_starts,
theirs_starts, classes }`.

`diff_split(split, algorithm, limits)` diffs the class ids without consuming
the split. Inputs that are not packed bytes (native `[u8; N]` arrays) go
through `split_lines` and `classify_lines` with the same results.
`empty_split()` owns nothing.

**Limits and errors.** `Limits { max_items, max_work }` (default 4,000,000
items, 4·10⁹ work units) bound each sequence's length and the item comparisons
plus frontier work. `Error` is one of `InvalidLimits`, `Bounds`, `ItemLimit`,
`WorkLimit` or `AllocationFailed`. A failure publishes no partial script and
frees every temporary buffer.

## Unified diffs (`ext::unidiff`)

`write_unified(a, b, script, hunks, old_name, new_name, max_output)` produces
GNU `diff -u` hunk syntax. `write_unified_split(split, script, hunks, ...)`
writes the same bytes from a `Split`'s lines.
`write_unified_split_funcnames(split, script, hunks, ...)` adds git's hunk-header
function names: after `@@ ... @@` comes a space and the nearest function line
above the hunk's first line, searching no further up than the previous hunk's
first line, cut to 80 bytes (newline included) with trailing whitespace
removed. A hunk without one repeats the previous hunk's name. A count of one is omitted (`-3` rather than `-3,1`),
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
- A match may not start before the end of the previously applied hunk, and the
  hunk, including fuzzed-away leading context, may not start before line 1.
- Fuzzed-away context lines keep the base's text.

`apply` locates base lines by offset (`line_starts`), not `Line` records. It
sums the output size first, then allocates once and copies each unchanged run
of base lines whole.

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
seq-diff [-U N] [-W|--function-context] [--xdiff|--histogram|--myers|--patience] OLD NEW   # exit 0 same, 1 differ, 2 error
seq-patch [-F N] [--max-offset N] BASE PATCH    # exit 0 applied, 1 rejects, 2 error
```

`seq-patch` also patches whole trees from multi-file GNU and git patches
(`-i PATCH`, with GNU or `--git`/`--3way` semantics); see
[multi-file patches](extended-patchset.md).

`seq-diff` writes `--- OLD` / `+++ NEW` and the hunks to stdout. From the first
hunk header on, its default output (also `--xdiff`) is that of plain
`git diff --no-index`: git's xdiff alignment, its default indent heuristic and
its hunk-header function names. `--histogram` gives `git diff --histogram`, and
`-W`/`--function-context` gives `git diff -W` with either alignment.
`--myers` gives a minimal diff and `--patience` a patience diff; both print bare
GNU-style `@@ ... @@` headers. Its git-format
`--word-diff`, `--char-diff` and `--stat` modes are described in
[word diff and diffstat](extended-wordiff.md). `seq-patch`
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
   using our diffs (Myers at -U3 plus a random -U0/1/5, patience, and the
   git-style default at -U3).
3. **Interoperability:** `seq-patch` applies real GNU `diff -a -u`, `-U0` and
   `-U5` output.
4. **Offset and fuzz:** over files of distinct lines, bases with lines prepended, context lines edited, or
   blocks deleted give the same output bytes and the same rejected-hunk sets as
   GNU `patch -F0` and `-F2`. A second group repeats this over files built
   from a few repeated lines, where several positions can match.
5. **Scale:** 2,000-, 20,000- and 100,000-line pairs round-trip, and their edit
   length equals GNU `diff --minimal`'s.

`tests/fixtures/extended/git_diff_oracle.py SEQ_DIFF WORKDIR [PAIRS]` checks
seq-diff against plain `git diff --no-index` in three modes per pair: the
default (every fourth pair as `--xdiff`), `--histogram`, and `-W` or
`--function-context` (30% of them with `--histogram`), each with a random `-U`
on 30% of pairs. It compares exact bytes from the first hunk header on, and the
exit status. git runs with an empty global configuration, so its defaults
apply: the indent heuristic and default function names. Receipt for 4,000 pairs
(seed 20261101, 12,000 comparisons, 96 s on a loaded machine), every one
agreeing. Each cell is pairs / pairs that differ / pairs with a named hunk
header / pairs with identical bytes and status; "wider" counts pairs whose `-W`
output differs from the default output:

| group | default | `--histogram` | `-W` | wider |
| --- | ---: | ---: | ---: | ---: |
| distinct lines, small edits | 804 / 664 / 221 / 804 | 804 / 664 / 221 / 804 | 804 / 664 / 221 / 804 | 1 |
| a few repeated values | 802 / 687 / 361 / 802 | 802 / 687 / 359 / 802 | 802 / 687 / 353 / 802 | 80 |
| indented code blocks with blank lines | 798 / 796 / 552 / 798 | 798 / 796 / 552 / 798 | 798 / 796 / 332 / 798 | 470 |
| C-like functions (comments, long and odd first bytes) | 798 / 728 / 462 / 798 | 798 / 728 / 462 / 798 | 798 / 728 / 363 / 798 | 289 |
| two to four values, each over 64 times (xdiff fallback) | 266 / 266 / 255 / 266 | 266 / 266 / 255 / 266 | 266 / 266 / 255 / 266 | 80 |
| unique lines among heavy repeats | 266 / 265 / 265 / 266 | 266 / 265 / 265 / 266 | 266 / 265 / 265 / 266 | 111 |
| 200-600 lines, many edits | 266 / 266 / 266 / 266 | 266 / 266 / 266 / 266 | 266 / 266 / 266 / 266 | 1 |

The oracle catches errors in the special paths. With git's indent heuristic
switched off, 65 of 600 histogram pairs differ. With the histogram fallback
disabled in a build, 49 of 50 heavy pairs differ. A build that cuts function
names at 81 bytes fails 78 of 1,200 pairs, and one without the appended-function
rule of `-W` fails 11. The registered test
(`tests/extended_wordiff_execution.rs`) runs 1,200 pairs. The 1.6 MB pair is
also identical to git in the default and `-W` modes.

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
| default (git xdiff, function names) -U3 reproduced by both tools | 878 |
| GNU diff -u / -U0 / -U5 output applied exactly by seq-patch | 878 each |
| offset/fuzz cases agreeing with GNU patch -F0 (output and rejects) | 333 (135 with rejects) |
| offset/fuzz cases agreeing with GNU patch -F2 (output and rejects) | 333 (77 with rejects) |
| repeated-line offset/fuzz cases agreeing with GNU patch -F0 | 328 (129 with rejects) |
| repeated-line offset/fuzz cases agreeing with GNU patch -F2 | 328 (53 with rejects) |
| scale pairs, both algorithms, edit length == GNU --minimal | 3 sizes × 2 |

The registered Rust test runs the same oracle with 200 pairs. The 1,000-pair
receipt above came from running the two compiled tools directly
(`seqdiff_oracle.py SEQ_DIFF SEQ_PATCH WORKDIR 1000`) in 43 s; nearly all of
that time is process startup and the Python LCS.

**Speed.** The 100,000-line (1.6 MB) scale pair produces byte-identical
output in every mode before and after this work. Wall times are the best of
10 runs on the target laptop, measured alongside other agents' jobs. Each
`git diff --no-index` run used the same flags and load:

| mode | before | now | git |
| --- | ---: | ---: | ---: |
| unified, Myers (default) | 182 ms | 59-70 ms | 43 ms |
| unified, `--xdiff` | 161 ms | 47-63 ms | 31-43 ms |
| `--word-diff` | 273 ms | 66-90 ms | 36-54 ms |
| `--char-diff` | — | 75-119 ms | 41-67 ms |
| `--stat` | 140 ms | 47-96 ms | 33-61 ms |
| `--patience` | 216 ms | 141 ms | — |

GNU `diff -u` takes 33 ms. With the later-side line prediction (see
`split_classify`), the default unified diff later measured 58 ms against
git's 45 ms under the same load. Phase times inside the program (best of 7, both
files, quieter machine):

| phase | before | now | change |
| --- | ---: | ---: | --- |
| read | 15 ms | 2 ms | `seq-diff` sizes each buffer from the file length plus `read_to_end`'s 64 KiB window, so the buffer never regrows (growth copied byte by byte) |
| split + classify | 37 + 35 ms | 26 ms | `split_classify`: one pass per file; LFs found 8 bytes at a time; lines hashed from words and hash-consed at once; lines kept as `i32` offsets, not six-word `Line` records |
| Myers | 22 ms | 22 ms | unchanged here; see the Myers row below |
| xdiff | 50 ms | 21 ms | kept records written to presized slots instead of two `try_push` per record; script written into counted slots; one workspace allocation instead of twelve |
| render | 2.4 ms | 2.2 ms | `write_unified_split` reads lines from offsets; steps read from the slice, not through `step()` results |
| word diff render | 63 ms | ~45 ms | no `Vec<Line>` materialized (`write_word_diff_split`); per group one workspace in `xdiff_classes`, one table allocation in `classify_lines` and a reserved word vector |

Allocations are system calls (each `Vec` allocation maps fresh memory), so
the per-group allocation count, not the arithmetic, dominated word diff.

A second pass on the default mode measured 41 ms against git's 33-35 ms on a
quieter machine (best of 20, interleaved; 1.2×, from 1.29×). Phases, best of
9:

| phase | before | now | change |
| --- | ---: | ---: | --- |
| table setup | 4.2 ms | 0.7 ms | one raw buffer: slots filled with -1 eight bytes at a time, one four-int record per class (a probe touches one record, not four arrays) |
| scan, first file | 21 ms | 12 ms | hash and line compare inlined in the scan loop (calls with many arguments are costly); the record layout above |
| scan, second file | 14 ms | 7 ms | the same |
| Myers engine setup | 2.3 ms | 0.3 ms | match table and frontier rows in one unfilled raw buffer (rows are initialized lazily); only the match table is filled, eight bytes at a time |
| Myers run | 28.7 ms | 14 ms | the bisection keeps its work budget in locals instead of calling `sd_charge` per diagonal; each diagonal reads one new frontier value (its neighbour carries over); a snake has one bound per step |

The first two rows were measured at high load (load average about 15), the
rest at about 8. The Myers run is the minimal algorithm's `D²` diagonal walk,
at about 6 ns per diagonal. `seq-diff --histogram` takes 55-60 ms against
35-41 ms for `git diff --histogram`.

The tables above measured the earlier Myers default. The default is now the
git-style xdiff mode with the indent heuristic and function names. At a load
average of about 15, best of 15, it took 79 ms against 67 ms for plain
`git diff --no-index` (1.2×). `--myers` took 76 ms and `-W` 78 ms in the same run.

The code generator still limits loops. Every value goes through the stack,
each element access emits a bounds check, constants are reloaded, and loop
invariants are not hoisted. A plain byte loop that counts LFs
(`tests/fixtures/compiler_defects/byte_loop_codegen.lani`) costs 2.8 ns/byte,
against under 0.1 ns for `gcc -O2`. The fused scan avoids most per-byte work
by reading 8-byte words. Its hot values sit in locals because field and
constant reads are not hoisted.

Verified execution is x86_64 Linux output from the GPU compiler. Other targets
have not been verified.
