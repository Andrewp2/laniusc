# Bounded numeric record repacking

`sample_programs/library/repack_records.lani` converts a binary record frame
between explicitly selected byte orders:

```sh
repack_records le be < little-endian.lnr > big-endian.lnr
repack_records be le < big-endian.lnr > little-endian.lnr
```

FROM and TO must each be exactly lowercase `le` or `be`. A sole `--help` or
`-h` prints usage without reading stdin. Other options, extra operands and
help mixed with a conversion are errors. Argument capture admits at most two
values and 64 total bytes, excluding terminating NULs.

## Frame and field contract

The frame begins with the four ASCII bytes `LNR1`, followed by a u32 record
count in FROM order. Exactly that many 32-byte records follow:

| Offset within each record | Width | Field |
| ---: | ---: | --- |
| 0 | 8 | u64 identifier |
| 8 | 8 | i64 timestamp |
| 16 | 4 | i32 channel |
| 20 | 4 | IEEE binary32 sample |
| 24 | 8 | IEEE binary64 reading |

The record count is 0 through 65536. A frame therefore contains exactly
`8 + 32 * count` bytes, at most 2097160 bytes. Count zero is valid and produces
an eight-byte frame. Empty stdin, bad magic, a short header, an oversized count,
truncated records and any trailing bytes are rejected.

Output retains the magic and record order, encodes the count in TO order, and
encodes each field in TO order. Signed fields retain their two's-complement
bits. Float fields have no numeric validation or arithmetic: the required
contract preserves zero signs, subnormals, infinities, and all quiet/signaling
NaN payload bits. Same-order conversion must be byte identity.

Every record is decoded and reencoded through the public
`core::endian::read_u64_*_or`, `read_i64_*_or`, `read_i32_*_or`,
`read_f32_*_or`, `read_f64_*_or` and corresponding `write_*` functions.
Count uses the existing u32 family. The same-order path also executes these
operations. The application has no private byte-reversal implementation or
floating-point conversion algorithm.

## Validation, publication and ownership

The program first reads through actual EOF into one
`alloc::io::Buffer` with a 2097160-byte logical limit. Only then does it validate
the complete magic, count and exact declared length. The full u32 count is
bounded before conversion to i32 or multiplication.

After successful validation, it changes the count and fields in place in that
buffer. Every field is read before that record's fields are written. The
backing remains live and unchanged in capacity throughout conversion. The
validated length and bounded record loop establish each public codec's
logical range and physical backing.

Stdout begins only after the entire conversion completes. Malformed,
oversized or truncated input, input errors, allocation failures and an
unexpected rejected codec write therefore publish no data. Failure precedence
follows the executed phases: an input I/O error or allocation failure may be
reported before a later framing problem can be examined.

The buffer owns input and staged output; no second output allocation is made.
It starts without backing, grows through the existing bounded byte-sink API,
and is explicitly destroyed on every return from the conversion workflow.
Argument capture has its own owner and is destroyed after argument handling
returns. No owner is copied into a separate cleanup authority. Descriptor
wrappers borrow stdin/stdout; the application does not close those descriptors.

## Budgets and failure behavior

| Resource | Bound |
| --- | ---: |
| Captured arguments / bytes | 2 / 64 |
| Records | 65536 |
| Logical input / staged output bytes | 2097160 each, sharing one buffer |
| Stack input staging | 4096 logical bytes |
| Input stream calls, including EOF and Interrupted | 8192 |
| Output stream calls, including Interrupted | 8192 |
| Bytes per native descriptor transfer | 1024 |
| Help stdout calls | 64 |
| Diagnostic stderr calls | 8 |
| Record conversions | At most 65536 |

Each input attempt consumes the shared input budget. Interrupted retries;
other errors terminate. A positive read is checked against the requested
count before append. At the byte cap, a one-byte probe distinguishes EOF from
oversized input without extending the buffer.

Output advances only by confirmed positive counts. Interrupted consumes an
attempt and retries; zero, invalid counts, other errors or exhausted attempts
stop. An output failure can leave the already published prefix. The program
does not replay it or promise output rollback. These call budgets impose no
wall-clock deadline on blocking host I/O.

| Exit | Meaning |
| ---: | --- |
| 0 | Complete frame written, or help written |
| 2 | Invalid CLI, framing/length/count/byte limit, or input call exhaustion |
| 3 | Argument capture or stdin I/O failure |
| 4 | Argument or input-buffer allocation failure |
| 5 | SIGPIPE setup, help output or frame output failure |
| 6 | Unexpected buffer/codec contract failure after admitted ranges |

For an error, stderr is attempted as the exact line
`repack_records: operation failed\n` using eight calls. A failed diagnostic
preserves the primary status. SIGPIPE is ignored before I/O; setup failure
returns 5 without a diagnostic. Successful conversion has no stderr output.
A return of zero acknowledges completed descriptor writes, not crash durability
or downstream consumption.

## Target and acceptance

All four registered application groups passed on 2026-10-28, totaling 96
native cases across two focused runs:

| Accepted group | Cases | Receipt under `target/stdlib-work/` |
| --- | ---: | --- |
| Model | 27 | One test, 7.80s; `native-endian-repack-model-first.log`, three other tests filtered |
| CLI, rejection and I/O | 23 + 30 + 16 | Three tests, 7.62s; `native-endian-repack-boundaries.log`, model filtered |

The model run's driver build took 1.64s. Both registered runs compiled the
application through the GPU compiler and passed the shared strict ELF checker
before native Linux x86_64 CPU execution, using existing descriptor and
allocator services. GPU-device execution and other backends remain unverified.

Executed application source SHA-256:
`6c2106c1e6b7c8e8c0ff0e1717443190798779bd86cda56dab54159c3b6c9355`.
Only a trailing blank line was removed after execution; the committed source
hash is `1e4b7b869b41177385461bb9643a9a7d73c62c46abb21f3a3408db872802646f`.
Oracle SHA-256:
`acab9ead1b8c4087943145fd5e0600c5e3e2db998fe915b8c588bbc6d4fcc0fa`.
Evidence directories:

- Model: `/tmp/repack-records-model-bs11ehz7`.
- CLI: `/tmp/repack-records-cli-5gsed9sn`.
- Rejection: `/tmp/repack-records-rejection-20lmhw1w`.
- I/O: `/tmp/repack-records-io-h0v9new5`.

The independent test-only oracle constructs per-field byte encodings by
integer shifts and masks. IEEE payloads remain integer bits throughout; Python
float conversion cannot quiet a signaling NaN in the reference. Explicit
known little/big byte strings also check the model independently of round trips.
Executed models cover all four FROM/TO combinations, byte-identical same-order
results, zero/singleton/65536 counts, signed extrema, full-width high bits,
zero signs, normal/subnormal values, infinities and quiet/signaling NaN payloads,
1024-byte frame boundaries and seeded raw bits. This establishes exact-bit
behavior for the exercised values on this target, not an exhaustive proof over
all bit patterns or compiler backends.

Rejection cases cover malformed magic/header/count/length, truncation, trailing
bytes and the input cap with empty stdout. Header-only counts `0x80000000` in
both orders check admission before narrowing. CLI cases exercise exact spellings,
help exclusivity, argument bounds and input bypass.

I/O cases execute directory stdin, closed data/help stdout, read/write EINTR,
read errors, failure of the required EOF probe after a complete frame and
SIGPIPE setup failure. A second-output-call EIO follows a real successful
1024-byte write and leaves exactly that independently encoded prefix. Persistent
EINTR summaries record 8192 input errors, or 8192 output errors followed by one
successful stderr diagnostic; these compact summaries do not observe releases.

The baseline trace observes no allocation after input EOF. Four reached
allocation-denial sites cover the two CLI snapshot allocations and first/last
input growth; each returns 4 with empty stdout. Detailed traces require matching
successful same-address/same-size releases for all observed successful mappings.
These are finite observations, not a resource checker or a proof of general
lifetime, aliasing, leak freedom or arbitrary-failure safety. The defensive
status-6 codec/buffer failure path is not claimed reachable from a valid frame.

See `tests/fixtures/stdlib_execution/repack_records/README.md` for retained
commands and detailed case scope, and `tests/stdlib_repack_records_execution.rs`
for the registered driver. Whitespace-only driver formatting after these
receipts does not represent a native rerun. With a warm build and configured
GPU, reproduce using:

```sh
timeout --kill-after=2s 100s flock -w 95 target/stdlib-work/library-gpu.lock \
  env CARGO_TARGET_DIR=target/stdlib-build LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=70000 \
  cargo test --test stdlib_repack_records_execution -- --nocapture --test-threads=1
```

The application adds no compiler, runtime ABI or proof source. Production is
Lanius, with no Rust/Python library implementation, JSON transport, Wasm
dependency or host byte-order assumption. See the
[native endian plan](library-native-endian-plan.md) for the public family and
separate library acceptance requirements.
