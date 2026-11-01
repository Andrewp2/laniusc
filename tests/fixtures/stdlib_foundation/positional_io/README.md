# Portable positional I/O contracts

Both registered portable gates passed: **2 tests in 7.01 seconds**, recorded in
`target/stdlib-work/positional-io-portable-first.log`. This ran one native
contract process and compiled two expected `LNC0008` trait-bound rejections.

`contracts.lani` uses an eight-call scripted virtual file and checks all
portable positional APIs through generic `ReadAt` and `WriteAt` bounds.
Expected traces are explicit arrays of requested offsets, lengths and file
positions, rather than a copy of the helper's retry algorithm.

The finite cases cover:

- Logical range and signed-file-span admission, including the exclusive MAX
  endpoint, positions above 4 GiB, invalid unsigned positions, negative budgets,
  zero budgets, and empty operations over inaccessible backing with no calls.
- Short transfers interrupted between successes, exact budget completion,
  interrupted-call exhaustion and successful last-byte operations at MAX-1.
- EOF, zero writes, WouldBlock, preserved Host payloads, other nonretryable
  errors and negative/oversized returned counts after a confirmed prefix.
- Exact callback offset/count/position logs, unchanged backing sentinels and
  source bytes, plus negative-stride fixed bytes and packed positive-stride
  bytes. Sequential read/write/flush methods trap if accidentally called.
- Two compile rejections: `Read` plus `WriteAt` cannot satisfy `ReadAt`, and
  `Write` plus `ReadAt` cannot satisfy `WriteAt`.

The Rust driver requires a genuine x86_64 ELF, applies the shared jump checks,
executes the producer, and requires an empty trace of memory services and
read/write/pread/pwrite/seek/close operations. Portable scripted acceptance
does not establish native file behavior, device execution or formal correctness.

## Executed scope

The contract process executes four scenario functions. Its finite cases include
15 admission configurations applied to both read and write, 12 post-prefix
failure cases across both directions, and successful short-transfer schedules
over two byte layouts. Explicit assertions cover quota exhaustion, repeated
interruptions and the final valid byte position. The accepted trace contains
no memory-service or host-I/O events selected by the driver.

Accepted source hashes (SHA-256):

| Source | Hash |
| --- | --- |
| `contracts.lani` | `52200d1acc9226c502a421e9b7ad80b727bca560489c6c3884aa60cf482f1c8f` |
| `tests/stdlib_positional_io_execution.rs` | `9bc0d92a150e8fecf0e382842ee73d96b4f7c944e3c64a3de741502fd1ba8271` |
| `negative_missing_read_at.lani` | `1b3e22ca9e7d80d59d322c7f5dae650c6053b54e7540dcaa634f642b546a92ed` |
| `negative_missing_write_at.lani` | `9e9363ced5c05d1c8c81d9c5aa735ec9b6bc1c0806ceca681e11c47e8795416f` |
| `stdlib/core/io.lani` | `cd9edded4e607a9e85b97c5bcae8243bcbe0660a59af4411ada24c3d04fb8ee1` |

The executable target is Linux x86_64 CPU output produced by the GPU compiler.
The source and driver were unchanged when this receipt was added.

Focused selectors:

```text
cargo test --test stdlib_positional_io_execution portable_positional_io_executes_exact_offsets_and_confirmed_failure_prefixes -- --exact
cargo test --test stdlib_positional_io_execution positional_exact_helpers_require_the_matching_explicit_offset_traits -- --exact
```
