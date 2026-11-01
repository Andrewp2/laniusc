# UTF-8 text search

`sample_programs/library/text_grep.lani` filters stdin with one compiled
[regular expression](extended-regex.md). It composes `ext::regex`, `ext::cli`,
`std::args`, `std::stream`, checked `core::text`, `core::fmt`, and an owned,
reusable `alloc::vec` input buffer. Production search and I/O run in Lanius.

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
| `--help`, `-h` | | Write usage and exit. |

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
form one region. `core::search::find` looks for the literal across the whole
region, and only the records containing it go to the matcher. One pass over
each gap between those records checks UTF-8 and counts its LFs, eight bytes per
step, so line numbers and errors stay exact. When the pattern is that literal
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
(`text-grep-count-receipt.log`), tiny build included. A build with a 3-state DFA
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

All 291 runs, including `/dev/full` and the failed diagnostic, give the
documented status, diagnostic and stdout prefix, and leave the map unchanged.
The DFA path maps fewer regions because it never creates per-record VM
scratch. The single stdout write is the buffered output. The DFA's
partial-state tables and `required_literal`'s three temporary vectors add
mappings. The fixed output area saves two compared with the growing
buffer it replaced. Before the fix above,
failures 8 through 21 of the DFA pattern were silently absorbed: the search
fell back to the VM and exited 0. Log:
`target/claude-work/s3/text-grep-faults-count-receipt.log`. The `(?:a|é)+` row goes through the line scan.

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
