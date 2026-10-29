# Checked Base64 independent profile model

This fixture checks all four `core::base64` APIs under Standard,
StandardUnpadded, UrlSafe and UrlSafeUnpadded against independent canonical
wire expectations. Production remains Lanius. Python's Base64 library and
binary framing are test infrastructure only.

## Strict independent oracle

RFC 4648's literal empty/f/fo/foo/foob/fooba/foobar vectors anchor host encoding.
Generated binary values are compared directly with `base64.b64encode`, using
the selected alphabet and explicit padding policy. Decoding does not rely on
permissive host admission: an independent left-to-right grammar checks profile
lengths, alphabet bytes and allowed padding positions first. Third-position
padding with a nonpadding fourth byte reports the third index. Only after that
policy is admitted does validated host decoding run, and a mandatory canonical
host re-encode must match the original wire exactly. This detects unused-tail
bits instead of copying the implementation's sextet-bit guards.

All error kinds and indexed payloads are compared exactly. Indices remain
relative to input.start. Both View metadata checks precede conversion errors;
encoding checks complete capacity before conversion, and decoding validates the
complete wire before capacity. Length-only operations validate their own inputs,
without inventing output metadata requirements. Arbitrary-precision length
arithmetic checks exact positive i32 limits without constructing huge backing.

Every response includes both complete 80-byte backings. Recoverable failures
preserve both, readers preserve input, and successful disjoint writes change
only the required target prefix. Functional cases vary input and output starts
independently. Native descending and packed ascending bytes run in all four
source/output combinations; no native magnitude is assumed. Exact same-first-
address aliases share the backing and stride, with sufficient physical backing.
Other partial overlaps are outside this model and the public preconditions.

## Finite corpus

There are **48,995 distinct cases**, seed `0xba5e640261102`:

| API | Cases |
| --- | ---: |
| encoded_len | 288 |
| decoded_len | 5,989 |
| encode_into | 13,688 |
| decode_into | 29,030 |

Profile counts are 12,870 Standard, 11,627 StandardUnpadded, 12,870 UrlSafe and
11,628 UrlSafeUnpadded. Identical complete input tuples are deduplicated.

Binary corpora cover every length 0..48 with varied sequential, zero, maximal
and seeded binary patterns, plus RFC and alphabet-sensitive vectors. Normal
wire cases cross profiles, all four stride combinations, shifted Views, exact
and spare capacities and short-capacity boundaries. Every byte 0..255 replaces
every position in selected one-/two-byte tails, full groups and alphabet-sensitive
anchors; every such mutation reaches decode_into with zero capacity, while a
defined subset also reaches decoded_len. Insertions/deletions, whitespace,
cross-alphabet symbols, padding shapes, noncanonical tails and multi-group error
indices supplement that corpus. It is not an exhaustive arbitrary-input claim.

There are **1,600 exact same-base cases**, including expanding encodes,
shrinking decodes, short capacity and malformed atomic rejection. The separate
physical boundary gate owns broader alias/unaligned-memory coverage. Scalar
length cases include negative lengths, i32 limits and padded/unpadded maximum
input boundaries. Metadata cases include empty, negative, overflowing and
large-start zero-length Views and ignored-output metadata for read-only APIs.

Reference outcome classifications are 17,571 successes; 424 Bounds; 16
LengthOverflow; 684 InvalidLength; 12,306 InvalidByte; 910 InvalidPadding; 936
NonCanonical; and 16,148 BufferTooSmall. CPU controls check literal RFC wire,
alphabet differences, exact length thresholds, tail bits, padding/byte/capacity
precedence, late relative indices and both directions of same-base conversion.
Eight deliberate corruptions of count, output bytes, capacity payload, atomic
backing, error precedence, indexed payload and alias writes are rejected.

## Protocol and acceptance

Each request has twelve little-endian u64 header words followed by at most
68 byte words, selecting API/profile, backing combination, alias policy, both
Views, scalar length argument and independently placed payload. Each response
has ten result/stride header words and both complete 80-byte backings. The
oracle checks exact framing, byte effects, errors and payloads and reports the
complete case, index and seed on mismatch.

The native gate passed on its first attempt: **1 registered test in 5.93s**,
after a 2.02s Rust test-driver build, reporting **48,995 cases / 4 profiles /
4 APIs / 4 source-output layout combinations** at seed `0xba5e640261102`.
The receipt is `target/stdlib-work/checked-base64-model-first.log`. This executes
all 1,600 exact same-base cases as part of the corpus, comparing complete
backing effects and recoverable rejection atomicity. Exact wire, indexed errors,
capacity and length outcomes execute against the reference, beyond compilation.
Per-kind counts above classify the finite reference corpus; the native summary
does not emit separate runtime coverage counters for each classification.

The registered test is
`independent_base64_profiles_match_canonical_wire_indexed_errors_and_atomic_backing`
in `stdlib_base64_model_execution`. It checks executable ELF admission and
shared strict x86 jumps, then runs one batched native process with a 90-second
outer timeout and 75-second child timeout. Accepted scope is finite native
Linux x86_64 CPU output from the GPU compiler. Physical access/host effects,
WebSocket consumers and real CLI faults have separate gates. No GPU-device,
arbitrary-target, cryptographic or formal verification guarantee is claimed.

Frozen tested identities (SHA256):

| Source | SHA256 |
| --- | --- |
| `stdlib/core/base64.lani` | `c5eb1fc4ee603adb8f681695a3dd22885008b76d37fb70d78ce013d95b1837e8` |
| `model.lani` | `9c43b8370e7a23ad9c9ccec79f082dd2df9a4e1aa463787515b5fa972a162b62` |
| `oracle.py` | `4e1e01cfeef2ee1a5da07d8645d228414ae00d1339cd4d9db488f97e4a754ed2` |

```sh
python3 -B tests/fixtures/stdlib_foundation/checked_base64_model/oracle.py controls
cargo test --test stdlib_base64_model_execution independent_base64_profiles_match_canonical_wire_indexed_errors_and_atomic_backing -- --nocapture
```
