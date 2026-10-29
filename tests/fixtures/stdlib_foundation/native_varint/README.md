# Native checked-varint direct contracts

Both registered direct tests passed on their first runs, in separate commands:

| Receipt | Accepted scope | Time |
| --- | --- | --- |
| `target/stdlib-work/native-varint-admission-first.log` | One admission test and native process | 4.72s |
| `target/stdlib-work/native-varint-direct-first.log` | One native four-scenario contract test; admission filtered | 5.14s |

Root ran the compiler, Cargo and native commands. Independent wire-model,
physical-boundary and application gates are separate from these finite direct
receipts.

`admission.lani` executes reads and writes for all four native integer widths
at full extrema, transporting typed `Result<Decoded<T>,Error>` through a generic
helper. It uses a nonzero View start and relative offset, checks literal wire
bytes, and preserves outside guards. Both accepted native processes passed
strict x86_64 ELF checks and full syscall tracing: only process entry and exit
occurred, with no allocation or other host services.

`contracts.lani` has four finite scenario functions and executes all 16 public
functions. Literal length and ZigZag tables cover width boundaries and signed
extrema. Thirty-seven wire vectors run through native descending byte storage
and packed positive-stride storage: writers must emit the exact bytes, and
readers separately decode literal bytes with and without trailing data. Every
encoded length from one through ten bytes is represented. Successful next
offsets are relative to the nonzero View start.

All-width writer failures check the entire backing for atomic rejection,
including exact BufferTooSmall payloads. Null-backed malformed metadata and
invalid offsets reject before access. A valid empty View at start=i32::MAX
reports Truncated or the required byte count without accessing backing.
Fifth/tenth-byte continuations and oversized payloads report Overflow;
admitted zero terminators after the first byte report NonCanonical. Truncated
prefixes and all read errors retain the exact input bytes. These cases also
run through both actual byte strides.

Accepted fixture and production source hashes:

| Source | SHA-256 |
| --- | --- |
| `admission.lani` | `92cd28fd0ff7ae96752ae038da49ad955799e9513f21cdde11753d0b4e0bc59a` |
| `contracts.lani` | `2e3bdccbe830e395aaab21acda111d3e610c6774181a4b1646884c73c6702dc1` |
| `stdlib/core/varint.lani` | `a0ef8c9ff2c5fc83fb8449c6baeaff4f24d9c3a0f32b962b68dfc11efbcc147b` |

```text
cargo test --test stdlib_varint_execution native_varint_all_widths_execute_extrema_and_generic_decoded_admission -- --exact
cargo test --test stdlib_varint_execution native_varint_literal_wires_lengths_errors_and_atomic_writes_execute -- --exact
```

The old status and two-word positive fixtures and signed driver are retired.
Physical backing-overclaim coverage is owned by the separate boundary suite.
Accepted target scope is native Linux x86_64 CPU execution of GPU-compiler output;
GPU device execution and formal correctness are unclaimed.
