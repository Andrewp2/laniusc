# Raw DEFLATE encoding

`ext::deflate` compresses arbitrary byte views into raw RFC 1951 streams. The
implementation is entirely Lanius, allocates nothing and calls no host service.
It emits actual length/distance backreferences. Repetitive input compresses;
incompressible input falls back to stored blocks.

Executable evidence covers **x86_64 Linux using the GPU compiler to produce
native executables**. GPU-kernel execution and other targets are unverified.
Use [`ext::compression`](extended-compression.md) for owned output, zlib or gzip
containers, and [`ext::inflate`](extended-inflate.md) for raw decoding.

The [resumable encoder](extended-streaming-deflate.md) adds fixed 32 KiB block
storage, retained pending bytes and chunk-invariant progress through the same
block helpers. All five streaming library groups pass on the finite native profile.
The APIs and historical
receipts below describe the whole-input policy.

## Caller storage and API

```lanius
pub enum Error { Bounds, ScratchTooSmall(i32), Capacity(i32), SizeOverflow }
pub fn scratch_len() -> i32;
pub fn encoded_len(input: core::slice::View<u8>,
                   scratch: core::slice::View<i32>) -> core::result::Result<i32, Error>;
pub fn encode_into(input: core::slice::View<u8>,
                   output: core::slice::View<u8>,
                   scratch: core::slice::View<i32>) -> core::result::Result<i32, Error>;
```

`scratch_len()` is **32768 i32 elements**, independent of input length. The
first 32768 logical elements are reset on every call; their previous contents
have no meaning. A larger scratch view is accepted, and elements after the
required prefix are preserved. Packed raw i32 scratch uses 128 KiB. Native
arrays and packed views can have different physical strides; normal slice
indexing preserves either representation.

The caller owns every buffer. Input, output and scratch must have disjoint
physical backing for the duration of a call. Input must remain unchanged while
the function runs. Views must point into live storage containing at least
`start + length` elements with their established strides. The API validates
logical metadata; it cannot discover backing capacity, dangling pointers or
overlap. No ownership is transferred and no destructor is needed.

`encoded_len` returns the exact compressed byte count and modifies scratch.
`encode_into` performs its own size pass, validates output capacity, then writes
exactly the returned number of bytes at `output.start`. Extra output capacity
is preserved. A call with the same input produces the same bytes regardless of
prior scratch contents. The final byte's unused high bits are zero.

A caller can measure, allocate the returned count, and encode. A caller that
already has enough output storage can call `encode_into` directly. The bound

```text
n + 5 * max(1, ceil(n / 65535))
```

is sufficient whenever the expression fits the caller's capacity type. Use
widened arithmetic when calculating it. Successful output may be much smaller;
an empty input uses two bytes, `03 00`. A logical input length of zero still
requires the full scratch view.

## Failure behavior

| Error | Meaning |
| --- | --- |
| `Bounds` | Any view has negative start or length, or `start + length` exceeds i32 |
| `ScratchTooSmall(32768)` | Metadata is valid but scratch has too few elements |
| `Capacity(required)` | Output has less than the exact required byte count |
| `SizeOverflow` | The smaller selected encoding cannot be represented by i32 |

Metadata validation precedes scratch validation. Measurement precedes capacity
validation. **Every returned error preserves all output bytes.** Scratch may
change on a size or capacity failure. Input is always read-only. Arithmetic for
bit counts and the stored representation uses u64 before checking the public
i32 result. Physical storage violations and overlapping buffers violate the
caller contract and are outside these error guarantees.

The tests exercise malformed metadata and exact capacity failures, including
empty, fixed-Huffman and stored-output selections. They do not allocate a
multi-gigabyte input to execute the final `SizeOverflow` branch.

## Compression profile

The wire representation follows [RFC 1951 sections 3.1.1 and
3.2.3–3.2.6](https://www.rfc-editor.org/rfc/rfc1951): least-significant-bit
field packing, canonical fixed Huffman codes, and stored blocks with complemented
16-bit lengths. Matches use lengths 3–258 and distances 1–32768, including
overlapping matches.

The encoder uses a 32768-entry table keyed by three input bytes. At a position
it checks the most recent candidate for that hash, verifies the actual bytes,
and takes a greedy match when its fixed-code cost saves bits. Every consumed
position with three remaining bytes is inserted. Hash collisions can discard
useful candidates and reduce compression; they cannot produce incorrect data.

The bounded most-recent-candidate policy is informed by
[zlib's `FASTEST` hash insertion and `deflate_fast`
implementation](https://github.com/madler/zlib/blob/develop/deflate.c).
This implementation chooses its own hash and inserts positions throughout a
match. It has no hash chains or lazy match search.

For the complete input it measures one fixed-Huffman block and the stored
representation, including final padding, and selects the smaller byte count.
Ties select fixed Huffman. Stored blocks hold at most 65535 input bytes each.
Fixed output is one final block, and matches can refer anywhere in its allowed
window. Both alternatives represent every input byte and have a final block.

This whole-input policy does not emit dynamic Huffman trees, choose blocks
independently for mixed data or accept preset dictionaries. The separate
[streaming policy](extended-streaming-deflate.md#deterministic-block-policy)
chooses each 32 KiB block independently and retains state across calls.
Ordinary DEFLATE decoders can read
the resulting streams; the decoder has broader block support than this encoder
needs to emit.

Work is O(n + 32768) per pass, with constant-size scratch. A candidate shorter
than three bytes stops after at most three comparisons; rejected three-byte
matches also have constant cost. Longer accepted matches consume their compared
span. Length/distance coding has a fixed bounded number of steps. There is
no recursive search or attacker-controlled chain length. `encoded_len` performs
one pass. `encode_into` measures then emits, with another matching pass for
fixed output or a copying pass for stored output.

## Executable evidence

`tests/extended_deflate_execution.rs` runs compiled Lanius programs and uses
the system zlib decoder solely as an independent test oracle. Production
Lanius code has no foreign codec dependency. The historical six-group receipt
below predates the shared block-helper streaming change; selected current
regressions belong in the [streaming guide](extended-streaming-deflate.md).
Its original scope covers:

- 644 empty, byte, generated binary, text, periodic, small-alphabet and mixed
  inputs, including all eight ending-bit positions and zero final padding.
- Every match length from 3 through 258, every literal byte, and distance-code
  boundaries through 32768. A separate bit reader confirms real matches occur.
- Stored block boundaries at 65534, 65535, 65536, 131070 and 131071 bytes,
  plus 512 KiB incompressible input; exact output sizes and complemented lengths.
- Exact capacity, preserved guards, malformed views, native strided arrays,
  selected input/output/scratch offsets and arbitrary prior scratch state.
- Allocation-failure injection with no mmap, munmap or brk calls during
  encoding, and no host services during the pure contract program.
- Larger 512 KiB inputs with bounded process deadlines and independent decoding.

The final complete six-group run passed in 9.88 seconds. Subsequent additions
to the contract and generated-input groups were rerun separately. Run the
focused suite from the repository root with an existing compiler build:

```sh
timeout --kill-after=2s 100s env \
  CARGO_TARGET_DIR=/home/andrew-peterson/code/laniusc/target/stdlib-build \
  CARGO_INCREMENTAL=0 CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --locked --test extended_deflate_execution -- --nocapture
```

## Native measurements

Measured on 2026-10-23, AMD Ryzen 9 5950X, Linux x86_64, pinned to CPU 8.
These are historical whole-input measurements, not measurements of the
resumable encoder or its current shared-helper revision.
The compiler base was `441e66f9`. The native batch fixture's `encode-only`
mode calls `encode_into` once per record, without a separate `encoded_len` call.
One warm run preceded five measured runs, alternating case order. Times include
process startup, fixture stack initialization, framed stdin/stdout and Python
subprocess transport. Reference decoding and input generation were outside the
timed interval. Other agents were active on the same machine.

| Input | Bytes in | Bytes out | Median ms | Min–max ms |
| --- | ---: | ---: | ---: | ---: |
| Deterministic random | 16384 | 16389 | 7.242 | 6.270–7.346 |
| Repeated `x` | 16384 | 107 | 6.625 | 5.679–7.719 |
| Repeated text records | 16384 | 160 | 6.744 | 6.122–7.068 |
| Deterministic random | 524288 | 524333 | 117.424 | 94.514–126.792 |
| Repeated `x` | 524288 | 3306 | 90.007 | 76.861–91.289 |
| Repeated text records | 524288 | 4098 | 90.514 | 79.174–95.027 |

The text record is `data=123456789\tstatus=success\n`. Random bytes come from
xorshift64 with shifts 13, 7, 17, starting at `0x1234abcd8765fedc`; the 16 KiB
random input is generated before the 512 KiB input from the same state. These
are native behavior and scale observations, not a comparison with another
compiler or codec. The small-input times include fixed fixture startup costs.

The batch fixture accepts repeated little-endian u32-length frames followed by
raw bytes, and emits the same framing around compressed data. Its optional
argument selects encode-only mode. That framing is a test harness, not a public
library transport or file format. It limits each test input to 512 KiB to keep
its native stack buffers within the usual process stack limit; the library
itself has the i32 length contract described above.
