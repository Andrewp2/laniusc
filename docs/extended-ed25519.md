# Ed25519

`ext::ed25519` provides allocation-free Pure Ed25519 key derivation,
deterministic signing and signature verification, following
[RFC 8032 section 5.1](https://www.rfc-editor.org/rfc/rfc8032.html#section-5.1).
The original Lanius implementation uses `core::sha512`, fixed field and
scalar arrays, and no external cryptographic backend or 128-bit primitive.
Ed25519ctx, Ed25519ph and Ed448 are separate algorithms outside this API.

```lanius
pub enum Error {
    Bounds, InvalidSeedLength, InvalidPublicKeyLength, InvalidSignatureLength
}
pub struct Key32 { bytes: [u8; 32] }
pub struct Signature64 { bytes: [u8; 64] }
public_key(seed: View<u8>) -> Result<Key32, Error>
sign(seed: View<u8>, message: View<u8>) -> Result<Signature64, Error>
verify(public: View<u8>, message: View<u8>, signature: View<u8>)
    -> Result<bool, Error>
```

The seed and public key are exactly 32 bytes; a signature is exactly 64.
A seed is the RFC seed, rather than an expanded secret or libsodium's
64-byte secret-key representation. All logical views are checked before
any size check or byte access: starts and lengths must be nonnegative,
and their sum must fit `i32`. Seed size is checked next for signing;
public-key size precedes signature size for verification. Invalid logical
metadata returns `Bounds`; wrong exact sizes return the corresponding
length error. A valid empty message may have any logically valid start.

Callers supply physical backing for every nonempty logical range, including
the slice's actual stride, and keep it immutable throughout each call.
The API cannot validate physical pointers or backing sizes from a view.
Inputs are not retained or changed. Returned key and signature byte arrays
are independent inline values, with ordinary value-copy semantics and no
destructor. To construct a view, first bind `let values: [u8] = key.bytes;`
and then use `View { values: values, start: 0, length: 32 }`.

## Signing

The 32-byte seed is hashed using SHA-512. Only the lower half used for
the secret scalar is pruned: the lowest three bits are cleared, bit 254
is set and bit 255 is cleared. The public key is its base-point multiple.
The upper hash half and the complete message determine the deterministic
nonce through SHA-512. The signature challenge hashes the encoded nonce
point, public key and complete message. Both 64-byte hashes are reduced
modulo the full group order; neither nonce nor challenge is pruned.
The result is `R || little_endian((r + k*a) mod L)`.

There is no context, `dom2` prefix or implicit prehash in this Pure Ed25519
API. Signing a SHA-512 digest with `sign` remains Pure Ed25519 over that
digest; it does not implement Ed25519ph. This distinction also applies to
[libsodium's multipart signing interface](https://doc.libsodium.org/public-key_cryptography/public-key_signatures).

## Verification policy

For valid input lengths, cryptographic invalidity returns `Ok(false)`.
Verification requires all of the following:

- `S < L`, where `L = 2^252 + 27742317777372353535851937790883648493`.
- Canonical encodings of both public point `A` and signature point `R`:
  the encoded `y` is below `p = 2^255-19`, a square root exists on the
  curve, and the sign bit is zero if the recovered `x` is zero.
- A nonidentity public key in the prime-order subgroup: `[L]A = identity`
  and `A != identity`. All nontrivial torsion and mixed-order keys reject.
- `R` is in the prime-order subgroup: `[L]R = identity`. A canonical
  identity `R` is allowed. Other torsion and mixed-order `R` values reject.
- The exact equation `[S]B = R + [k]A`, with
  `k = SHA512(encoded_R || encoded_A || message) mod L`.

These rules deliberately choose a policy at the cofactor boundary. RFC
8032 permits a cofactored verification equation, which can admit points
excluded here. Libsodium's detached verification behavior varies by
version; its published point-validation contract requires canonical
main-subgroup points and excludes small-order points, while its current
documentation also warns of mixed-order checks in older versions.
See [libsodium point validation](https://doc.libsodium.org/advanced/point-arithmetic)
and the [detached verifier source](https://github.com/jedisct1/libsodium/blob/master/src/libsodium/crypto_sign/ed25519/ref10/open.c).

Allowing identity `R` preserves the valid zero-nonce case: a nonce hash
can reduce to zero, and `sign` must still produce a signature accepted
by `verify`. A constructed positive test uses known secret scalar one,
`A=B`, `R=identity` and `S=k`. Libsodium rejects this small-order `R`,
so the independent group model determines this API's expected result.
The implementation does not claim to accept every signature admitted
by the RFC's cofactored equation or every library's verification policy.

## Arithmetic bounds and schedules

Field values use 16 radix-2^16 `u64` limbs. Stored results are canonical:
limbs 0–14 are below 65536 and limb 15 is below 32768. The original field
arithmetic is shared in design with `ext::x25519`, copied privately into
this module. Addition is componentwise; subtraction forms `a+2p-b`, so
all coefficients stay nonnegative. A multiplication coefficient sums at
most 16 products below 2^32 and is below 2^36. Folding at degree 16 uses
`2^256 = 38 mod p`, leaving lower coefficients below 2^42 and the top
below 2^37. Multiplication by two stays below 2^17.

Three fixed carry passes normalize each field result. After the first,
the low limb is below 2^28 and the other limbs meet their radices. The
second can produce at most one wrap at the top; the third resolves its
addition of 19 to the low limb. The result is below 2^255. One radix
subtraction and a mask select the canonical value below `p`. The added
radix 65536 makes subtraction temporaries nonnegative, with borrow in
`{0,1}`. All intermediate field arithmetic fits in `u64`.

Curve points use extended homogeneous coordinates `(X,Y,Z,T)` with
`XY=ZT`. Complete addition and specialized doubling use RFC 8032's
formulas. Every scalar multiplication executes exactly 256
double/add/select steps. A scalar bit controls only limb-selection masks;
no secret digit indexes a point table. Encoding uses fixed-exponent
inversion. Public point decoding uses the RFC square-root formula with
exponent `(p-5)/8 = 2^252-3`, checking the root and its sign explicitly.

Scalars use 16 radix-2^16 limbs modulo `L`. Fixed binary reduction starts
each step with `r<L`, shifts in one bit to get `2r+bit<2L`, then uses one
masked subtraction to restore `r<L`. Its limb temporaries are below 2^17.
The reduction processes all 512 bits of a nonce or challenge hash, or
all 256 bits of a pruned seed scalar. Multiplication and nonce addition
use 32 coefficients, each below `16*2^32+2^16 < 2^37`; normalization
adds a carry below 2^21. Since both multiplicands and the addend are
below `L`, the result fits 512 bits before reduction. No arithmetic
depends on a machine integer wider than `u64`.

This specifies source schedules and addresses for secret-dependent work.
Verification branches on public encodings and group checks. It does not
establish constant-time generated machine code, cache behavior, stack
erasure or resistance to physical side channels. Secret seed, expanded
hash and scalar copies may remain in stack storage after return.

## Focused verification

All five focused gates passed on **x86_64 Linux native executables generated
by the GPU compiler**, with strict ELF checks and empty allocation traces.
The driver is `tests/extended_ed25519_execution.rs`.

| Exact test | Accepted evidence | Elapsed |
| --- | --- | ---: |
| `ordinary_consumer_without_error_variant_projection` | Fixed RFC key/signature answers and independent retained signatures without projecting the error enum | 4.80 s |
| `rfc8032_all_pure_vectors_key_sign_verify_both_layouts` | 30 commands: all five section 7.1 vectors, complete keys/signatures and verification in both layouts | 6.60 s |
| `deterministic_libsodium_messages_padding_layouts_and_independent_copies` | 74 commands: deterministic signing, SHA-512 boundaries, independent returned-value copies and input mutation | 8.52 s |
| `canonical_subgroups_identity_nonce_and_scalar_malleability` | More than 150 policy cases: ordinary generated positives, all torsion cosets, canonical/off-curve boundaries, strict subgroups, identity nonce and scalar boundaries | 10.23 s |
| `every_signed_component_byte_mutation_and_bounds_precedence` | 206 commands: 160 component-byte mutations and 46 logical-bounds/length-priority cases | 13.78 s |

These were **five separate exact test invocations**, each compiling its
own ELF: one ordinary consumer and four protocol executables. They were
not a single full-suite invocation. The fresh resume Rust driver build
took 0.20 s; its log is `build-resume-foundations.log`. Earlier builds
and the executed source snapshots were unchanged.

The protocol checks native scalar-array and packed-byte physical layouts
at nonzero offsets, preserves every input and guard cell, and emits
complete results. Each protocol invocation reuses its compiled ELF and
splits records into batches of 24 with a 45-second native-process bound;
each independent oracle process has a 35-second bound.
Every native process is traced for `mmap`, `mremap`, `munmap` and `brk`;
all admitted traces were empty.

Expected bytes come from the fixed
[RFC 8032 section 7.1 vectors](https://www.rfc-editor.org/rfc/rfc8032.html#section-7.1),
installed libsodium's seeded key/signature API, and a separate Python
bigint model using three-coordinate homogeneous group arithmetic.
That model uses a different addition representation from production's
four-coordinate formulas, ordinary integer reduction, independent
SHA-512, and explicit subgroup/equation checks. It also constructs an
exact-equation mixed-order forgery which subgroup admission must reject.
Libsodium determines ordinary signing results; the documented group
policy determines adversarial acceptance. Python and Rust are test
orchestration only, and are not part of the Lanius production module.

Local ignored logs are under `target/stdlib-work/tls-auth-admission/`:
`ed25519-ordinary.log`, `ed25519-rfc.log`, `ed25519-model.log`,
`ed25519-policy.log` and `ed25519-mutations.log`. The admitted driver
basename was `extended_ed25519_execution-f98b2d64d2de34c8` in
`target/stdlib-build/debug/deps/`; a fresh build can produce another name.

This evidence covers the enumerated contracts and messages through 2048
bytes in the protocol, rather than exhaustive keys, messages or signatures.
It does not verify other target architectures or user GPU kernels; GPU
execution here refers to the compiler. The API's manual physical-backing
contract, documented subgroup-policy differences, and lack of generated
constant-time or stack-erasure guarantees remain applicable. The recorded
times include test orchestration and compilation and are not isolated
cryptographic throughput measurements.
