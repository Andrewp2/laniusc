# Binary summaries with bounded fallible folds

`sample_programs/library/byte_summary.lani` reads binary stdin and summarizes
its byte values through resumable iterator folds:

```sh
byte-summary [--batch N] [--reverse] [--help]
printf '\x03\x00\xff' | byte-summary --batch 2 --reverse
```

The example writes fully quoted CRLF CSV equivalent to:

```csv
"count","sum","min","max","first","last"
"3","258","0","255","255","3"
```

Input is raw bytes. NUL, invalid UTF-8 and every value from 0 through 255 are
accepted without text conversion. Count and sum are unsigned integer totals;
min, max, first and last are decimal byte values. Reverse traversal swaps the
input's first and last values and preserves the other four statistics.

## CLI and output

`--batch` ranges from 1 through 1048576 and defaults to 4096. It limits direct
source pulls per bounded fold call; it does not change the summary. Its
argument is a nonempty ASCII decimal u64 without signs or whitespace; leading
zeros are allowed. `--reverse` consumes the slice from its back instead of its
front. Short aliases are `-b N`, `-r` and `-h`.

Every duplicate option is rejected, including different aliases, repeated
help and short clusters such as `-rr`. Positional operands are rejected. Help
validates all supplied options and then bypasses stdin. Attached short values,
long equals forms and a final bare `--` follow the existing CLI parser.

Output always has exactly the six-field header and one data record. Empty
input has count and sum zero, with four empty byte fields:

```csv
"count","sum","min","max","first","last"
"0","0","","","",""
```

The CSV writer quotes every field and uses CRLF. The entire result is staged
before stdout. Input, allocation and processing failures cannot publish an
earlier CSV record. An stdout error may leave a confirmed written prefix.

## Iterator composition and checks

The actual processing path is:

```text
owned byte vector -> canonical slice Iter<u8>
    -> repeated try_fold_up_to or try_rfold_up_to
    -> checked POD summary -> staged CSV -> native stdout
```

A source-defined `TryFolder<Summary,u8,Processing>` receives the accumulator
first and byte second. Each callback checks u64 count and sum before addition,
updates min/max, retains the first encountered byte and replaces the last.
Its accumulator and error are plain values with no allocation or resource
cleanup. All callbacks use the shared generic library fold implementation.

The program keeps one canonical slice cursor and the callback alive through
all calls. The reverse branch calls `try_rfold_up_to` directly on that same
cursor. Successful progress must match the callback count increase and stay
within both batch and input bounds. A quota-ending call has exhausted=false
and resumes in the next batch, even when its last byte was the last input
byte. Only an actual observed None supplies exhausted=true; no remaining-count
query or take quota substitutes for EOF. At exhaustion the accumulated count
must equal the input length.

The expected call count for a correct finite slice is
`floor(input_bytes / batch) + 1`, including the empty input or final EOF call.
There is a separate hard fold-call cap. Progress inconsistency or callback
failure returns processing status 6 without output. These checks preserve the
library's [bounded-fold contract](library-iterator-fold-plan.md).

## Ownership and limits

The input vector owns backing storage that remains stable throughout all
fold resumptions. Its cursor borrows it and never destroys it. Processing
returns only a plain summary, then the input owner is destroyed before output
construction. A reusable CSV record copies each formatted field; stack digit
buffers do not escape. Record, output buffer and captured argument owners have
explicit cleanup on returned paths. The output buffer remains live until
publication completes. These are manual ownership contracts, not a lifetime
or leak-freedom proof.

| Resource | Bound |
| --- | ---: |
| Raw stdin bytes | 4194304 (4 MiB) |
| stdin attempts | 16384 |
| Batch direct-pull quota | 1..1048576 |
| Bounded fold invocations | 8388608 |
| Staged output | 4096 bytes |
| CSV staging / stdout / help attempts | 64 / 64 / 64 |
| Diagnostic attempts | 8 |
| Captured arguments / total argument bytes | 24 / 1024 |

An excess-byte probe distinguishes exact-cap EOF from oversized input. EINTR
retries spend their corresponding read or write budget; other errors,
including WouldBlock, terminate. Blocking stdin/stdout have no whole-program
wall-clock deadline. Each native descriptor attempt currently transfers at
most 1024 bytes.

With the accepted input cap, correct byte counts cannot exceed 4194304 and
sums cannot exceed 1069547520. Even batch 1 needs at most 4194305 fold calls.
Count/sum overflow and the larger fold-call cap are therefore defensive checks
that valid bounded input cannot reach. The larger staging cap is likewise an
explicit resource bound, rather than a claim that normal summaries approach
4096 bytes.

| Exit | Meaning |
| ---: | --- |
| 0 | Summary or help completed |
| 2 | Invalid CLI, input byte limit or input call limit |
| 3 | stdin or argument-capture I/O error, or invalid input transfer count |
| 4 | Reported allocation failure |
| 5 | stdout error/call limit or SIGPIPE setup failure |
| 6 | Checked processing, fold progress/call limit or formatting failure |

SIGPIPE is ignored before I/O. Setup failure returns 5 before diagnostics;
other failures attempt `byte-summary: operation failed\n` on stderr. Failed
diagnostics preserve the primary status.

## Target and verification

The verified target is native Linux x86_64 CPU code emitted by the GPU
compiler, with native stdin/stdout. Device-side GPU execution is outside this
profile. Production is entirely Lanius over existing iterator, vector, decimal,
CLI, CSV and stream modules. No new host service or Rust/Python library
implementation is added.

All four registered application groups are accepted on 2026-10-28, totaling
87 unique native cases across two focused runs:

| Accepted group | Cases | Receipt under `target/stdlib-work/` |
| --- | ---: | --- |
| Model | 40 | One test, 9.92s; `iterator-fold-byte-summary-model.log`, three other tests filtered |
| CLI, bounds and I/O | 32 + 1 + 14 | Three tests, 9.33s; `iterator-fold-byte-summary-boundaries.log`, model filtered |

Both runs compiled the corrected application through the GPU compiler and
passed the shared strict ELF checker before execution. Evidence directories:

- Model: `/tmp/byte-summary-model-0b9yfhjv`.
- CLI: `/tmp/byte-summary-cli-k2mgamqh`.
- Bounds: `/tmp/byte-summary-bounds-rmn_lwjp`.
- I/O: `/tmp/byte-summary-io-dsoll4va`.

The independent test-only oracle uses builtin byte length, sum, min/max and
endpoints rather than a fold or batching loop. It checks exact quoted CRLF CSV
for binary input, both directions, batch boundaries, empty input, seeded data
and exact 4 MiB input. Batch-one cases remain small. Nine CPU-only controls
passed separately.

I/O cases include real directory stdin and closed stdout failures, reached
read/write errors and retryable interruptions, plus four reached allocation
denials. Full traces pair observed successful mmap and munmap address/size
pairs on those selected processes. Persistent read EINTR uses summary-only
strace, confirming exactly 16384 failed read attempts, status 2 and no stdout;
that summary does not observe allocation releases. These are finite behavior
and fault observations, not a runtime ownership checker or lifetime/leak proof.
The unreachable checked-overflow and fold-call paths are not claimed as
injected coverage.

The first driver attempt stopped at application syntax admission in a mixed
comparison condition. `iterator-fold-byte-summary-first.log` records those
failed compile attempts, not accepted native cases. Parenthesizing the mixed
comparisons produced the current source without changing help, output,
fixtures or compiler code. Only the two subsequent receipts above establish
runtime acceptance.

Executed application source SHA-256:
`78788a611716d0230e5b7a21e6b68510da9c53266305f1af9cacc39b65ef0fe6`.
Oracle SHA-256:
`6092261549f855022f5eea91ce3737ff6f6a153cd21387294bac4a0099ab6736`.
Final registered driver SHA-256:
`1b058285a4bc6770236d368104ebd29feb609e58c9dda8a5223687c4cdba5899`.
The driver received whitespace formatting after the accepted receipts; no
behavior changed and no native rerun is claimed for that formatting. The
application and oracle identities above remain unchanged.
See `tests/fixtures/stdlib_execution/byte_summary/README.md` for the detailed
model and fault scope, and `tests/stdlib_byte_summary_execution.rs` for the
driver. With a warm build and configured GPU, reproduce using:

```sh
timeout --kill-after=2s 100s flock -w 95 target/stdlib-work/library-gpu.lock \
  env CARGO_TARGET_DIR=target/stdlib-build LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=70000 \
  cargo test --test stdlib_byte_summary_execution -- --nocapture --test-threads=1
```

The [iterator fold guide](stdlib-iterator-folds.md) records separate generic
API contracts and library evidence. This application's finite summaries do
not replace tests of per-call callback/source effects. The source imports
`core::slice` and qualifies slice-view construction, following the
[existing import limitation reduction](../tests/fixtures/stdlib_compiler_state/item_import_priority/README.md).
Compiler repair remains separate; this increment changes no compiler, ABI
or proof source. Automatic ownership, formal verification and broader target
execution remain roadmap work.
