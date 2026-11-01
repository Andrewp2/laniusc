# Native varint independent wire model

This fixture checks u32/u64/i32/i64 `core::varint` reads, writes, lengths and
ZigZag helpers against independent wire and integer references. Production
remains Lanius; Python and binary framing are test infrastructure only.

## Independent expectations

The writer reference repeatedly divides an unbounded integer by 128 to obtain
wire digits. Signed inputs use the mathematical ZigZag bijection: `2*x` for
nonnegative x and `-2*x-1` for negative x, including signed minima. Expected
length is calculated from bit length. Readers find the first terminator within
the allowed five/ten-byte window, reconstruct the integer with base-128 powers,
check its width and independently re-encode it to test shortest-wire admission.
This avoids reproducing unsigned ZigZag bit masks, terminal-zero guards or
bounded accumulator shifts.

Reads are checked against independently supplied wire bytes. Writes are checked
against exact expected bytes over an unrelated initial backing, beyond an
encode/decode roundtrip. Every case also observes len/ZigZag functions on a
scalar independent of the decoded wire. Values/errors, BufferTooSmall's full
required length, View-relative next offsets and all 32 backing bytes are checked.
Readers preserve backing; insufficient writers preserve all bytes atomically.

Four start/offset profiles make wire bytes begin at backing index four while
varying absolute View start and relative offset. Truncated Views can have the
missing canonical suffix physically present beyond their logical end, so using
backing capacity in place of View length is detected. Native descending and
packed ascending byte backings are covered. Native magnitude is not assumed;
packed stride must be +1. Logical metadata does not establish physical backing.

## Finite corpus

There are **61,144 distinct cases**, seed `0xa71a0261102`, comprising **52,662
reads / 8,482 writes**:

| Native integer type | Cases |
| --- | ---: |
| u32 | 13,753 |
| u64 | 16,801 |
| i32 | 13,761 |
| i64 | 16,829 |

The wire corpus includes every one-byte input under all four types and both
strides, and every one of the 32,768 two-byte prefixes whose first byte requests
continuation. Each two-byte prefix occurs once, assigned across the four types,
two strides and offset profiles; this is not a claim that every prefix is
repeated under every combination. Every final byte 0..255 is tested at the
fifth/tenth position after both zero and maximal payload prefixes, under every
type and both strides, with and without an extra terminator beyond the limit.

Known examples include 0, 127, 128, 300, unsigned maxima, overlong zero and
nonzero values. The value corpus combines every bit's neighborhoods, full signed
and unsigned extrema and 128 generated full-width words per type. Each value
checks every insufficient writer capacity, exact and spare capacity, every
reader truncation, the canonical wire and ignored trailing bytes. Negative,
overflowing, empty and out-of-range metadata/offset cases test Bounds precedence
over capacity/truncation. Deduplication excludes repeated full input tuples.

Reference outcome classifications are 23,008 successes; 176 Bounds; 6,226
BufferTooSmall; 23,642 Truncated; 7,916 Overflow; and 176 NonCanonical. CPU
controls check literal known wire, independent signed extrema, maximum-width
continuation/payload precedence, noncanonical final zero, relative next and
atomic short writes. Eight deliberate corruptions of decoded value, next,
required capacity, atomic backing, error precedence, ZigZag sign and guard
preservation are rejected. No statistical or unbounded exhaustive claim is made.

## Protocol and acceptance

Requests have eight little-endian u64 header words and at most twelve byte
words. The header selects read/write, native type, layout, View start/length,
relative offset, scalar bits and payload length. The adapter uses typed
`Result<Decoded<T>,Error>` for all four reader results. Each response has twelve
words for result, len/ZigZag and stride observations, then the complete backing.
Errors expose no synthetic partial value/next. The oracle checks exact framing
and reports the complete case, index and seed on mismatch.

The native gate passed on its first attempt: **1 registered test in 6.12s**,
after a 1.70s Rust test-driver build, reporting **61,144 cases / 4 integer
types / 2 byte layouts** at seed `0xa71a0261102`. The receipt is
`target/stdlib-work/native-varint-model-first.log`. Exact wire, typed decoded
values, relative offsets, scalar helpers, errors and entire backing states
execute against the reference, beyond compilation. Reference family/outcome
classifications above describe the finite corpus; they are not separate native
runtime coverage counters.

The registered test is
`independent_varint_wire_models_match_all_widths_errors_and_atomic_backing`
in `stdlib_varint_model_execution`. It checks executable ELF admission and
shared strict x86 jumps, then runs one batched native process with a 90-second
outer timeout and 75-second child timeout. Accepted scope is finite Linux
x86_64 CPU output produced by the GPU compiler. Physical access boundaries,
pure-phase host effects and real consumer programs have separate gates. No
GPU-device, arbitrary-target or formal verification guarantee is claimed.

Frozen tested identities (SHA256):

| Source | SHA256 |
| --- | --- |
| `stdlib/core/varint.lani` | `a0ef8c9ff2c5fc83fb8449c6baeaff4f24d9c3a0f32b962b68dfc11efbcc147b` |
| `model.lani` | `a79793024965b34b4dd4f03ecce78c7f45c0b929080585a7cecba99cf3876878` |
| `oracle.py` | `23f89c4402c25fc882b739f415453e7af9d55dba09395ea8b665bf166b0801f9` |

```sh
python3 -B tests/fixtures/stdlib_foundation/native_varint_model/oracle.py controls
cargo test --test stdlib_varint_model_execution independent_varint_wire_models_match_all_widths_errors_and_atomic_backing -- --nocapture
```
