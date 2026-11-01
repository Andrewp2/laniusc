# Word diff and diffstat

`ext::wordiff` writes git's `--word-diff=plain` output at word or character
level. `ext::diffstat` writes git's `--stat` summary, either from scripts or
from unified diffs that git, `diff -u` or `diff -ruN` produced. Both build on
the [generic diff engine](extended-seqdiff.md). That engine now also offers
`Algorithm::Xdiff`, a port of git's xdiff alignment, so the output matches
git's byte for byte. `seq-diff` gains `--word-diff`, `--char-diff` and
`--stat`, and `sample_programs/library/seq_diffstat.lani` is a diffstat tool
for patches. Import with `--source-root extended --stdlib-root stdlib`.

## git's alignment: `Algorithm::Xdiff`

`ext::seqdiff::xdiff_classes(a, b, limits)` (also `diff`/`diff_lines` with
`Algorithm::Xdiff`) follows git 2.43's `xdiffi.c` and `xprepare.c` with flags 0.
It runs these steps:

1. Trims the common prefix and suffix.
2. Discards items that have no match on the other side. Items with many
   matches (at least the shift-based square root of the length, capped at
   1,024) are also discarded when they sit inside runs of unmatched items
   (`xdl_clean_mmatch`: a 100-item window, keep ratio 1/4).
3. Splits ranges with `xdl_split`'s middle snake, using xdiff's diagonal order
   and tie rules. Above edit cost 256 it applies the same heuristics: a split
   at a 20-item snake, and the furthest-reaching split at the cost limit.
4. Compacts change groups: each group slides up and then down as far as equal
   items allow, merging groups it meets. A group that can line up with a
   change on the other side is moved to the last such position; otherwise it
   stays at its lowest position.

The result is not always minimal, which is git's own behavior. git's indent
heuristic for line diffs is not ported. Word diffs never use it, but git's
line diff does, so line hunks can differ from git when that heuristic moves a
slidable group. The oracle below found no such case. `myers` and
`myers_classes` remain the minimal choice.

## Word diff

`split_words(text, mode, limits)` returns views of the words as
`ext::seqdiff::Line` values (with hashes):

- `Mode::Words`: maximal runs of bytes other than space, TAB, CR and LF, git's
  default.
- `Mode::Chars`: every well-formed UTF-8 character except LF, the same as git
  `--word-diff-regex=.` under a UTF-8 locale. Malformed bytes (bad leads,
  overlong forms, surrogates, values above U+10FFFF) are not characters,
  because glibc's regex `.` does not match them. They separate characters, as
  LF does.

`write_word_diff(a, b, script, hunks, old_name, new_name, options)` takes the
same line inputs as `ext::unidiff::write_unified`. It writes `--- `/`+++ `
headers, then each hunk with:

- **Header.** A git-style hunk header. With `options.function_names`, it ends
  with git's default function line: the nearest line above the hunk, searching
  back no further than the previous hunk's start, whose first byte is an ASCII
  letter, `_` or `$`. The line is cut to 80 bytes and loses trailing
  whitespace. When no line is found, the previous one is reused.
- **Context lines.** Printed without the leading space; a missing final LF is
  supplied.
- **Change groups.** Each maximal run of removed and added lines is word-diffed
  as one group, the way git's `diff_words_show` does:
  - **Removal only.** When the added side is empty, the removed text is printed
    whole as `[-...-]`.
  - **Both sides.** Otherwise both texts are split into words and aligned with
    `Algorithm::Xdiff`.
    - Unchanged words, and all whitespace between words, are printed from the
      added side.
    - A removed run spans from its first word to its last, including the
      whitespace inside it.
    - Each LF-free piece of a run is wrapped as `[-old-]` or `{+new+}`.

`write_group(minus, plus, options)` writes one group. Options are
`Options { mode, function_names, max_output, limits }`, from
`default_options(mode)`. The errors are `InvalidInput`, `ItemLimit`,
`WorkLimit`, `OutputLimit` and `AllocationFailed`.

## Diffstat

`Stats` holds `FileStat { name_start, name_length, added, deleted,
interesting }` entries plus a byte arena of print names. It provides `len`,
`get`, `name(i)` and `destroy`.

- `add_file(stats, name, added, deleted)` stores a name exactly as given.
- `add_pair(stats, old, new, added, deleted)` names a compared pair the way
  `git diff --no-index` does. Equal paths are quoted when needed. Different
  paths use git's `pprint_rename` form, such as `dir/{a => b}/file`, and the
  quoted form `"A" => "B"` when either path needs quoting.
- Quoting is git's `quote_c_style` with `core.quotePath`: control bytes, `"`,
  `\`, DEL and bytes above 0x7f, with octal escapes.
- `count_script(script)` returns `Counts { added, deleted }`.

`write_stat(stats, StatOptions { width, name_width, graph_width, count,
max_output })` follows git's `show_stats`:

- **Name column.** The longest shown name, capped by `name_width`. The name
  column gets at most 5/8 of `width`, which is at least 16 + 6 + digits.
- **Graph column.** The largest change, capped by `graph_width` and by 3/8 of
  `width`.
- **Truncation.** Long names become `...` plus their tail, cut back to the
  first `/` that remains.
- **Scaling.** The graph is scaled with `1 + n*(width-1)/max`, and a file that
  has both additions and deletions shows at least one `+` and one `-`.
- **Count.** `count` lists that many files, then ` ...`.
- **Summary.** The summary line covers all files. An empty `Stats` gives no
  output, and ` 0 files changed` appears when every file is hidden (not
  `interesting` and unchanged).
- **Defaults.** `default_stat_options()` uses width 80, git's value when stdout
  is not a terminal.
- **Width counting.** Unquoted UTF-8 names count one column per character;
  wide characters are not counted as two.

`parse_patch(text, strip, max_files)` counts `+`/`-` lines per file section.

- **Sections.** A section starts at a `diff ` line, or at a `--- ` header that
  follows another section's hunks.
- **Hunks.** Hunk bodies are consumed by their header counts, so content lines
  such as `--- x` are not mistaken for headers.
- **Names.** Rename lines give `pprint_rename` names. Otherwise the `+++` path
  is used, or the `---` path for deletions, then the `diff --git` line when a
  section has neither, as with mode changes and empty new files.
- **Path cleanup.**
  - Timestamps after a TAB are dropped.
  - Quoted names, both git's and GNU diff's, are decoded and quoted again by
    git's rules.
  - `strip` drops leading components: -1 drops one from `diff --git` sections
    and none elsewhere.
- **Errors.** Binary sections are `Unsupported`, because git prints their byte
  sizes. A malformed or truncated hunk is `InvalidInput`, and more than
  `max_files` sections is `FileLimit`.

## Tools

```sh
seq-diff [-U N] [--myers|--patience|--xdiff] [--word-diff|--char-diff|--stat[=W[,N[,C]]]] OLD NEW
seq-diffstat [-p N] [--stat=W[,N[,C]]] [PATCH]
```

`--word-diff` (also `--word-diff=plain`), `--char-diff` (also
`--word-diff-regex=.`) and `--stat` match `git diff --no-index` with the same
options. These modes align lines with `--xdiff` unless an algorithm is given.
Word diffs print `--- OLD`/`+++ NEW` instead of git's `diff --git` and `index`
lines; everything from the first hunk on is git's output. `seq-diffstat` reads
PATCH or stdin and prints what `git diff --stat` prints for the same change.
Exit status is 0 identical / 1 different / 2 error for `seq-diff`, and 0 / 2
for `seq-diffstat`.

## Verification

`tests/extended_wordiff_execution.rs` runs
`tests/fixtures/extended/wordiff_contracts.lani`: 30 checks covering word and
character splitting, malformed UTF-8, every group form, function-line headers,
missing final LF, output limits, xdiff trimming and group sliding, rename
names, quoting, scaled and truncated stats, `count`, git and plain patch
parsing, and the error kinds. It then runs
`tests/fixtures/extended/wordiff_oracle.py` with 400 pairs.

The oracle compares exact bytes and exit status against git 2.43
(`LC_ALL=C.UTF-8`, `COLUMNS` unset) in these groups:

- **Pairs.** Each pair runs `--word-diff`, `--char-diff` and `--stat` or a
  random `--stat=W[,N]`.
  - **Distinct.** Distinct words (ASCII, Latin and CJK stems).
  - **Repeated.** A 15-word vocabulary with blank lines.
  - **Big.** 200-400 lines with 60-120 edits.
  - **Heuristic.** Long unrelated or 10%-corrupted texts over 2-5 symbol
    alphabets, so edit costs exceed 256 and malformed UTF-8 appears.
  - **Text variations.** Leading tabs and spaces, trailing CR and missing
    final LFs.
- **Repositories.** One to ten files are edited, deleted, added, renamed into
  `moved/` or `*.renamed`, mode-changed or left empty. Names include
  directories, spaces, `é`, `"` and 70-byte paths. `seq-diffstat` reads `git
  diff HEAD` and must match `git diff --stat HEAD` plus two `--stat=W,N,C`
  variants. In text-only repositories it must also match `git diff
  --no-renames --stat` when reading `diff -ruN` output with `-p 1`.

Receipt for 2,000 generated pairs plus 40 heuristic pairs and 500 repositories
(seed 20261031, `--strict-repeated`, 82 s, run directly on the compiled
tools):

| group | cases | identical to git |
| --- | ---: | ---: |
| word diff: distinct / repeated / big / heuristic | 950 / 950 / 100 / 40 | all |
| character diff: distinct / repeated / big / heuristic | 950 / 950 / 100 / 40 | all |
| `--stat` on pairs | 2,040 | all |
| `seq-diffstat` on `git diff HEAD` (3 widths each) | 1,500 | all |
| `seq-diffstat -p 1` on `diff -ruN` | 282 | all |

Three more `diff -ruN` repositories were skipped because GNU diff's own
script had different line counts from git's. A control build without xdiff's
cost heuristics agrees on only 8 of 20 heuristic character pairs and 3 of 25
big distinct character pairs, so the heuristics are exercised.

git 2.43 prints bytes from outside the name for `--stat` name widths 1-4, so
the oracle does not use those widths.

On the 1.6 MB scale pair from the [seqdiff guide](extended-seqdiff.md),
`--word-diff`, `--char-diff` and `--stat` produce git's output in 0.32 s,
0.31 s and 0.18 s, while git takes 0.04-0.06 s.

Verified execution is x86_64 Linux output from the GPU compiler. Other targets
have not been verified.
