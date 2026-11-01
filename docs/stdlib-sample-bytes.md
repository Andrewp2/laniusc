# Binary sampling with exact-size iterators

`sample_programs/library/sample_bytes.lani` samples binary stdin without text
conversion, a reversed input copy or a handwritten sampling loop:

```sh
sample-bytes [--offset N] [--step N] [--count N] [--reverse] [--help]
printf '0123456789' | sample-bytes --reverse --offset 1 --step 3 --count 2
```

The example writes exactly `85`, with no trailing newline. All byte values,
including NUL and bytes above 127, pass through unchanged.

## Selection and CLI

The tool reads through EOF, optionally reverses input iteration, skips `offset`
bytes, selects every `step`th byte beginning at the next byte, and takes at most
`count` selected bytes. The order is:

```text
slice iterator -> optional rev -> skip -> step_by -> take -> staged byte vector
```

Defaults are offset 0, step 1 and count 18446744073709551615. Each parameter is
a nonempty sequence of ASCII decimal digits representing a u64; leading zeros
are allowed, signs and whitespace are rejected, and step must be positive.
An offset beyond the input produces empty output. A step beyond the input
still selects the first byte after the offset when one exists. Count zero
produces no bytes but still reads and bounds-checks all input.

Short aliases are `-o N`, `-s N`, `-n N`, `-r` and `-h`. Attached values, long
`--name=value` forms and short clusters follow `ext::cli`. Every duplicate
option is rejected, including duplicates through different aliases or inside
clusters. Positional operands are rejected. A bare final `--` is allowed.
Help validates all supplied options, writes usage and bypasses stdin.

## Exact count and ownership

The ordinary and reversed branches call the same generic helper bounded by
`Iterator<u8>` and `ExactSizeIterator<u8>`. That helper constructs real borrowed
`Skip`, `StepBy` and `Take` adapters. It queries the final adapter's
`remaining_count()` and reserves that many output slots before consumption.
It does not mistake the take quota for the number of available bytes.

Every byte is appended through `Vec::try_push`; the exact count never permits
unchecked writes. An independent 1 MiB bound guards the append loop, and the
final output length must equal the promised count before any stdout write.
A count-contract failure returns status 2 with no output.

The input vector owns its backing storage. Its cursor, optional reverse cursor
and each adapter stay alive and their backing remains unchanged throughout
selection. Adapters borrow their sources and have no resource cleanup or hidden
ownership transfer. After selection, input storage is destroyed; independent
output storage remains until publication completes. Input, output and argument
owners are explicitly destroyed on returned paths. These are source contracts,
not a leak-freedom proof.

## Bounds and failures

| Resource | Bound |
| --- | ---: |
| Raw input and staged output | 1048576 bytes each |
| stdin attempts | 4096 |
| stdout attempts | 4096 |
| Diagnostic attempts | 8 |
| Captured arguments / total argument bytes | 24 / 1024 |

An excess-byte probe distinguishes exact-cap EOF from oversized input. Every
I/O attempt, including EINTR, spends its call budget. Interrupted transfers
retry; other errors, including WouldBlock, terminate the operation. The current
native descriptor adapter transfers at most 1024 bytes per attempt. Blocking
stdin/stdout have no wall-clock deadline.

| Exit | Meaning |
| ---: | --- |
| 0 | Selected bytes, empty selection or help completed |
| 2 | Invalid CLI, input/call limit, or violated exact-count contract |
| 3 | stdin error or invalid input transfer count |
| 4 | Reported allocation failure |
| 5 | stdout error/call limit or SIGPIPE setup failure |

SIGPIPE is ignored before I/O. Failure to configure it returns 5 before a
diagnostic is attempted. Subsequent errors attempt
`sample-bytes: operation failed\n` on stderr; diagnostic failure preserves the
primary exit. Output is staged before publication, so input, allocation and
selection failures publish no prefix. An output failure can leave a confirmed
written prefix. Empty output makes no stdout write and can succeed with a
closed stdout reader.

## Target and verification

The verified executable target is Linux x86_64 emitted by the GPU compiler.
This application uses native stdin/stdout and makes no claim of device-side GPU
execution. Production code is entirely Lanius and uses existing `ext::cli`,
`core::iter`, `alloc::vec` and `std` facilities. No Rust/Python library
implementation, C library, JSON transport or Wasm dependency is added.

The registered driver `tests/stdlib_sample_bytes_execution.rs` compiled the
application through the GPU compiler, passed the shared strict ELF checker,
and passed all four tests on 2026-10-28. Its independent test-only oracle uses
Python byte slicing. The accepted groups are model 37, limits 3, CLI 39 and
I/O 16: 95 finite application cases. Runtime took 9.44 seconds; Cargo build took
1.70 seconds. The retained receipt is
`target/stdlib-work/sample-bytes-runtime-first.log`.

The I/O cases include actual directory stdin errors, closed stdout,
nonblocking input, interruption retries and caps, a real written prefix before
a later error, and two reached allocation denials. There is no resource ledger,
leak proof or exhaustive fault claim. Eight CPU-only controls passed separately.
Each native child is limited to 20 seconds and each registered group to 85
seconds. Accepted evidence directories are:

- Model: `/tmp/sample-bytes-model-s8tfmb4c`.
- Limits: `/tmp/sample-bytes-limits-0hmwt3q5`.
- CLI: `/tmp/sample-bytes-cli-urlxjxfx`.
- I/O: `/tmp/sample-bytes-io-zz6pp3oe`.

Executed source SHA-256:
`f2dc47389be7c22f32e23ae790dfb2bd2055619127023ae6952cd160a75b81b2`.
Oracle SHA-256:
`3303757c39451c5646de9dfb9c842b151c5897a1a5c83e35f72cc64de8c3da27`.
No separately retained direct-run ELF is claimed. See
`tests/fixtures/stdlib_execution/sample_bytes/README.md` for reproduction
commands and evidence boundaries.
