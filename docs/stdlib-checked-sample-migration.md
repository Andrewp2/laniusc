# Checked collection and output samples

Seventeen ordinary sample programs now use explicit collection failures and
checked output. Twelve previously imported `std::vec`; all nine calls to
`std::io::print_i32` in seven programs now compose the existing decimal
formatter and complete stream writer. The migrated samples no longer use
either interface or the statusless `print` primitive.

This migration changes Lanius application code. The protected `std::vec`
module, formal extraction, compiler and diagnostic catalog remain unchanged.
A separate source-only heap view correction is described below.

## Collection ownership and preserved behavior

| Samples | Migration and contract |
| --- | --- |
| `vector_halfword_checksum`, `vector_unsigned_checksum`, `vector_signed_byte_sum`, `vector_signed_halfword_sum`, `vector_true_count`, `vector_square_sum` | Borrow one `alloc::vec` owner, check every push, read within its initialized count and destroy it before output. The existing wrapping/saturating calculations and output values remain unchanged. |
| `vector_edit_checksum` | Use the checked `from_view` builder, insertion and value-returning removal. The removed integer transfers explicitly to the caller. The final sequence is still `[3,5,11]`, with checksum 19. |
| `wide_signed_sum`, `wide_unsigned_sum` | Keep the existing represented two-word values, decimal-line grammar, 20-byte line capacity and modulo-2^64 sum. Only the vector owner and output delivery change; no represented integer implementation is duplicated or replaced. |
| `unicode_sort_unique` | Store valid `char` values in an alloc vector, check growth and sort by scalar value. Preserve the 4,096-scalar ceiling, duplicates, NUL and all Unicode scalar values. The output is the distinct sorted scalars followed by LF; an input LF is also an ordinary scalar in that set. No normalization or grapheme grouping occurs. |
| `unicode_text_report` | Use an alloc byte vector for input. Keep the owned UTF-8 validation, byte/scalar count header and reversal by scalar, including NUL and combining scalars. Reverse-buffer failures may occur after the count header has been written, as before. |
| `top_scores` | Retain the existing min-heap selection engine and its checked insertion. Reserve an alloc vector before transferring values through the heap's existing `pop` operation. Its ascending pop order becomes descending output by traversing the vector backwards. No legacy owner escapes into the application. |

All growth failures destroy the active owner before returning. These samples
store plain scalar/number values, so removed or displaced elements contain no
nested resource requiring destruction. The canonical vector still has manual
shallow ownership: copying an owner does not create an independent allocation.

`top_scores` keeps its K range 0..=4,096, at most 100,000 scores, 1 MiB complete
input ceiling, signed-i64 grammar and descending output with duplicates. Equal
scores are indistinguishable scalar values; no new stability promise is made.
The destination reserve adds one explicit allocation failure before output. At most
4,096 heap slots and 4,096 output-vector slots coexist, in addition to the
existing bounded input buffer. The heap algorithm is shared with the library.

Before the separate heap view correction, the attempted view-based builder and
an 11-line `BinaryHeap<i64>::as_view` reproduction hit LNC0047. An independent
`Vec<i64>` sort control and the checked drain builder executed. Exact failing
and successful contexts, including the original heap module and an isolated
reproduction helper, are retained under
`tests/fixtures/stdlib_compiler_state/checked_sample_heap/`. The heap owner then
replaced its nested view-result construction with an owner-proven direct View
return; the focused heap view/contract group passed. The production application
keeps the checked drain form, using the shared owner/priority operations.

## Checked delivery and signal policy

The integer samples format into fixed caller-owned buffers with
`core::decimal::format_i32` or `format_i64`, append LF, and call
`core::io::write_all` with a `std::stream` descriptor. Represented wide sums and
Unicode output use their existing scalar/decimal encoders with the same shared
delivery loop. Every fallible result is inspected.

Positive short writes advance by the reported count. Interrupted writes retry.
Zero progress or another host error returns a nonzero status. A real stream
failure can leave a written prefix; the samples do not claim atomic or durable
output. Count headers and score lines retain their exact visible bytes.

Each program explicitly requests `std::signal::Signal::BrokenPipe` with
`Disposition::Ignore` before allocating or writing. This is application policy,
implemented through the shared checked `std::signal::set_disposition` API. A
closed reader then produces an EPIPE error through the writer instead of
terminating the program before it can report its I/O status. Failure to install
the policy returns that same I/O status before work begins. There is no global
runtime signal-policy change or local syscall-packing implementation.

The existing raw byte/scalar/line input helpers in the Unicode and represented
wide programs still report an interrupted read as their documented error.
`top_scores` uses `std::stream::copy`, whose complete-copy loop retries
interrupted reads. The migration does not silently turn malformed input or
input failure into a valid scalar or score.

| Sample | Output / signal-setup failure status |
| --- | ---: |
| Four narrow checksum programs and `vector_true_count` | 3 |
| `vector_square_sum` | 2 |
| `vector_edit_checksum` | 4 |
| `result_reading_total`, `random_fill` | 3 |
| `stdio_flush` | 4 |
| `stdio_print_i32` | 1 |
| `host_runtime_files` stdout | 6 |
| `unicode_sort_unique` | 5 |
| `unicode_text_report`, `top_scores` | 3 |
| Represented wide sums | 5 |

Other existing input, allocation and calculation statuses remain distinct.
`host_runtime_files` still attempts to close each opened descriptor on a write
or read failure and reports its earlier file-phase statuses. A failed close is
attempted once: retrying an ambiguous close can affect a reused descriptor.
Its read now requires all six written bytes before parsing the five digits and
LF. Fault injection exposed that the former raw fallback integer reader could
accept a completed digit prefix when the following delimiter read returned
EIO; the checked exact read reports that failure and retries EINTR.

## Native verification

`tests/stdlib_checked_sample_migration_execution.rs` compiles the actual
seventeen samples. Its independent Python oracle checks fixed expected output,
seeded Unicode scalar sorting/reversal, full-width modular integer sums and
priority selection. Directed cases include extrema, duplicates, NUL, combining
scalars, supplementary characters, invalid UTF-8 and the scalar ceiling.

For each small successful witness, the oracle enumerates every reached native
allocation and every read/write position. It injects ENOMEM, EIO, EINTR,
zero-progress writes and positive short stdout writes. A mapping ledger matches
every successful mmap to its exact munmap address/length on success and failure.
Additional cases cover late invalid/over-limit input, stderr delivery,
signal-setup failure, `/dev/full`, closed reader pipes, entropy failures and
file open/close failures. File descriptors have one close attempt per acquired
ownership, including error paths.

The existing `top_scores` gate retains its large inputs, exact 1 MiB input
boundary, 100,000-score ceiling and all reached allocation failures. Its I/O
expectations now reflect complete score lines and retrying EINTR rather than
the former one-byte writes.

Verification applies to native x86_64 Linux. Python is a test oracle, not a
production implementation. The tests require `strace` for native fault
injection and resource accounting.

The five focused groups pass: 316 independent result cases and 421 injected
failure cases. The failure cases include 27 reached allocation denials, 219
read faults, 116 write faults, 25 signal/entropy/file-operation faults, 17
`/dev/full` runs and 17 closed-reader-pipe runs. Additional traces check owner
cleanup after late malformed and over-limit input. Passing group times are
14.67 s (fixed vectors), 10.09 s (formerly statusless output), 11.82 s
(Unicode), 8.03 s (represented wide sums) and 6.96 s (heap application).
The existing large-input `top_scores` gate also passed in 6.74 s, including its
exact input/count boundaries and reached allocation and I/O failures.

## Historical compiler control

Before changing `sample_programs/stdio_print_i32.lani`, its exact HEAD source
was copied to
`tests/fixtures/stdlib_compiler_state/wasm_primitive_output/stdio_print_i32.lani`.
The existing Wasm compiler regression now reads that fixture and retains its
`34\n55\n` stdout contract. This preserves the old compiler context as
historical evidence; it adds no compatibility alias or production fallback.
The migrated canonical sample has the native support scope described above.
