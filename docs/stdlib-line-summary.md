# Summarize UTF-8 lines

`sample_programs/library/line_summary.lani` reads bounded UTF-8 from stdin and
writes a TSV summary to stdout. It uses the canonical borrowed `Text.lines()`,
`split_ascii_whitespace()` and `scalars()` cursors. Input and line admission
finish before the first output byte. The application passes 102 native process
cases and both standalone examples on Linux x86_64.

## Build and use

From the repository root with the compiler binary built:

```sh
mkdir -p target/stdlib-work
timeout --kill-after=2s 100s flock -w 95 target/stdlib-work/library-gpu.lock \
  target/stdlib-build/debug/laniusc --stdlib-root stdlib --source-root extended \
  --emit x86_64 sample_programs/library/line_summary.lani \
  -o target/stdlib-work/line_summary
printf 'alpha beta\r\n\n\303\251 x\360\237\230\200' | \
  target/stdlib-work/line_summary
```

Expected stdout, with literal tabs between columns and LF after every row:

```text
line	bytes	words	last_word_bytes	last_scalar
1	10	2	4	97
2	0	0	0	-1
3	8	2	5	128512
```

The final input line is `é x😀` without a trailing newline. Its last word has
five UTF-8 bytes, and its last scalar is U+1F600 (decimal 128512).

NUL and non-ASCII whitespace remain word content. A lone CR remains line
content even though it is a word separator:

```sh
printf 'a\000b\302\240c\r' | target/stdlib-work/line_summary
```

Exact expected stdout is
`line\tbytes\twords\tlast_word_bytes\tlast_scalar\n1\t7\t1\t6\t13\n`.
Both examples exited 0 with empty stderr and exact stdout of 83 and 56 bytes,
respectively. The standalone compiler command also passed; receipts are below.

## Output contract

The application accepts no arguments. Even `--help`, `--` and an empty
argument reject before reading stdin. The zero-entry `std::args::snapshot`
does not allocate or copy argument bytes.

The exact 45-byte header is
`line\tbytes\twords\tlast_word_bytes\tlast_scalar\n`.
Every subsequent record has five decimal fields separated by tabs and ends in
LF. There are no signs except the empty-line sentinel `-1`, and no leading
zeros except the number zero itself.

| Field | Meaning |
| --- | --- |
| `line` | One-based line number in source order |
| `bytes` | UTF-8 byte length after removing a line terminator |
| `words` | Number of nonempty words separated by ASCII whitespace |
| `last_word_bytes` | Byte length of the last word, or zero if absent |
| `last_scalar` | Final Unicode scalar value as decimal, or -1 for an empty line |

Lines end at LF or CRLF. Their terminators are excluded; a lone CR, NUL, NBSP
and Unicode line/paragraph separators remain content. Empty input produces
only the header. A final LF produces no extra phantom line, while leading or
repeated line terminators produce empty lines.

Word separators are exactly HT, LF, VT, FF, CR and space. Unicode whitespace
is ordinary word content. The final scalar describes the whole line, including
trailing whitespace; it need not be the final scalar of the last word. These
are Unicode scalar values, not grapheme counts or display widths.

## Bounds and publication

| Resource | Maximum |
| --- | ---: |
| Input bytes | 1,048,576 |
| Lines | 65,536 |
| Stdin read attempts | 16,384 |
| Stdout write attempts across the header and all rows | 131,072 |
| Stderr diagnostic write attempts | 64 |

Interrupted calls spend attempts and retry. EOF reads and the cap probe also
spend read attempts. WouldBlock is an I/O failure; this program does not wait
for readiness or change descriptor blocking mode. Positive short reads and
writes are accepted. A zero-progress or invalid-count output result fails.

`alloc::io::read_to_string` collects the complete input before validating
UTF-8. At exactly the byte cap it performs a real one-byte read: EOF admits the
input; an extra byte is consumed and rejects it. A separate full line-count
pass then admits at most 65,536 lines. Input, UTF-8, allocation and line-limit
failures publish no header or records.

Publication writes the header, then one complete staged row at a time. Output
I/O failure or write-attempt exhaustion can leave a confirmed stdout prefix,
including part of the header or a row. The program neither rolls back nor
restarts that prefix. This is true for status 2 from output call exhaustion as
well as status 3 from output I/O failure. No flush or durability claim is made.

## Ownership and traversal

Signal setup and argument admission precede input. The empty argument owner
is retired before the collector starts. The collector reserves before reads,
using capped geometric growth beginning at 1024 bytes and fixed input scratch.
Even empty input first reserves a 1024-byte buffer before discovering EOF.
Successful UTF-8 validation transfers the existing byte allocation into one
String owner; it does not copy the complete input into another allocation.

The first `lines()` cursor checks the line limit. A fresh cursor then visits
the same immutable backing in source order. For each line, the application
pulls the last word backward, counts the remaining words forward on that same
cursor, and pulls the final scalar backward. No line or word is copied into an
owner. Decimal fields reuse one 64-element stack byte array; the descriptor
adapter provides its usual fixed packed host-I/O scratch.

The String remains live through publication. Every ordinary collection,
admission or output failure releases its input or partial-input owner before
attempting a diagnostic. Success releases the input after all cursor uses end.
Stdin, stdout and stderr are borrowed descriptors and are never closed here.
These are explicit manual lifetimes, not automatic borrow checking or trap
recovery.

## Failures

| Status | Meaning |
| --- | --- |
| 0 | Complete summary written |
| 2 | Unsupported arguments, invalid UTF-8, byte/line limit or read/write call limit |
| 3 | Signal setup, argument capture, input/output I/O or diagnostic failure |
| 4 | Allocation failure |

If SIGPIPE-ignore setup fails, the program returns 3 before argument capture,
input or any output. It attempts no diagnostic, because stderr might itself
be a closed pipe and the protective signal disposition was not established.
Every subsequent failure attempts one fixed LF-terminated diagnostic:

```text
line_summary: arguments are not supported
line_summary: could not read arguments
line_summary: input is not valid UTF-8
line_summary: input exceeds 1048576 bytes
line_summary: input exceeds 65536 lines
line_summary: read attempt limit exceeded
line_summary: write attempt limit exceeded
line_summary: allocation failed
line_summary: input operation failed
line_summary: output operation failed
```

Diagnostics contain no input bytes. The primary status is returned only if
the diagnostic completes. A diagnostic write failure or diagnostic call-limit
exhaustion returns 3, overriding an earlier status 2 or 4; its stderr prefix
can remain visible. Successful SIGPIPE-ignore setup lets broken-pipe writes
return an I/O error.

## Acceptance and supported targets

The tested target is native Linux x86_64, compiled through the GPU compiler
with executable ELF and x86 jump validation. The resulting program runs on the
CPU. Stdin, stdout, signal handling and allocation require the existing host
runtime. GPU device execution, other targets and formal proof remain outside
this receipt.

The four focused gates passed against source SHA-256
`ebbf42590aae82d90ed8d4c58d2b36d64c736f082509a32f934d4a7f4b64d5a2`:

| Gate | Native process cases | Test time | Log under `target/stdlib-work/` |
| --- | ---: | ---: | --- |
| Independent complete TSV model | 44 | 7.73 s | `text-line-summary-model.log` |
| Argument and UTF-8 admission | 20 | 7.27 s | `text-line-summary-admission.log` |
| Byte probes and line limits | 8 | 11.84 s | `text-line-summary-limits.log` |
| Allocation, I/O and attempt failures | 30 | 17.11 s | `text-line-summary-io-revised.log` |
| **Total** | **102** | | |

The model checks exact bytes for LF/CRLF, lone CR, NUL, Unicode whitespace,
all UTF-8 widths, combining scalars, noncharacters, chunk boundaries and
seeded records. Admission cases reject every tested argument and malformed
UTF-8 without publishing a header. Limit cases observe the actual one-byte
EOF/extra-byte probes after exactly 1 MiB and compare complete output at the
65,536-line cap.

The I/O gate reaches all 11 input-growth allocation sites from its measured
baseline. Its syscall ledger checks exact full-width allocation releases,
EOF before stdout, one live input mapping during output, and retirement before
diagnostics. It also covers reached read/write errors, Interrupted retries,
zero-progress writes, diagnostic overrides, a real closed stdout pipe,
directory-backed stdin and silent signal-setup failure with closed stderr.
The argument snapshot has no allocation site to inject.

The two payload-attempt tests use continuous Interrupted injection because
the installed `strace` rejects the required finite-range endpoint. They
observe exactly 131,072 stdout attempts followed by 64 diagnostic attempts.
Every diagnostic request contains the complete 43-byte write-limit message;
the final status is 3 because those diagnostic writes also fail. One case
preserves the actual 45-byte header written before injection begins. These
tests establish bounded output exhaustion and confirmed-prefix behavior;
they do not independently exercise status 2 after a successful write-limit
diagnostic. The initial I/O attempt stopped on the unsupported trace syntax;
the harness was corrected without changing application source.

The exact standalone build command exited 0 with no output, recorded in
`target/stdlib-work/text-line-summary-cli.log`. Both guide examples then
matched their literal 83-byte and 56-byte outputs, exited 0 and left stderr
empty, recorded in `target/stdlib-work/text-line-summary-examples.log`.
These overlapping smoke checks add no distinct cases to the 102-case corpus.
