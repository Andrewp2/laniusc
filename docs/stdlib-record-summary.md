# Summarize byte records

`sample_programs/library/record_summary.lani` reads bounded binary stdin and
writes a TSV summary. It uses the generic `SplitInclusive`, `Split` and
`ChunkBy` cursors over one owned byte buffer. Input and record-count admission
finish before the first output byte. The application passes 94 native process
cases and both standalone examples on Linux x86_64.

## Build and use

From the repository root with the compiler binary built:

```sh
mkdir -p target/stdlib-work
timeout --kill-after=2s 100s flock -w 95 target/stdlib-work/library-gpu.lock \
  target/stdlib-build/debug/laniusc --stdlib-root stdlib --source-root extended \
  --emit x86_64 sample_programs/library/record_summary.lani \
  -o target/stdlib-work/record_summary
printf 'aa,,bbb\n\nx,x,\r\n' | target/stdlib-work/record_summary
```

Expected stdout, with literal tabs between columns and LF after every row:

```text
record	bytes	fields	empty_fields	longest_run
1	7	3	1	3
2	0	1	1	0
3	5	3	0	1
```

The final record retains CR as a one-byte field. Binary data and quotes are
handled by the same delimiter rules:

```sh
printf '\000\000,\377\377\377,,"q,q"' | target/stdlib-work/record_summary
```

Exact expected stdout is
`record\tbytes\tfields\tempty_fields\tlongest_run\n1\t13\t5\t1\t3\n`.
The comma between quotes still separates fields. Both examples exited 0 with
empty stderr and exact stdout of 75 and 56 bytes, respectively. The standalone
build command also passed; receipts are below.

## Record and output contract

No arguments are accepted. Even `--help`, `--` and an empty argument reject
before any input read. The zero-entry `std::args::snapshot` needs no heap
allocation or argument-byte copy.

Records end at LF. Inclusive splitting retains that LF in the selected view,
then the application removes only its final byte. A CR before LF remains
record content. Empty stdin yields no records; a terminal LF adds no phantom
record. Leading and repeated LF bytes produce empty records.

Every comma separates fields, including commas inside quotes. Leading,
adjacent and final commas preserve empty fields. An empty record contains one
empty field. NUL, CR, quotes and bytes outside UTF-8 are ordinary content; no
escaping, text decoding or normalization is performed. This delimiter report
does not interpret quoted CSV.

The exact 45-byte header is
`record\tbytes\tfields\tempty_fields\tlongest_run\n`.
Each record produces five unsigned decimal values without leading zeros,
separated by tabs and terminated by LF:

| Field | Meaning |
| --- | --- |
| `record` | One-based record number in input order |
| `bytes` | Content byte length, excluding only a final LF |
| `fields` | Comma-delimited field count, including empty fields |
| `empty_fields` | Number of fields with zero bytes |
| `longest_run` | Longest run of identical adjacent content bytes, or zero for empty content |

Run length covers the entire content, including commas, quotes and CR. It is
not restricted to individual fields. Runs compare byte values directly, so
multibyte text receives no special treatment.

## Bounds and publication

| Resource | Maximum |
| --- | ---: |
| Input bytes | 1,048,576 |
| Records | 65,536 |
| Stdin read attempts | 16,384 |
| Stdout write attempts across the header and every row | 131,072 |
| Stderr diagnostic write attempts | 64 |

`alloc::io::read_to_end` collects input under the byte and read-call limits.
At exactly the byte cap it performs a real one-byte read: EOF admits input;
an extra byte is consumed and rejects it. The application then completes a
record-count pass before writing the header. Byte, record, read-limit and
allocation failures publish no records or header.

Interrupted calls consume attempts and retry. EOF and probe reads also
consume attempts. Positive short reads and writes are accepted; zero-progress
or invalid-count writes fail. WouldBlock is an I/O failure. The application
does not wait for readiness or change descriptor blocking mode.

Each output row is staged in fixed scratch before writing it. Output failure
or write-attempt exhaustion can leave a confirmed stdout prefix, including a
partial header or row. The application does not roll back or restart output.
The write-attempt counter spans the header and all rows; it does not reset at
record boundaries. No flush or durability guarantee is made.

## Cursors, effects and ownership

After signal setup, argument admission finishes and the empty argument owner
is destroyed. The input collector reserves before reading, with capped
geometric growth beginning at 1024 bytes and fixed input scratch. Even empty
input first reserves 1024 bytes before observing EOF. The result is one
`Vec<u8>` owner.

`SplitInclusive<u8,ByteEquals>` first counts LF-delimited records. A fresh
cursor visits the same unchanged backing for output. Each selected record
becomes a subview excluding only its final LF. `Split<u8,ByteEquals>` counts
comma fields and empty fields; `ChunkBy<u8,EqualBytes>` finds the longest
equal-byte run. All three factories check their logical view bounds. Selected
views retain the original storage and offsets.

The two callbacks only compare byte values. They neither mutate backing nor
their own context, allocate, perform I/O or reenter a cursor. Their stack
storage remains live through every cursor pull. Record and field views are
borrowed; the application creates no owned copy or cached record array.
Decimal fields reuse one 64-element stack byte array, and the stream adapter
uses its usual fixed packed host-I/O scratch.

The input owner remains live through output. Every ordinary collection,
admission or publication failure destroys its input or partial-input owner
before attempting a diagnostic. Success destroys the input after all views
and cursors are finished. Stdin, stdout and stderr are borrowed descriptors
and are never closed here. These are manual lifetime rules, not automatic
borrow checking or trap recovery.

## Failures

| Status | Meaning |
| --- | --- |
| 0 | Complete report written |
| 2 | Unsupported arguments, byte/record limit or read/write call limit |
| 3 | Signal setup, argument capture, input/output I/O or diagnostic failure |
| 4 | Allocation failure |

Failed SIGPIPE-ignore setup returns 3 before argument capture, input or
output. It attempts no diagnostic because stderr might itself be a closed
pipe without a protective signal disposition. Every later failure attempts
one fixed LF-terminated diagnostic:

```text
record_summary: arguments are not supported
record_summary: could not read arguments
record_summary: input exceeds 1048576 bytes
record_summary: input exceeds 65536 records
record_summary: read attempt limit exceeded
record_summary: write attempt limit exceeded
record_summary: allocation failed
record_summary: input operation failed
record_summary: output operation failed
```

Diagnostics contain no input bytes. Diagnostic failure or its own call-limit
exhaustion overrides the primary status with 3 and may leave a stderr prefix.
In particular, output call exhaustion returns 2 only when its diagnostic
completes; the already-written stdout prefix remains in either case.

## Acceptance and supported targets

The tested target is native Linux x86_64, compiled through the GPU compiler
with executable ELF and x86 jump validation. The resulting program runs on
the CPU and requires the existing allocation, stream and signal host
services. GPU device execution, other targets and formal proof remain outside
these receipts.

All four application gates pass against source SHA-256
`c9f83694dc11e4314eacd9349465925331cbcad4d77b5a516bdde9dadf1bd2d3`:

| Gate | Native cases | Test time | Rust build | Log under `target/stdlib-work/` |
| --- | ---: | ---: | ---: | --- |
| Independent binary TSV model | 48 | 7.44 s | 1.77 s | `slice-record-summary-model.log` |
| Argument admission | 8 | 7.23 s | 0.18 s | `slice-record-summary-admission.log` |
| Byte probes and record limits | 8 | 13.80 s | 0.19 s | `slice-record-summary-limits.log` |
| Allocation, I/O and attempt failures | 30 | 18.49 s | 0.20 s | `slice-record-summary-io.log` |
| **Total** | **94** | | | |

The independent model compares complete output for empty and repeated
records, CRLF retaining CR, all 256 byte values, invalid UTF-8, NUL, quotes,
empty fields, equal-byte runs, read boundaries and 16 seeded binary inputs.
Admission cases observe no input read or allocation for rejected arguments.
Limit cases observe the actual one-byte EOF/extra-byte probes after 1 MiB,
compare every output row at the 65,536-record cap, and confirm full input
collection before record-limit rejection.

The I/O gate reaches all 11 input-growth allocation denials selected from its
measured baseline. The ledger observes `read`, `write`, `mmap`, `munmap`,
`mremap`, `brk`, `openat`, `close` and `rt_sigaction`; it does not observe every
possible host effect. It checks full-width allocation addresses and exact
release extents, EOF before stdout, one live input mapping during output,
and complete retirement before diagnostics. Reached read/write failures,
Interrupted retries, zero-progress output, diagnostic overrides, real closed
stdout and directory stdin are also covered. Silent signal-setup failure is
checked with both ordinary and closed-pipe stderr. The argument snapshot has
no allocation site to inject.

Installed `strace` cannot express the required finite payload-write fault
range. The two payload-budget tests use continuous Interrupted injection and
observe exactly 131,072 stdout attempts followed by 64 failed diagnostic
attempts. Each diagnostic request contains the complete 45-byte write-limit
message. The final status is 3 because diagnostics also fail; one case
preserves the real 45-byte header written before injection starts. These
tests establish bounded attempts and confirmed-prefix behavior, but do not
independently execute status 2 after a successful output-limit diagnostic.
The read-attempt limit does execute status 2 with a successful diagnostic.

Observed diagnostics are checked byte for byte. Argument-capture host-read
failure has no injected execution case. Synthetic zero-write results test
rejection only; they are not evidence of actual transferred bytes. Earlier
or partial attempts and host-only controls add no native cases to the total.

The exact standalone compiler command exited 0 with no output, recorded in
`target/stdlib-work/slice-record-summary-build.log`. Both literal guide
examples then matched their 75-byte and 56-byte outputs, exited 0 and left
stderr empty, recorded in
`target/stdlib-work/slice-record-summary-examples.log`. These overlapping
smoke checks add no distinct cases to the 94-case corpus.
