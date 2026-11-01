# Native endian independent bit/byte model

This fixture exercises all 24 additions in the
[native byte-order contract](../../../../docs/library-native-endian-plan.md):
big/little-endian reads with fallback and writes for `u64`, `i16`, `i32`,
`i64`, `f32` and `f64`. Production remains Lanius. Python and the binary
adapter are test infrastructure only.

## Independent directions

Read input bytes are supplied directly by Python. The producer calls the
selected public reader and reports its exact specified-width bits. A separate
buffer receives an unrelated write value through the public writer, and the
producer reports every resulting byte. Python compares reads with
`int.from_bytes` and writes with integer `to_bytes`, including all surrounding
sentinels and the complete unchanged read buffer. A pair of symmetric wrong
read/write implementations cannot pass through a matching round trip.

No Python floating values or floating arithmetic are used. IEEE values remain
unsigned integer words throughout generation and comparison. The Lanius
adapter uses only `core::f32` / `core::f64` `from_bits` and `to_bits` for float
transfer, preserving the expected signaling/quiet distinction and payloads.
Signed integer results are observed as their specified-width two's-complement
bits, and write/fallback inputs are constructed with explicit width casts.

## Finite corpus

There are **16,032 cases**, using seed `0xe0d1a0261030`, with both byte orders
and two backing layouts: native descending-byte arrays and packed ascending
byte storage. Cases include zero/nonzero offsets, exact-width ranges, final
valid positions and surrounding initialized bytes.

| Family | Cases |
| --- | ---: |
| Edge bit patterns at four valid field locations, both orders/layouts | 7,552 |
| Edge fallback patterns at ten invalid metadata shapes, both orders/layouts | 4,640 |
| 160 seeded raw-bit datasets per type, both orders/layouts | 3,840 |

Overall there are 10,624 admitted and 5,408 rejected cases. Type counts are
`u64=3152, i16=1616, i32=2128, i64=3152, f32=2992, f64=2992`.
Every type/order read and write selector is exercised in both layouts.

Integer edge sets include each isolated bit and each corresponding clear-bit
mask, both alternating-byte patterns, ascending/descending byte patterns,
zero, signed extrema and high-half-only/full-width values. Both float widths
include both signs of zero, subnormals, normals, infinities, quiet NaNs and
signaling NaNs. Multiple payloads and values at the subnormal/normal and
normal/infinity boundaries are included. CPU corpus checks require every one
of those signed categories independently for binary32 and binary64 in direct
reads, direct writes and rejected-read fallbacks.

Invalid metadata covers negative/extreme logical lengths and offsets, short
fields, one byte beyond the final valid start, and large positive offsets near
`i32::MAX`. Rejected reads must preserve the fallback bits exactly; rejected
writes must return false and preserve the whole destination. Every admitted
field is physically backed. Physical overclaim traps and invalid reads over
unbacked storage belong to separate contract fixtures; this model does not
infer absence of all backing reads from an unchanged read buffer.

## Protocol and acceptance

Each case is 96 bytes: eight little-endian `u64` words for type, order, layout,
claimed logical length, offset, write bits, fallback bits and identity, then
32 read-buffer bytes. Signed metadata uses two's complement. The producer
admits the finite type/order/layout selectors and initializes an independent
write buffer. The oracle bounds every raw word to its specified width.

Each output case contains 69 words: type, order, layout, observed read bits,
write Boolean, all 32 read-buffer bytes and all 32 write-buffer bytes. The
oracle checks every word and rejects truncation or extra output. Failure
diagnostics include the full case and deterministic seed.

CPU controls pass, including manual u64/signed/IEEE vectors. Six deliberate
corruptions of high read bits, byte order, an unselected write guard, read-only
storage, the write result and a signaling-NaN fallback are rejected.

The registered Rust gate is
`independent_native_endian_models_preserve_bits_bytes_bounds_and_strided_sentinels`
in `stdlib_native_endian_model_execution`. It uses shared strict x86 ELF
checks and one batched native process, with an 85-second outer timeout and
a 70-second child timeout. Executable target: native Linux x86_64 CPU
output from the GPU compiler. This finite model supplies no direct GPU,
arbitrary physical-memory, allocation-trace or formal verification claim.

The first registered runtime run passed: **one test and all 16,032 cases in
6.96 seconds**, covering all 24 additions, both layouts and both byte orders,
with seed `0xe0d1a0261030`. The log is
`target/stdlib-work/native-endian-model-first.log`; its exact summary is
`native-endian cases=16032 functions=24 layouts=2 orders=2 seed=0xe0d1a0261030`.
This finite result establishes the described bit/byte observations for native
Linux x86_64 output from the GPU compiler, including the selected signaling NaN
payloads and invalid fallbacks. It does not establish another target's exact-bit
value-transfer behavior.

Tested SHA-256 identities:

| Source | SHA-256 |
| --- | --- |
| `stdlib/core/endian.lani` | `3f00b73670d1b388bd3a91efd01bd02077f7b116efdd945dd13a8bb4e165cb3a` |
| `model.lani` | `5a9c5a70b3f33150bfba5c55a69ccfc263fa89c66eef65e30d88d6c328bafe44` |
| `oracle.py` | `75c46ec1fc221f8f7e08bba29dae6c38aee8a1b2dc254ef3d11f7d6e66801e57` |

```sh
python3 -B tests/fixtures/stdlib_foundation/native_endian_model/oracle.py controls
python3 -B tests/fixtures/stdlib_foundation/native_endian_model/oracle.py /path/to/model
```
