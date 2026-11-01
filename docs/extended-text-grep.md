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
greedy and lazy repetition, anchors, and Unicode properties. Lookaround,
backreferences, possessive quantifiers, and unsupported escapes fail explicitly;
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
buffer and one compiled regex. An assertion-free pattern also gets one
capture-free [lazy DFA](extended-regex.md#capture-free-dfa-matching), which
answers each record exactly as the VM would. VM scratch is created and released
only for a search the DFA cannot decide, or for patterns with assertions. On a
915,606-byte, 25,000-line corpus, `-c` searches for `zzz`, `abs`, `max\(`,
`(min|max)\([^)]*,`, `9{3,}` and `[0-9]+ *\*\* *[0-9]+` dropped from
3.0–3.8 s to 0.15–0.23 s each, with identical counts and `-n` output. The
assertion pattern `^ *1` still takes about 3 s on the VM. These are wall times
on a loaded laptop. A failed DFA cache allocation is an allocation failure
(status 4, `stage=pattern`); only a pattern with assertions uses the VM
instead. Spare line capacity and regex scratch mean these limits do not specify a
total memory limit. The input is read in 1024-byte chunks; a UTF-8 sequence may
cross a read boundary safely because validation happens after record assembly.

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
an unreleased mapping is a failure. The driver runs the matrix for two
patterns on `aaé\r\nnope\néa` with `-n`:

| Pattern | Path | mmap = munmap | Allocation failures (status 4) | Read faults | Stdout write faults |
| --- | --- | ---: | ---: | ---: | ---: |
| `^(?:a\|é)+$` | VM | 39 | 39/39 | 2 × EIO, EINTR | 5 × EIO, 0, EINTR, short |
| `(?:a\|é)+` | lazy DFA | 23 | 23/23 | 2 × EIO, EINTR | 5 × EIO, 0, EINTR, short |

All 114 runs, including `/dev/full` and the failed diagnostic, give the
documented status, diagnostic and stdout prefix, and leave the map unchanged.
The DFA path maps fewer regions because it never creates per-record VM
scratch. Before the fix above, failures 8 through 21 of the DFA pattern were
silently absorbed: the search fell back to the VM and exited 0. Log:
`target/claude-work/s3/text-grep-faults-receipt.log`.

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
