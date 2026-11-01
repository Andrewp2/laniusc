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
Selected records collect in one output buffer. It is written when it holds
64 KiB, at EOF, and before any error is reported. If that last write fails,
the status is 3 at `stage=output`, in place of the earlier error.

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
`--max-line` and small `--max-work`. Seeds 20261031, 1 and 2 gave 1500/1500
identical runs (log `target/claude-work/s3/text-grep-scan-receipt.log`).

The table compares GNU grep 3.11 (`-E`, `en_US.UTF-8`) with text_grep on
S4's 48,770,754-byte, 814,590-line Rust-heavy corpus. Times are best of three
wall times in ms, with stdout written to a file. Every row's output (`-c`
count, or the `-n` listing) is byte-identical to GNU's. "Before" is the build
from the assertion commit above, which used 1024-byte reads, a matcher run
on every record and one write per record. The laptop had other work running
(load 10–19). Logs: `target/claude-work/s3/grep-prefilter-timings.log` and
`grep-unicode-timings.log`.

| Pattern | Before `-c` | `-c` | `-n` | GNU `-c` | GNU `-n` |
| --- | ---: | ---: | ---: | ---: | ---: |
| `zzzz` (no match) | 5176 | 68 | 69 | 11 | 18 |
| `core::result::Result` (8,682 lines) | 5035 | 140 | 165 | 17 | 31 |
| `fn main` | 5024 | 109 | 134 | 32 | 47 |
| `the` | 5552 | 272 | 473 | 69 | 100 |
| `^\s*//` | 4835 | 114 | 142 | 30 | 42 |
| `\bResult<` | 5066 | 110 | 131 | 16 | 28 |
| `fn [a-z_]+_main\(` | 4717 | 85 | 84 | 15 | 23 |
| `[0-9]+$` (no required literal) | | 1583 | 1690 | 44 | 57 |

The no-match scan is now close to the cost of `core::search` itself. A
program that only reads the corpus and calls `core::search::find` in a loop
takes 30 ms for `zzzz` and 100–110 ms for `core::result::Result`; the rest of
text_grep's time is the validating line count. The `core::result::Result`
search is slower because `find` picks its two probe bytes by rank, and here
both are the adjacent `::` at offsets 4 and 5. Every `::` in Rust text then
costs a full compare. Patterns with no required literal, such as `[0-9]+$`,
still run the DFA on every record, at about 32 ns per byte. On the 1.3 MB
mixed-script file `target/claude-work/s3/unicode_lines.txt`, compared with
GNU `grep -P`:

| Pattern | Before `-c` | `-c` | `-n` | GNU `-P -c` |
| --- | ---: | ---: | ---: | ---: |
| `\p{Lu}` | 1110 | 147 | 142 | 9 |
| `\p{L}+ \p{N}` | 1329 | 153 | 143 | 8 |
| `日\p{L}` | 832 | 145 | 166 | 5 |
| `[^\p{L}\s]` | 1583 | 197 | 203 | 13 |

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
an unreleased mapping is a failure. The driver runs the matrix for three
patterns on `aaé\r\nnope\néa` with `-n`:

| Pattern | Path | mmap = munmap | Allocation failures (status 4) | Read faults | Stdout write faults |
| --- | --- | ---: | ---: | ---: | ---: |
| `^(?<!x)(?:a\|é)+$` | VM (lookbehind) | 45 | 45/45 | 2 × EIO, EINTR | 1 × EIO, 0, EINTR, short |
| `^(?:a\|é)+$` | lazy DFA with anchors | 34 | 34/34 | 2 × EIO, EINTR | 1 × EIO, 0, EINTR, short |
| `(?:a\|é)+` | lazy DFA | 31 | 31/31 | 2 × EIO, EINTR | 1 × EIO, 0, EINTR, short |
| `a*é` | prefilter, DFA on hit records | 31 | 31/31 | 2 × EIO, EINTR | 1 × EIO, 0, EINTR, short |
| `é` | prefilter, literal decides | 30 | 30/30 | 2 × EIO, EINTR | 1 × EIO, 0, EINTR, short |

All 218 runs, including `/dev/full` and the failed diagnostic, give the
documented status, diagnostic and stdout prefix, and leave the map unchanged.
The DFA path maps fewer regions because it never creates per-record VM
scratch. The single stdout write is the buffered output. There are more
mappings than before because of the output buffer, the DFA's partial-state
tables and `required_literal`'s three temporary vectors. Before the fix above,
failures 8 through 21 of the DFA pattern were silently absorbed: the search
fell back to the VM and exited 0. Log:
`target/claude-work/s3/text-grep-faults-unicode-receipt.log`.

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
