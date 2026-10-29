# Direct resumable decompression contracts

These fixtures exercise the public caller-workspace APIs in `ext::inflate`
and `ext::compression`. The authoritative behavior is frozen in
`docs/library-streaming-inflate-plan.md`.

## Registered execution groups

`tests/stdlib_inflate_stream_execution.rs` registers exactly four tests:

- `resumable_inflate_stored_chunks_execute_exact_native_admission`:
  inert construction, split stored header/data, exact per-call progress,
  output suspension, raw trailing-byte retention, completion and reset.
- `resumable_inflate_fields_matches_errors_and_recycled_strided_buffers_execute`:
  fixed, stored and dynamic literal streams; overlap at distances one/two;
  history across blocks and ring wrap; repeat codes 16/17/18; 15-bit canonical
  codes; exact malformed/truncated progress; stored input/output precedence;
  incomplete HLIT precedence. Every input and output chunk is overwritten
  between calls. Native descending bytes and packed ascending bytes alternate
  across input, output and history, with nonzero starts and outer guards.
- `resumable_inflate_metadata_reset_and_terminal_progress_preserve_caller_storage`:
  constructor metadata/capacity/window admission, full history/workspace
  snapshots, invalid step/reset inertness, recoverable Bounds, sticky codec
  failure, completion precedence, pending literal preservation and logical
  history reset. Invalid descriptors use null backing to make premature access
  observable. No invalid physical backing is submitted with valid metadata.
- `resumable_container_framing_checksums_members_limits_and_exact_progress_execute`:
  raw/zlib/gzip and concatenated gzip, optional extra/name/comment/FHCRC,
  recycled byte chunks and both byte layouts, exact output budgets, unread-tail
  input accounting, complete-header/trailer precedence, dictionary rejection,
  checksum and size errors, provisional output/counters, member history reset,
  final EOF, split next-member magic, metadata and terminal/reset behavior.

The raw valid bitstreams were constructed from RFC 1951 fields and independently
checked with system zlib. Container constants use the same stored binary payload
and independently computed Adler-32/CRC32 trailers; zlib independently decoded
ordinary zlib, gzip and optional-header gzip constants. No production codec,
crypto primitive, native codec dependency, or transport is supplied by the test
code. Larger independent oracle/model and ownership tests live in separate
fixtures and drivers.

## Execution gate

The driver compiles each fixture through the GPU compiler to Linux x86_64 CPU
code, requires a strict executable ELF, applies the shared in-function jump
validator, and actually executes it under a 15-second child timeout. A complete
syscall trace must contain exactly one successful executable launch and one
successful exit, with no intervening host effects. Stdout/stderr must be empty.
Root runs compiler/native commands serially, under the library lock and the
outer bounded command deadline.

This is native CPU execution of GPU-compiler output. It does not establish
execution on a GPU device, other targets, formal verification, memory safety of
invalid caller backing, or u64/ISIZE wrap behavior after billions of bytes.
Borrow lifetime, disjoint storage and inactive aliases remain caller obligations.

## Accepted receipts

- Tiny admission passed in the first gate: 1 test in 4.67 seconds;
  `target/stdlib-work/inflate-stream-admission-first.log`.
- The final frozen direct suite passed all 4 tests in 12.02 seconds (Rust build
  0.18 seconds), with every complete no-host-effects trace accepted:
  `target/stdlib-work/inflate-stream-direct-final.log`.
- An earlier raw-only pass is retained in
  `target/stdlib-work/inflate-stream-direct-first.log` (1 test, 4.79 seconds).
  Review subsequently corrected the chunk scheduler to reoffer the exact unread
  final suffix; the accepted final suite includes that correction.

These receipts cover the exact driver and fixture hashes below. Root executed
all native gates; this fixture owner ran no compiler or native commands.

## Frozen sources

SHA-256:

| Source | Hash |
| --- | --- |
| `tests/stdlib_inflate_stream_execution.rs` | `77e1e8da0aacdb408f2ac75aab0ca474ca6e3780ed11df1cb81c12d6440c23d7` |
| `admission.lani` | `13e11fb64ebb4301abca292737616edff458e85a1279e4c6736c57f9b2975c5d` |
| `contracts.lani` | `54e4e4f89bc72d05af907cd069db1210a3b9ac878a58c0eb169a3bc06d325e21` |
| `preflight.lani` | `5aec946c08c3734c02e70c0fca86d550f5d250c55fc18146ff1d96d6be2496b5` |
| `framing.lani` | `86c907f4d5089bef05406f7b1544cbfcd6066413e0504d041f65ec86bab7625d` |
