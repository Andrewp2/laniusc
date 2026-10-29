# Portable seek contracts

All three registered tests passed across two commands:

| Receipt | Accepted scope | Time |
| --- | --- | --- |
| `target/stdlib-work/seek-admission-first.log` | One admission test and native process | 6.30s |
| `target/stdlib-work/seek-contracts-first.log` | Two tests: one native four-scenario contract process and one marked LNC0008 rejection; admission filtered | 4.74s |

Root ran the compiler, Cargo and native commands. These finite direct core
receipts are separate from buffered, File, independent-model and application
gates.

`admission.lani` exercises a custom `Seek`-only provider through generic calls,
all origins, `stream_position`, `rewind` and `offset_position`, then seeks actual
`SliceReader` and `SliceWriter` values. Input bytes stay unchanged. The driver
requires strict x86_64 ELF and a complete syscall trace containing only process
entry and exit.

`contracts.lani` has four finite scenario functions. Literal offset expectations
cover i64::MIN, i64::MAX and u64::MAX, exact endpoints and out-of-domain results.
Scripted `Seek`-only providers record each origin and argument: helpers make
exactly one call, preserve errors (including Interrupted), accept a full-width
position and reject a malformed nonzero rewind acknowledgement. Provider
effects before an error remain visible, without a rollback promise.

Memory-cursor cases reject invalid public states before arithmetic and admit
zero-byte or huge logical cursor operations without touching inaccessible
backing. Ordinary cursor tests seek from every origin, then read and write real
binary bytes through both actual byte strides. Bounds failures preserve cursor
and backing, and writes at the admitted end return zero. A marked LNC0008
negative fixture proves that `Read` alone does not satisfy the `Seek` bound.
Both accepted native processes had full syscall traces containing only process
entry and exit, with no allocation or host I/O effects.

Accepted fixture and production source hashes:

| Source | SHA-256 |
| --- | --- |
| `admission.lani` | `794b010a2a8fcdc74ae995c0762696c778b2e0ad0cb7f31f02c5dd667f2e8775` |
| `contracts.lani` | `ba1723a19d869cf617c0b184a9752320b53c09b2964e50e19e9da68e7e980272` |
| `negative_missing_seek.lani` | `95f59df033e061d916b08a6309c17294388a29a3e5e6cf2193dadb9835ea2c75` |
| `stdlib/core/io.lani` | `16f3f761235ed7e3e0cde154e5a45555d55f09fa69e94507b2744c41227def31` |

```text
cargo test --test stdlib_seek_execution seek_only_generic_provider_and_memory_cursors_execute_admission -- --exact
cargo test --test stdlib_seek_execution portable_seek_executes_signed_boundaries_state_guards_and_strided_io -- --exact
cargo test --test stdlib_seek_execution position_helper_requires_seek_instead_of_sequential_read -- --exact
```

Accepted target scope is a native Linux x86_64 executable produced by the GPU
compiler and run on the CPU. GPU device execution and formal correctness are
unclaimed.
