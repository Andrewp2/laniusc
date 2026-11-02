# UTF-8 text search

`sample_programs/library/text_grep.lani` filters stdin, files or directory
trees with one compiled [regular expression](extended-regex.md). It composes
`ext::regex`, `ext::cli`, `std::args`, `std::stream`, checked `core::text`,
`core::fmt`, and an owned, reusable `alloc::vec` input buffer. File operands
and `-r` add `std::directory`, `std::file_ops`, [`ext::fnmatch`](extended-fnmatch.md)
and [`ext::gitignore`](extended-gitignore.md); see
[Files and recursive search](#files-and-recursive-search). Production search
and I/O run in Lanius.

Build and run from the repository root:

```sh
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  --stdlib-root stdlib --source-root extended \
  sample_programs/library/text_grep.lani -o /tmp/text-grep
printf 'info: ready\nerror: disk full\nerror: retry\n' | timeout 10s /tmp/text-grep -n '^error:'
```

Output:

```text
2:error: disk full
3:error: retry
```

The command takes exactly one pattern. Quote the pattern for the shell; shell
quoting is removed before the program sees it. Use `--` before a pattern that
starts with a dash:

```sh
printf 'one\n-a\ntwo\n' | timeout 10s /tmp/text-grep -- '-a'
printf 'ok\nerror\nwarning\n' | timeout 10s /tmp/text-grep -vc 'error|warning'
```

## Records and matching

LF ends a record. The final nonempty sequence before EOF is also a record, even
without LF. Empty input contains zero records; `\n` contains one empty record.
No extra empty record is synthesized after the final LF.

Search sees the record without LF. A CR immediately before LF is also excluded
from search, so `^name$` selects both `name\n` and `name\r\n`. A final CR without
LF, and CR elsewhere in a record, remain searchable text. A selected record is
written with its original bytes, including CRLF or the absence of a final LF.
Embedded NUL is valid UTF-8 and is retained. For example, `\x00` can select a line
containing NUL even though a native argument cannot itself contain NUL.

All input records are checked for valid UTF-8, including records that would not
be selected and records processed with `--invert` or `--count`. Malformed input
is an error. The program does not replace characters, truncate a record, or
interpret a malformed expression as literal text. An empty pattern matches every
record, including an empty record. Matching uses Unicode scalar values, exact
literal spelling, and the provider's ASCII `\d`, `\s`, `\w`, and word-boundary
semantics. No Unicode normalization or case folding is performed.

The provider supports alternatives, groups, character classes and ranges,
greedy and lazy repetition, anchors, fixed-width lookbehind, and Unicode
properties. Lookahead, backreferences, possessive quantifiers, and unsupported escapes fail explicitly;
see the provider guide for the complete grammar. Default multiline and dot
options are used. Each logical record is searched independently.

## Options and limits

| Option | Default | Meaning |
| --- | ---: | --- |
| `--invert`, `-v` | false | Select records that do not match. |
| `--line-number`, `-n` | false | Prefix each selected record with its decimal line number and `:`. |
| `--count`, `-c` | false | Write only the number of selected records followed by LF, after EOF. |
| `--max-line N` | 1048576 | Maximum bytes before each LF; CR counts. Accepted range 0–67108864. |
| `--max-pattern N` | 65536 | Maximum pattern bytes. Accepted range 0–65536. |
| `--max-states N` | 4096 | Maximum compiled regex states. Accepted range 4–65536. |
| `--max-groups N` | 16 | Maximum explicit capture groups; group zero is additional. Accepted range 0–128. |
| `--max-work N` | 10000000 | Work budget for each record search. Accepted range 1–2147483647. |
| `--recursive`, `-r` | false | Search directory operands, or `.` when there is none, recursively. |
| `--include GLOB` | | Search only files whose name matches GLOB (repeatable). |
| `--exclude GLOB` | | Skip files whose name matches GLOB (repeatable). |
| `--exclude-dir GLOB` | | Do not enter directories whose name matches GLOB (repeatable). |
| `--gitignore` | false | With `-r`, skip what the `.gitignore` files of the walked tree ignore, and `.git` directories. |
| `--help`, `-h` | | Write usage and exit. |

With file operands or `-r`, `--max-line` defaults to 67108864 and
`--max-work` to 2147483647, since whole files are in memory.
Long options accept `--name N` and `--name=N`; short flags may be combined.
Options and the pattern may be intermixed until `--`. Repeated flags remain
enabled; the last repeated numeric value wins. Numeric values are unsigned
decimal. `--count` takes precedence over `--line-number`; its count includes the
inversion setting. Line numbers start at one and include every empty or
unselected record. A zero line limit accepts empty LF records but rejects a CRLF
record because its CR counts toward the limit.

The program retains the provider's nesting-depth limit of 64 and bounded-repeat
limit of 1000. Argument capture accepts at most 64 arguments totaling 69632 bytes,
excluding the executable and trailing NULs. These are hard limits independent of
any smaller requested pattern limit. Selection counts and line numbers are
checked against `u64` capacity.

The work budget starts afresh for each regex search; it is not a total process
instruction count. Input scanning, UTF-8 validation, and native I/O are outside
that budget. The line limit bounds input storage per record. The process may
consume an unlimited number of records, retaining one geometrically growing
buffer and one compiled regex. A pattern without lookbehind also gets one
capture-free [lazy DFA](extended-regex.md#capture-free-dfa-matching), which
answers each record exactly as the VM would, anchors and word boundaries
included. VM scratch is created and released only for a search the DFA cannot
decide, or for patterns with lookbehind. On a
915,606-byte, 25,000-line corpus, `-c` searches for `zzz`, `abs`, `max\(`,
`(min|max)\([^)]*,`, `9{3,}` and `[0-9]+ *\*\* *[0-9]+` dropped from
3.0–3.8 s to 0.15–0.23 s each, with identical counts and `-n` output. The
Since anchors and word boundaries became DFA state, the assertion patterns
below dropped as well (`-c`, same corpus, before / best of three after):

| Pattern | VM | Lazy DFA |
| --- | ---: | ---: |
| `^ *1` | 2.64 s | 0.10 s |
| `\bmax\b` | 2.40 s | 0.09 s |
| `[0-9]+$` | 2.68 s | 0.09 s |
| `^\(` | 2.26 s | 0.09 s |
| `\B9\b` | 2.44 s | 0.09 s |
| `1$\|^2` | 2.46 s | 0.09 s |
| `abs` (no assertion) | 0.13 s | 0.09 s |

Counts and `-n` output are byte-identical before and after. These are wall
times on a laptop with other work running; log
`target/claude-work/s3/grep-assert-timings.log`. A failed DFA cache
allocation is an allocation failure (status 4, `stage=pattern`); only a
pattern with lookbehind uses the VM instead. Spare line capacity and regex scratch mean these limits do not specify a
total memory limit. The input is read with `std::fs::read`, up to 64 KiB per
call, straight into the record buffer. A UTF-8 sequence or record may cross a
read boundary safely, because validation happens after record assembly.
Selected records collect in one fixed 64 KiB output area. It is allocated at
the first selected record and is never grown. It is written when the next
piece would not fit, at EOF, and before any error is reported. If that last
write fails, the status is 3 at `stage=output`, in place of the earlier
error. A record of 64 KiB or more is written straight from the input buffer.
Records are copied in eight-byte words. The 32 bytes in front of the area keep
the last line number in decimal, so the next number is one increment with
carry and only a jump in numbering runs the division loop. `--invert` uses
both scans: the records between literal hits, or before the line scan's next
match, are the selected ones. With `--count` only their number is added.

## Literal prefilter

Before the scan, `Regex.required_literal` gives the longest literal that every
match contains (up to 256 bytes). For each 64 KiB read, the complete records
form one region. text_grep looks for the literal across the whole region,
and only the records containing it go to the matcher. One pass over
each gap between those records checks UTF-8 and counts its LFs, eight bytes per
step, so line numbers and errors stay exact. Without `--invert` that pass also
covers the hit record up to its LF, so the record is not validated again;
if the combined range is invalid, the gap and the record are checked apart,
as before.

The literal search (`find_pair`) gives the same answer as
`core::search::find` and probes the same two needle offsets: the rarest byte
by `core::search::rank`, and the rarest byte that differs from it. It tests
eight candidate starts per step, in two word views of the region shifted by
the two offsets, and compares the whole needle only where both bytes match.
Two words without the first probe byte are skipped together. `find` instead
calls `find_byte` for the first probe byte and checks the second byte at each
of its hits, which costs one call per occurrence of a common byte such as the
`h` of `the`. Full compares past `core::search`'s linear budget hand the rest
of the region to `core::search::find`, which then switches to Two-Way, so the
search stays linear. When the pattern is that literal
alone (`Regex.literal_length()`) and it has no CR or LF, a valid record that
contains it is selected without running the matcher at all. The region path
is used only when none of its records can exceed `--max-line` and none can
reach `WorkLimit`, which is the bound the DFA uses: `(region bytes + 2) *
boundary_cost <= max_work`. It is not used with `--invert` or for patterns
with lookbehind. Otherwise, and from an invalid gap onward, records go one at
a time. Each of them still skips the matcher when it lacks the literal and
cannot reach `WorkLimit`. Output, status and diagnostics are byte-identical to
the record-at-a-time scan.
`tests/fixtures/extended/text_grep_scan/compare.py` checks that against a
build from before the change on generated inputs. The inputs mix multibyte
scalars, CR, NUL, invalid UTF-8, records over 64 KiB, `-v`, `-n`, `-c`, small
`--max-line` and small `--max-work`. A third of the inputs have 3,000
records, which brings in dense literal hits and long line scans. Seeds
20261031, 1 and 2 gave 1,500/1,500 identical runs, both before and after the
output rework (`text-grep-output-receipt.log`) and after the skip and numbered
blocks (`text-grep-numbers-receipt.log`) and after the counting scan
(`text-grep-count-receipt.log`) and after the word-wise literal search
(`text-grep-pair-receipt.log`) and after the file and recursive modes, which
moved the record loop into a shared `block` function
(`text-grep-recursive-scan-receipt.log`), and after the file-mode literal
path and the inline UTF-8 check (`text-grep-speed-scan-receipt.log`, each
seed in two halves with `--from 750`), tiny build included. A build with a 3-state DFA
cache and 2 partials gave 800/800 on seeds 20261031 and 7, which forces the
undecided-record path (log `target/claude-work/s3/text-grep-scan-receipt.log`).

Patterns with no required literal use the
[line scan](extended-regex.md#line-scanning): `Dfa.match_lines` runs over the
whole region in one pass and stops only at a record that matches or that it
cannot decide. text_grep checks the rest of a matching record, emits it, and
resumes after its LF. An undecided record goes through the per-record path,
which runs the VM or reports the UTF-8 error at its exact offset. With
`--invert`, the records the scan passed over are the ones selected. The
literal path also switches to the line scan for the rest of a region when hit
records come denser than one per 256 bytes (after 32 hits), unless the
pattern is a pure literal. Each hit record it still handles goes through
`match_lines` on that record alone.

The between-hit pass is the SWAR loop that was asked for. It tests two 8-byte
words at a time for any high bit, so all-ASCII words skip the scalar
validator. For newlines it computes `((w ^ 0x0a..0a) + 0x7f..7f) & 0x80..80`,
which marks the bytes that are not LF. On an ASCII word this has no carries
between lanes, so it is exact. The marks add up in byte lanes and are folded
every 255 words, which costs less than a popcount or multiply per word. Only a
word with a high bit goes byte by byte through `core::utf8`. Matching records
used to be validated twice, once by text_grep and once byte-wise inside
`Dfa.is_match`. They now go through `Dfa.is_match_input`, so the matcher does
not check them again.

The table compares GNU grep 3.11 (`-E`, `en_US.UTF-8`) with text_grep on
S4's 48,770,754-byte, 814,590-line Rust-heavy corpus. Times are best of three
wall times in ms, with stdout written to a file. Every row's output (`-c`
count, or the `-n` listing) is byte-identical to GNU's. "Before" is the build
from the assertion commit above, which used 1024-byte reads, a matcher run
on every record and one write per record. The laptop had other work running
(load 10–19). Logs: `target/claude-work/s3/grep-lines-timings.log` (this
table), `grep-prefilter-timings.log` (prefilter build), `grep-unicode-timings.log`
and `grep-unicode-lines-timings.log`.

| Pattern | Before `-c` | `-c` | `-n` | GNU `-c` | GNU `-n` |
| --- | ---: | ---: | ---: | ---: | ---: |
| `zzzz` (no match) | 5176 | 64 | 63 | 8 | 15 |
| `core::result::Result` (8,682 lines) | 5035 | 132 | 141 | 15 | 24 |
| `fn main` | 5024 | 99 | 102 | 29 | 36 |
| `the` | 5552 | 210 | 426 | 54 | 90 |
| `^\s*//` | 4835 | 88 | 113 | 24 | 34 |
| `\bResult<` | 5066 | 87 | 108 | 14 | 24 |
| `fn [a-z_]+_main\(` | 4717 | 78 | 76 | 13 | 20 |
| `[0-9]+$` (no required literal) | 1771 | 543 | 542 | 37 | 49 |
| `a.c` (literal `a` on most lines) | 1224 | 538 | 618 | 73 | 91 |

For `[0-9]+$` and `a.c`, "Before" is the prefilter build before the line
scan, which ran the DFA record by record. With `-v -c`, `[0-9]+$` went from
1414 ms to 663 ms (GNU 48 ms). `-v -n` writes 800,000 numbered lines and
took 1737 ms (GNU 177 ms), mostly formatting output. Log:
`target/claude-work/s3/grep-lines-timings.log`.

The output path and `--invert` were then reworked as described under
[Options and limits](#options-and-limits). Same corpus, best of three in ms
(load 12–16; log `target/claude-work/s3/grep-output-timings.log`). "Before"
is the line-scan build above, run in the same session. Every row's output is
byte-identical to GNU's.

| Pattern | Mode | Before | After | GNU |
| --- | --- | ---: | ---: | ---: |
| `[0-9]+$` | `-v -n` | 2547 | 891 | 271 |
| `[0-9]+$` | `-v` | 1041 | 558 | 131 |
| `[0-9]+$` | `-v -c` | 703 | 430 | 54 |
| `[0-9]+$` | `-n` | 555 | 384 | 45 |
| `the` | `-v -n` | 1435 | 430 | 204 |
| `the` | `-v` | 735 | 341 | 119 |
| `the` | `-n` | 449 | 216 | 91 |
| `the` | `-v -c` | 420 | 148 | 58 |
| `fn main` | `-v -n` | 1374 | 392 | 202 |
| `fn main` | `-v -c` | 268 | 107 | 38 |

`-c` times also fell, for example `[0-9]+$` from 592 to 400 ms, although the
`-c` path did not change. The other difference between the two builds is the
compiler from the merged lang branch, so part of every gain may come from
code generation.

Then the per-line costs were removed (log
`target/claude-work/s3/grep-numbers-timings.log`):

- **Inverted blocks:** with `--invert`, a run of selected records between
  matches is handled as one block. With `-c` only its line count, which the
  8-byte gap pass already has, is added. Without `-n`, a block of 4 KiB or
  more is written straight from the input buffer, and a smaller block is one
  word copy. With `-n`, one loop writes "N:" and the record for each line. It
  increments the stored digits in place, so there is no per-record call into
  emit, put or the formatter.
- **Skipping in the line scan:** `Dfa.match_lines` skips over the start state
  eight bytes at a time (see
  [Line scanning](extended-regex.md#line-scanning)). This applies when no
  ASCII byte other than LF leaves the start state except at most three values
  or a range of at most 48. It counts LFs on the way with the has-zero-byte
  test and a multiply.

Best of three in ms, before (the output-area build above) / after / GNU:

| Pattern | `-v -n` | `-v` | `-c` |
| --- | --- | --- | --- |
| `[0-9]+$` | 746 / 375 / 175 | 1168 / 205 / 201 | 430 / 173 / 44 |
| `the` | 424 / 360 / 173 | 357 / 231 / 137 | 212 / 202 / 58 |
| `fn main` | 389 / 289 / 216 | 329 / 128 / 121 | 116 / 119 / 33 |
| `\bResult<` | 356 / 270 / 153 | 382 / 136 / 165 | 109 / 104 / 17 |

The `-v -n` column comes from a run at load 11–14. The `-v` and `-c` columns
come from a run at load 17–19, where a repeat of `-v -n` measured 531 / 532 /
626 / 600 ms against GNU's 196 / 251 / 287 / 298. `-v -n` is 1.3–2.1x GNU at
the lower load. Every row's output is byte-identical to GNU's.

With `--count`, matching records no longer stop the scan. Without a literal,
or after a dense-hit switch, `Dfa.count_lines` counts matches across the whole
region, skips from each match to the next LF, and returns only for an
undecided record. For a pure literal, the region gets one validating line
count, and then only the hits are found, each followed by a jump to its LF.
`-v -c` uses the same counts, as records minus matches. The gain is small.
`the -c` went from 157 to 123 ms at load 12–14 (GNU 53). The rest of the
time is `core::search::find` per hit and the DFA byte loop, not line
splitting: `[0-9]+$` stays at 145 ms (GNU 39), `\bResult<` at 75 (GNU 15)
and `a.c` at 298 (GNU 70). For `a.c`, the start-state skip stops at every
`a`. Log: `target/claude-work/s3/grep-count-timings.log`; that run was at load
17, so it is noisier.

The word-wise literal search (`find_pair`, see [Literal prefilter](#literal-prefilter))
and the combined gap-and-hit pass cut most of the per-hit cost. Best of three
wall times in ms at load 9 against the build just before them, GNU last; every
output is byte-identical to GNU's (log
`target/claude-work/s3/grep-pair-timings.log`):

| Pattern | `-c` before / after / GNU | `-n` before / after / GNU |
| --- | --- | --- |
| `the` | 127 / 100 / 54 | 229 / 193 / 88 |
| `core::result::Result` | 96 / 57 / 15 | 101 / 62 / 23 |
| `fn main` | 87 / 66 / 30 | 99 / 72 / 37 |
| `\bResult<` | 77 / 63 / 15 | 84 / 105 / 25 |
| `a.c` | 569 / 447 / 100 | 497 / 446 / 102 |
| `zzzz` | 79 / 56 / 9 | 58 / 51 / 16 |

The `\bResult< -n` wall time is noise: its minimum CPU time over five runs
went from 79 to 66 ms. `a.c` is bound by the DFA byte loop (the literal `a`
is on most lines), and `the -n` by its 150,582 hit records.

The no-match scan is now close to the cost of `core::search` itself. A
program that only reads the corpus and calls `core::search::find` in a loop
takes 30 ms for `zzzz` and 100–110 ms for `core::result::Result`; the rest of
text_grep's time is the validating line count. The `core::result::Result`
search is slower because `find` picks its two probe bytes by rank, and here
both are the adjacent `::` at offsets 4 and 5. Every `::` in Rust text then
costs a full compare; S4 is changing that choice. The line scan runs at
about 11 ns per byte. On the 1.3 MB
mixed-script file `target/claude-work/s3/unicode_lines.txt`, compared with
GNU `grep -P`:

| Pattern | Before `-c` | Prefilter build `-c` | Line scan `-c` | GNU `-P -c` |
| --- | ---: | ---: | ---: | ---: |
| `\p{Lu}` | 1110 | 141 | 73 | 9 |
| `\p{L}+ \p{N}` | 1329 | 141 | 73 | 8 |
| `日\p{L}` | 832 | 106 | 84 | 5 |
| `[^\p{L}\s]` | 1583 | 130 | 72 | 8 |

## Files and recursive search

```sh
text-grep [OPTIONS] PATTERN FILE...
text-grep -r [--include GLOB] [--exclude GLOB] [--exclude-dir GLOB] [--gitignore] PATTERN [DIR|FILE...]
```

Operands after the pattern are files, and the output matches GNU grep 3.11
(`grep -E` in a UTF-8 locale) byte for byte. Each file is read whole into
one reused buffer and searched with the same scan as stdin. Records,
`-v`, `-n` and `-c` are as above, except where GNU grep differs:

- Output lines get a `PATH:` prefix when there is more than one operand or a
  directory is walked. A single file operand gets none. `-c` writes
  `PATH:COUNT` for every file searched, including counts of 0.
- An unterminated last record is written with a LF.
- A file with a NUL byte is binary. NUL then also ends records, nothing of
  the file is written, and `text-grep: PATH: binary file matches` goes to
  stderr when a record was selected. Without `-c` the search of that file
  stops at the first selected record.
- A file with invalid UTF-8 and no NUL is searched record by record. A
  record with encoding errors matches when one of its valid pieces does,
  each piece being searched as a record of its own. Selected records with
  errors are counted but not written, and they get the same stderr line at
  the end of the file. Valid selected records are written as usual. Next to
  an encoding error the two programs differ: GNU grep treats the bad byte as
  a word character that nothing matches, so `^` and `$` do not hold beside
  it and `\b` does not either. text_grep's pieces start and end there, so
  `^x` matches `\xffx` in text_grep and not in GNU grep. This follows the
  same rule as `\b` and `\w` in [`ext::regex`](extended-regex.md), which use
  ASCII word characters (GNU grep's `beta\b` does not match `betaé`, and
  text_grep's does).
- A file is binary when it contains a NUL anywhere. GNU grep decides this
  per 96 KiB read buffer, so for a NUL after the first buffer it writes the
  lines of the earlier buffers and text_grep writes none.
- `-v` with an empty pattern exits 1 without reading anything.
- A directory operand without `-r` is reported as `is-a-directory` and the
  search goes on.

With `-r` and no operand the walk starts at `.` and names are shown without
`./`. The walk goes depth first, in the order the filesystem returns the
entries, as GNU grep's `fts` walk does, so the output order is the same.
Symbolic links and special files below the starting point are skipped, as
in GNU grep's `-r`; symbolic links named on the command line are followed.

`--include`, `--exclude` and `--exclude-dir` match with
[`ext::fnmatch`](extended-fnmatch.md) and flags 0. In the walk they apply to
the base name. For command-line operands a glob matches the whole operand or
the part after any `/`. For files the last matching `--include` or
`--exclude` decides. A file that matches none is skipped when the first of
these options is an `--include`. `--exclude-dir` never applies to the
implicit `.`. These are GNU grep's rules.

`--gitignore` is not a GNU option. It reads the `.gitignore` file of each
directory as the walk enters it and applies [git's rules](extended-gitignore.md):
deeper files and later lines win, ignored directories are not entered, and
`.git` directories are skipped. Only files inside the walked tree are read,
not `.git/info/exclude`, the global excludes file or `.gitignore` files
above the starting directory. A `.gitignore` that cannot be read is
reported like any unreadable file, and none of its rules apply.

#### How a file is scanned

A pattern with a required literal that has no NUL, CR or LF, in a file in
which no record can exceed `--max-line` or reach the work bound, takes the
literal path. That is every literal-bearing pattern on ordinary files. The
path never splits the file into records. It looks only at the records that
hold the literal, as GNU grep does:

1. The literal is searched eight starts per word. The search tests the
   literal's rarest byte (by `core::search::rank`) in each word, and for a
   common rarest byte (a frequent letter) both probe bytes at once, so
   `the` does not stop at every `h`. The same word tests also look for NUL.
2. Around a hit, one backward and one forward word scan find the record's
   LF bounds. They also note any byte >= 128 and stop at a NUL.
3. Only that record is checked for UTF-8, and only when it is not all
   ASCII. A record that is the literal alone (`the`, `fn main`) is then
   selected without the matcher; otherwise the lazy DFA decides.
4. With `-n`, the LFs between hits are counted eight bytes per step. With
   `-v`, the records between hits are the selected ones. They are counted,
   or checked and written, a region at a time.
5. The search then goes on after the record.

A NUL makes the file binary, but the file was read optimistically, so the
first NUL can show up after records were selected. The file's output stays
in the output area until then. Before a record could make the area flush,
the rest of the file is checked for NUL first. On a NUL the file's output,
counts and line number are dropped, and the file is searched again as a
binary file. `-v` checks the whole file for NUL up front, since it writes
most of it. A file without the literal is not looked at further.

Other patterns (no required literal, as for `TODO|FIXME`, or a literal with
a line break) still validate the whole file and run the stdin record scan,
and are slower. On the repository, `TODO|FIXME` took 5–12x GNU grep's wall
time under load.

Two library changes also made the walk cheaper:
- `std::directory::decode_entry` reads the dirent fields by direct
  indexing, not through `Option` per byte.
- `core::path::from_view` and `std::file_ops`'s path staging check bytes
  directly too.

The walk over 14,200 entries went from about 0.09 s to 0.03 s user. Reading
a file no longer zero-fills the buffer. The buffer is used through its
capacity and, when it grows, copies only the bytes read so far.

Failures reading one file, opening it or reading a directory are reported
with the path, for example `text-grep: src/a.c: io-failure stage=input
byte=0`, and the search goes on; the exit status is then 2. An allocation
failure (status 4) or an output failure (status 3) ends the whole search.

### Comparison with GNU grep

`tests/fixtures/extended/text_grep_recursive/compare.py` runs both programs
and requires the same stdout bytes, exit status and stderr lines (without
the program name, so `PATH: binary file matches` lines must agree too).

```sh
W=target/claude-work/s3
python3 -I tests/fixtures/extended/text_grep_recursive/compare.py "$W/text_grep" tree . --exclude-dir target
python3 -I tests/fixtures/extended/text_grep_recursive/compare.py "$W/text_grep" generated --count 400 --seed N
```

`tree` searches the repository (12,654 files, 273 MB without `target/`) for
6 patterns under 6 option sets: plain, `-n`, `-c`, `-v -c`,
`--include='*.md' -n` and `--exclude-dir=tests --exclude='*.rs' -c`. All 36
runs were identical. `generated` builds random trees with nested
directories, symbolic links (to `.`, `..`, files and missing targets), NUL,
Latin-1 and CRLF files, file names with spaces, and `.gitignore` files. It
runs `-r` under 12 option sets mixing `-n`, `-c`, `-v`, repeated
`--include`/`--exclude`, a `--exclude` that overrides an `--include`, and
`--exclude-dir`, with patterns including the empty one. A quarter of the
files are long (100–900 lines), with invalid bytes and NULs placed anywhere
in them. Many lines are selected, so the output area fills in the middle of
a file, and the optimistic NUL handling above has to drop output and start
the file again. Seeds 20261101, 1 and 2 gave 400/400 each. The same command
checks `--gitignore` against git itself (see
[.gitignore rules](extended-gitignore.md#verification)); it agreed in
242/242, 217/217 and 246/246 cases. Log:
`target/claude-work/s3/text-grep-speed-recursive-receipt.log` (before the
literal path: `text-grep-recursive-receipt.log`).

Timings on the repository tree with `--exclude-dir=target` and output to a
file (GNU grep stops at the first match when stdout is `/dev/null`). Each is
the best user+sys of five interleaved runs, on the laptop at load average
6–15 (`target/claude-work/s3/bench_r.sh`):

| Search | text_grep before | text_grep now | GNU grep | now / GNU |
| --- | ---: | ---: | ---: | ---: |
| `-r the` | 0.90 s | 0.53 s | 0.37 s | 1.42 |
| `-r -n the` | | 0.59 s | 0.40 s | 1.47 |
| `-r -c the` | | 0.46 s | 0.33 s | 1.39 |
| `-r -c zzqqxx` (absent) | 0.31 s | 0.32 s | 0.17 s | 1.88 |

Wall time for `-r the` was 0.53 s against 0.39 s. System time is lower than
GNU grep's (0.09 s against 0.13 s). Of text_grep's 0.43 s user:
- the walk, opens and reads take about 0.07 s;
- the word search over the 273 MB takes about 0.15 s;
- the hit records (116,000 of them, 29 MB of output) take the rest.

The absent-word search is bound by the word search alone. GNU grep's
`memchr` is vectorized, and this loop moves one 8-byte word per step. Log:
`target/claude-work/s3/grep-speed-timings.log`. The earlier timings, under
heavy load, are in `grep-recursive-timings.log`.

## Exit status and failures

| Status | Meaning |
| ---: | --- |
| 0 | At least one record was selected, or help was written. |
| 1 | No record was selected. Count mode still writes `0\n`. |
| 2 | Invalid arguments, invalid/unsupported regex, malformed UTF-8, or resource/work limit. |
| 3 | Native read/write failure, including failure to write a diagnostic. |
| 4 | Allocation failure. |

Errors attempt one allocation-free stderr diagnostic, for example:

```text
text-grep: invalid-utf8 stage=input line=2 byte=3
text-grep: invalid-regex stage=pattern argument=0 byte=0
```

Input byte positions start at zero within the original record. Pattern byte
positions are relative to the pattern. Argument numbers start at zero after the
executable. A line limit points to the first excess byte. A native read failure
points to the current buffered byte count; a provider work/resource failure may
have no byte position. Stages distinguish arguments, pattern compilation, input,
search, and output. Invalid options and pattern compilation fail before input
is read.

The program stops at the first error and releases every current owner. Earlier
selected records remain on stdout if a later record fails. The current record is
validated and matched before it is written. Native writes can transfer a prefix
before failure, including a line-number prefix, so an I/O error can leave a
partial record. Count mode emits no count when input or search fails. `EINTR` is
retried, short writes advance by the transferred count, and zero-progress writes
fail. A failed stderr diagnostic changes the final status to 3.

## Verification

`tests/extended_text_grep_execution.rs` compiles the real sample through GPU code
generation and executes its native x86_64 Linux output. It compares generated
Unicode, NUL, CRLF, empty, and unterminated records with independent Python `re`
searches over the common grammar, using ASCII shorthand semantics. Python is
used only as a test oracle. The suite checks inversion, counting, numbering,
argument and provider limits, unsupported expressions, malformed UTF-8 across
read boundaries, and output retained before a later error.

Linux fault tests trace a multi-record search, deny every observed allocation,
and reconcile successful mappings with unmaps. Each observed read is tested with
an I/O error and interruption. Each observed stdout write is tested with an I/O
error, interruption, zero progress, and a short/faked byte transfer. The suite
also checks `/dev/full` and a failed diagnostic write. It requires `python3` and
`strace`.

`tests/fixtures/extended/text_grep_faults/driver.py` runs the same matrix
without ptrace. `faultinj.c` in that directory uses seccomp user notification
to count `mmap`, `munmap`, `read` and `write` calls and to fail the N-th one.
At exit it compares `/proc/PID/maps` with the map at the first trapped call, so
an unreleased mapping is a failure. The driver runs the matrix for seven
patterns on `aaé\r\nnope\néa` with `-n`:

| Pattern | Path | mmap = munmap | Allocation failures (status 4) | Read faults | Stdout write faults |
| --- | --- | ---: | ---: | ---: | ---: |
| `^(?<!x)(?:a\|é)+$` | VM (lookbehind) | 43 | 43/43 | 2 × EIO, EINTR | 1 × EIO, 0, EINTR, short |
| `^(?:a\|é)+$` | lazy DFA with anchors | 32 | 32/32 | 2 × EIO, EINTR | 1 × EIO, 0, EINTR, short |
| `(?:a\|é)+` | lazy DFA | 29 | 29/29 | 2 × EIO, EINTR | 1 × EIO, 0, EINTR, short |
| `a*é` | prefilter, DFA on hit records | 29 | 29/29 | 2 × EIO, EINTR | 1 × EIO, 0, EINTR, short |
| `é` | prefilter, literal decides | 28 | 28/28 | 2 × EIO, EINTR | 1 × EIO, 0, EINTR, short |
| `nope` with `-v` | prefilter, numbered gap blocks | 31 | 31/31 | 2 × EIO, EINTR | 1 × EIO, 0, EINTR, short |
| `[nx][o][p][e]` with `-v` | line scan, numbered gap blocks | 34 | 34/34 | 2 × EIO, EINTR | 1 × EIO, 0, EINTR, short |

Two more rows search a tree (`a`, `sub/b`, `ignored` with that input and a
`.gitignore` naming `ignored`) from its parent directory:

| Arguments | mmap = munmap | Allocation failures (status 4) | Read faults | Stdout write faults |
| --- | ---: | ---: | ---: | ---: |
| `-r -n --gitignore é tree` | 39 | 39/39 | 8 × EIO, EINTR | 1 × EIO, 0, EINTR, short |
| `-r -c --include=[ab] a tree` | 38 | 38/38 | 4 × EIO, EINTR | 1 × EIO, 0, EINTR, short |

A failed read there must give status 2 and one `text-grep: tree/...:
io-failure stage=input` line, and stdout may only lose the lines of that
file (or, when the `.gitignore` read fails, gain those of `ignored`). The
first version of these rows found 16 failures: an allocation failure while
collecting file operands or globs was reported as `invalid-arguments`
(status 2), and every early return after argument parsing (a regex that
failed to compile, for one) left the operand and glob lists mapped. Both
lists are now owned by `process` and released on every path, and a failed
push is status 4. A directory buffer that cannot be allocated is status 4
too, not an unreadable directory.

All 402 runs, including `/dev/full` and the failed diagnostic, give the
documented status, diagnostic and stdout prefix, and leave the map unchanged.
The DFA path maps fewer regions because it never creates per-record VM
scratch. The single stdout write is the buffered output. The DFA's
partial-state tables and `required_literal`'s three temporary vectors add
mappings. The fixed output area saves two compared with the growing
buffer it replaced. Before the fix above,
failures 8 through 21 of the DFA pattern were silently absorbed: the search
fell back to the VM and exited 0. Log:
`target/claude-work/s3/text-grep-faults-speed-receipt.log` (counts unchanged by the literal path; the stdin
rows alone: `text-grep-faults-pair-receipt.log`). The `(?:a|é)+` row goes through the line scan.

```sh
W=target/claude-work/s3
cc -O2 -o "$W/faultinj" tests/fixtures/extended/text_grep_faults/faultinj.c
target/claude-work/bin/lcc -o "$W/text_grep" --stdlib-root stdlib \
  --source-root extended sample_programs/library/text_grep.lani
python3 -I tests/fixtures/extended/text_grep_faults/driver.py "$W/faultinj" "$W/text_grep"
```

A large workload reuses one compiled expression across 12000 records. One local
run on 2026-10-23 processed 436000 input bytes and emitted 168000 selected bytes
in 1464 ms. The timer includes process/file setup and I/O; it excludes compilation
and oracle generation. This is an observation, not a throughput guarantee.
Execution evidence is for native x86_64 Linux. GPU compilation does not establish
execution as a GPU kernel or support for other native targets.
