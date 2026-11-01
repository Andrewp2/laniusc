# Explicit record storage with checked layouts

`sample_programs/library/layout_records.lani` composes byte-storage layouts,
allocates one arena block, fills and verifies deterministic records, then
prints a small binary report:

```sh
layout_records 257 > report.bin
```

COUNT is required and must be ASCII decimal 0..65536, parsed by
`core::decimal::parse_u64_range`. Leading zeros are allowed; signs,
whitespace, prefixes, empty input and out-of-range values are rejected.
A sole `--help` or `-h` prints help. No other options or operands are
accepted. Argument capture admits one value and 64 total bytes, excluding
its terminating NUL. The application never reads stdin.

## Composed storage contract

This describes explicit packed byte storage, not the compiler's native
layout for a record or typed array. The program constructs these public
`core::layout` values:

| Field | Size | Alignment | Composed offset | Encoding |
| --- | ---: | ---: | ---: | --- |
| tag | 1 | 1 | 0 | One u8 |
| serial | 4 | 4 | 4 | Little-endian u32 |
| value | 8 | 8 | 8 | Big-endian u64 |

It calls `from_size_align` for each field, `extend` twice,
`pad_to_align` on the complete record and `array` for COUNT records.
The resulting record has alignment 8 and padded stride 16. Bytes 1..3 of
every record are zero padding. The array occupies exactly `COUNT * 16`
bytes, at most 1048576.

All layout results are checked. The program verifies the returned offsets,
stride and alignment, checks total size against i32 before narrowing, then
requests `arena.allocate(total_size, 8)`. A valid arithmetic layout alone
does not establish physical backing; only successful arena allocation permits
construction of the borrowed byte view.

The arena configuration is chunk_size 4096, max_retained 2097152 and
max_chunks 1. One nonempty block therefore uses one retained chunk; the
4096-byte default chunk may exceed a small block's requested size. COUNT zero
still composes and validates the record/array and makes a zero-size arena
request. That request uses the arena's non-dereferenced aligned sentinel and
retains no chunk. Its raw view has length zero.

## Values and readback

For record index i in 0..COUNT, fields are:

```text
tag    = (17*i + 3) mod 256
serial = (i * 65537) XOR 0xa5a5a5a5
value  = (i * 281479271743489) XOR 0x0123456789abcdef
```

The largest index is 65535. Its serial multiplication is exactly u32::MAX;
its value multiplication is exactly u64::MAX. The products fit their widths
before XOR, with no signed conversion or overflow required.

A public counted `View<u8>` borrows the complete packed arena block.
`View.fill(0)` initializes fields and padding. `View.try_set` writes
each tag; public endian codecs write serial/value. A separate readback pass
checks every tag, all three padding bytes and both decoded numeric fields.
The same live arena owner backs every view throughout these passes.

## Exact report

Stdout is exactly 24 bytes, with no header or text terminator:

| Report byte offset | Width | Big-endian u64 value |
| ---: | ---: | --- |
| 0 | 8 | COUNT |
| 8 | 8 | Total requested record bytes, COUNT * 16 |
| 16 | 8 | Weighted checksum of actual stored bytes |

For stored byte b[j] at zero-based physical byte position j in the packed
block, checksum is:

```text
sum over j of ((j + 1) * b[j]) modulo 2^64
```

The checksum reads the actual complete block, including zero padding, through
the public byte view. It does not recompute the logical field values. The
maximum admitted block bounds this sum below 2^48, so no wrap occurs for this
CLI. This is a deterministic validation checksum with no cryptographic claim.
COUNT zero produces 24 zero bytes.

Only after every layout/allocation/write/readback/checksum stage succeeds does
the program destroy the arena, encode the three report fields through public
u64 big-endian codecs into caller-backed storage and publish stdout. Invalid
arguments or any prepublication error therefore produce no report prefix.

## Owners, work and failures

The arena has one explicit cleanup authority. The block and byte views borrow
it and do not release individual allocations. Every path after arena creation
destroys it once, including allocation, codec and readback failures. No byte
view escapes that lifetime. The argument snapshot has its own owner, retained
until argument handling returns and explicitly destroyed before main returns.

The arena is released before report encoding and stdout. The 24-byte output
array is stack storage; the native descriptor adapter respects its actual
stride. No output allocation or compiler-native record-layout assumption is
introduced.

| Resource | Bound |
| --- | ---: |
| COUNT | 0..65536 |
| Captured arguments / bytes | 1 / 64 |
| Record stride / alignment | 16 / 8 |
| Requested arena block bytes | 1048576 |
| Retained arena bytes / chunks | 2097152 / 1 |
| Arena block allocation requests | One |
| Block initialization/checksum byte positions | At most 1048576 each |
| Record fill/readback passes | At most 65536 records each |
| Report bytes | 24 |
| Data/help stdout attempts, including Interrupted | 64 each |
| Diagnostic stderr attempts | 8 |

Output retries only Interrupted, advancing solely by confirmed positive
counts. Zero, invalid counts, other errors or exhausted attempts stop; an
output failure may leave a confirmed prefix without replay. The attempt budget
does not impose a deadline on blocking host writes. Success acknowledges
completed descriptor writes, not downstream consumption or durability.

| Exit | Meaning |
| ---: | --- |
| 0 | Complete report written, or help written |
| 2 | Invalid CLI/count/argument limits |
| 3 | Argument-capture host error |
| 4 | Argument or arena allocation failure |
| 5 | Data/help output or SIGPIPE-policy failure |
| 6 | Layout, arena-policy, codec, readback or internal contract failure |

Errors attempt the exact line `layout_records: operation failed\n` using at
most eight stderr write attempts. A failed diagnostic preserves the primary status. SIGPIPE is
ignored before I/O; setup failure returns 5 without a diagnostic. Successful
runs have no stderr output.

## Target and acceptance

All three registered application groups passed in one 7.32s run after a
1.89s driver build, totaling 58 unique native cases:

| Accepted group | Cases | Evidence directory |
| --- | ---: | --- |
| Model | 20 | `/tmp/layout-records-model-6t0qni1e` |
| CLI | 28 | `/tmp/layout-records-cli-brho61zj` |
| I/O | 10 | `/tmp/layout-records-io-d9y3fc6a` |

The receipt is `target/stdlib-work/layout-records-first.log`: three tests
passed with no filtered tests. The registered driver compiled through the GPU
compiler, required an actual ELF64 x86-64 executable and passed the shared
strict jump admission gate before native Linux x86_64 CPU execution, using
existing allocator and descriptor services. GPU-device execution and other
backends remain unverified. Arena backing/alignment and byte-view lifetime
remain public library contracts, not consequences of layout arithmetic.

Executed application source SHA-256:
`194ca89cebd16151f0c3385169b5881b9ba09f60d8920e3164cf15b1d10ab6f2`.
Oracle SHA-256:
`8a239e7827ead3d73d6b5fb0bb2e71e15c64b71f7a158e8a40df840fcbb3b171`.

The independent test-only oracle computes each field byte's contribution
directly from integer significance and physical position, without importing
the production layout/arena/endian implementation. Literal record-zero and
record-one bytes check the model separately. Executed models cover zero,
singleton and small counts, 64/256-record boundaries, 65535/65536 records,
leading zeros and exact 64-byte COUNT spellings. The final record at the
maximum count exercises full-width serial/value bits. Zero-count evidence
observes no retained arena mapping.

The CLI group checks sole help, missing/extra/mixed arguments, strict unsigned
decimal syntax, signs/space/non-ASCII, range/overflow and argument byte caps.
All application children receive directory stdin; complete traces reject
read calls, checking that the program does not consume input.

The I/O group reaches three selected ENOMEM sites: both argv allocations and
the arena chunk. Each returns 4 with empty stdout. Complete traces require
explicit successful same-address/same-size releases for observed successful
mappings; the baseline observes arena release before stdout and permits argv
owners to remain until argument handling returns. These are finite observations,
not exhaustive allocation-failure, automatic-lifetime or leak-freedom claims.

Output checks include actual closed data/help stdout, EIO, one EINTR followed
by the exact report, SIGPIPE setup failure and a 64-attempt interruption cap.
The compact interruption summary records 64 output errors plus one successful
stderr diagnostic; it does not observe allocation cleanup. No successful
transfer count is fabricated. This small-report suite does not claim an actual
positive partial report write. Internal layout/readback failure injection,
general lifetime/aliasing safety and formal verification remain outside these
receipts.

See `tests/fixtures/stdlib_execution/layout_records/README.md` for retained
commands and detailed scope, and `tests/stdlib_layout_records_execution.rs` for
the registered driver. Whitespace-only driver formatting after these receipts
does not represent a native rerun. With a warm build and configured GPU,
reproduce using:

```sh
timeout --kill-after=2s 100s flock -w 95 target/stdlib-work/library-gpu.lock \
  env CARGO_TARGET_DIR=target/stdlib-build LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=70000 \
  cargo test --test stdlib_layout_records_execution -- --nocapture --test-threads=1
```

Production is entirely Lanius and adds no compiler, runtime ABI, proof or host
service. No Rust/Python library implementation, JSON transport or Wasm
dependency is introduced. See the [layout plan](library-layout-plan.md) for
the separate layout arithmetic and arena-consumer contracts.
