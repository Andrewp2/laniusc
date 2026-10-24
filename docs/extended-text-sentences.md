# text-sentences

`sample_programs/library/text_sentences.lani` segments UTF-8 stdin using the
complete Unicode 17 default sentence rules from
[`ext::unicode_sentences`](extended-unicode-sentences.md). The program combines
`std::args`, `ext::cli`, `alloc::io`, `alloc::vec`, `core::text`, `core::fmt`,
`core::io` and `std::stream`. Production behavior is Lanius throughout.

```sh
target/stdlib-build/debug/laniusc --stdlib-root stdlib --source-root extended \
  sample_programs/library/text_sentences.lani -o /tmp/text-sentences
printf 'Hello. World!\n' | /tmp/text-sentences
printf 'Hello. World!\n' | /tmp/text-sentences --format frames
```

The default `--format csv` emits `start,end,text` with input-relative byte
positions and a quoted UTF-8 text field. Every text quote is doubled; commas,
newlines, carriage returns, tabs and NUL remain original bytes inside the
quoted field. A sentence can occupy several physical output lines. Parse this
as CSV rather than splitting on newlines. No whitespace or punctuation is
trimmed.

`--format frames` emits one little-endian `u32` byte length followed by exactly
that many original UTF-8 bytes per sentence. There is no header or empty frame.
Concatenating frame payloads reconstructs stdin exactly, including embedded
newlines and NUL. Empty input yields only the CSV header or zero frame bytes.
The default boundary rules do not perform language-specific abbreviation
recognition; the library guide describes this distinction.

## Limits and errors

| Option | Default | Maximum accepted |
| --- | ---: | ---: |
| `--max-input-bytes` | 4,194,304 | 67,108,864 |
| `--max-output-bytes` | 16,777,216 | 67,108,864 |
| `--max-segments` | 1,048,576 | 16,777,216 |
| `--max-work` | 33,554,432 | 1,000,000,000 |

All limits accept zero. Duplicate options, operands, unknown options, malformed
numbers and values above these hard ceilings are argument errors. `--help` or
`-h` must appear alone. Output and segment limits apply to the complete result;
input below its limit does not guarantee that its formatted output fits.

The program reads bounded bytes, reserves `7 * input_bytes` work units,
validates UTF-8, measures exact output size using one cursor scan, allocates
that exact output size, then scans again to format. Work units cover at most
one UTF-8 scalar validation and two sentence scans with at most three scalar
classifications each; they are conservative abstract units, not machine
instruction counts. UTF-8 validation uses at most one unit per input byte.
CSV quote scans, numeric formatting, input/output copies and argument parsing
are outside this classification budget and are separately bounded by the
input, output, segment and argument limits. The program performs O(input plus
output bytes plus segment count) work and uses bounded owned input/output
buffers with O(1) segmentation state.

The entire result is staged before stdout is written. Invalid UTF-8, exhausted
limits and allocation failures produce no stdout, including failures found
after many valid sentences. A real output I/O error can leave a written prefix.
Interrupted reads/writes and positive short writes are handled through the
stream and `core::io` contracts. Input and output owners are released on success
and every failure path. The CLI explicitly ignores SIGPIPE before copying
arguments or allocating input/output, so closed stdout or stderr pipes return
through checked I/O and cleanup. Failure to install that process-wide signal
disposition exits with status 3 before allocation.

Exit codes are 0 success, 2 invalid arguments/UTF-8 or resource limit, 3 I/O
failure, and 4 allocation failure. Stderr names the reason and stage: 0
arguments, 1 input/UTF-8 validation, 2 work/segmentation/output staging, 3 writing.
Invalid UTF-8 diagnostics also give a zero-based byte offset.

## Executed evidence

`tests/extended_text_sentences_execution.rs` compiles and executes the actual
program. Its independent Python consumer oracle checks all 512 official Unicode
17 sentence vectors in framed form, exact frame reconstruction, quoted CSV with
Unicode/quotes/control bytes, long right context, empty input, argument policy,
invalid UTF-8, exact work thresholds and input/output/segment limits.

A growing multi-read input exercises allocations in argument capture, input
growth and final output. Each native allocation is failed individually with
`ENOMEM`; a syscall mapping ledger checks that all successful mappings are
released on success and late UTF-8/limit failures. EINTR/EIO read/write failures,
positive short writes and `/dev/full` exercise I/O behavior. A focused native
gate uses real closed stdout/stderr pipes with preserved descriptor redirection,
checks mapping cleanup, and injects signal-setup failure before allocation.
These native tests
require Linux x86_64, Python 3 and `strace`. The generator/conformance inputs are
vendored, and the production program does not require Python or a host Unicode
service.
