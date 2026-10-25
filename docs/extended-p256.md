# P-256 public keys, ECDH and ECDSA verification

`ext::p256` implements portable, allocation-free P-256 (secp256r1) public-key
validation, scalar multiplication, ECDH and ECDSA verification. Production is
Lanius throughout, with fixed-width arithmetic and no BigUint, host crypto or
external-library fallback.

The profile follows [SEC 1 version 2.0](https://www.secg.org/sec1-v2.pdf), especially
sections 2.3, 3.2.2.1, 3.3.1 and 4.1.4; P-256 parameters come from
[NIST SP 800-186 section 3.2.1.3](https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-186.pdf).
ECDSA verification also follows
[FIPS 186-5 section 6.4.2](https://nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.186-5.pdf).
The internal Jacobian formulas correspond to the
[Explicit-Formulas Database's a=-3 Jacobian representation](https://www.hyperelliptic.org/EFD/g1p/auto-shortw-jacobian-3.html),
with explicit masked handling of exceptional inputs.

## API and encodings

Every input below is a `core::slice::View<u8>`. All methods return
`core::result::Result<..., Error>`.

| Function | Success value |
| --- | --- |
| `validate_public_key(encoded)` | `PublicKey { bytes: [u8;65] }` |
| `compress_public_key(encoded)` | `CompressedKey { bytes: [u8;33] }` |
| `public_key(private_key)` | `PublicKey` |
| `shared_secret(private_key, encoded)` | `SharedSecret { bytes: [u8;32] }` |
| `verify_digest(encoded, digest32, signature64)` | `bool` |
| `verify_sha256(encoded, message, signature64)` | `bool` |
| `parse_der_signature(der)` | `Signature { bytes: [u8;64] }` |

Private keys are exactly 32-byte **big-endian** integers satisfying
`1 <= d < n`. They are not clamped, reduced or generated internally. Public
keys accept SEC1 uncompressed `04 || x || y` (65 bytes) or compressed
`02/03 || x` (33 bytes). Public outputs are normalized to the uncompressed
form; compression is explicit. Coordinates are 32-byte big-endian integers.
Infinity, hybrid encodings, other prefixes, coordinates at least `p`, off-curve
points and compressed nonresidues are rejected. P-256 has prime group order and
cofactor one; a finite on-curve point therefore belongs to the prime subgroup.
No additional `nQ` computation is needed for these fixed parameters.

ECDH validates the supplied scalar and peer encoding on every call. It returns
the affine x coordinate as exactly 32 big-endian bytes, including leading zeros.
A valid shared coordinate equal to zero is accepted. This is a raw ECDH
primitive, not a KDF, peer authentication or a TLS key schedule.

ECDSA's raw signature is `r || s`, each 32-byte big-endian. Both values must lie
in `1..n-1`. Verification accepts both high and low `s`; no low-S-only rule is
imposed. `verify_digest` consumes **exactly 32 digest bytes**, with no implicit
hashing, padding, alternate digest size or truncation. `verify_sha256` computes
SHA256 of the supplied message exactly once. It adds no domain separator or
protocol framing. Callers must supply the intended message or digest.

DER conversion is separate from raw verification. `parse_der_signature` accepts
a bounded, minimally encoded DER SEQUENCE of two positive INTEGERs, at most
72 bytes. It rejects negative/zero integers, unnecessary leading zeros,
indefinite/long lengths, magnitudes exceeding 32 bytes, extra elements and
trailing bytes. One necessary sign-padding zero is accepted. Parsing checks
encoding, not `r,s < n`; an encoded positive value at least `n` can be converted
but will fail cryptographic verification.

## Errors, copies and backing

`Error` distinguishes `Bounds`, `InvalidScalarLength`, `InvalidScalar`,
`InvalidPublicKeyLength`, `InvalidPointEncoding`, `InvalidPoint`,
`InvalidDigestLength`, `InvalidSignatureLength` and
`InvalidSignatureEncoding`. All direct view metadata is validated before any
length/content access. Metadata errors therefore take priority over length or
cryptographic rejection. Physical backing remains a manual caller contract.

Validation/ECDH return explicit errors for invalid public points. Verification
returns `Ok(false)` for a malformed point of an accepted encoded length,
noncanonical/off-curve coordinates, invalid `r/s`, an infinity verification sum
or a failed equation. Wrong metadata and public/digest/raw-signature lengths
remain errors. DER syntax failures are explicit parser errors. A false result
never means a signature was partially accepted.

Outputs own inline arrays and remain independent of input lifetimes, later
calls, and mutations to other returned copies. Public record fields are not
unforgeable validation tokens: each operation accepts byte views and validates
public encodings again. Input backing must remain immutable for the call and
disjoint from live mutable state. Inputs and bytes outside their logical ranges
are not modified. No implicit destruction, secret erasure or protected-memory
contract is provided.

## Arithmetic and finite bounds

Internal numbers use eight least-significant-first digits, each below `2^32`,
stored in `u64`. Field and scalar arithmetic use separate fixed moduli `p` and
`n`, in Montgomery form with `R = 2^256`. Constants include the exact `R mod m`,
`R^2 mod m`, and `-m^-1 mod 2^32` values for each modulus. Curve b and generator
coordinates are stored in the field's Montgomery representation. This machinery
is private; caller-fabricated residues never enter it.

Schoolbook multiplication and REDC use 17 fixed scratch digits. Every inner
product-plus-digit-plus-carry is bounded by
`(2^32-1)^2 + 2*(2^32-1) = 2^64-1`, so the expression fits exactly in `u64`.
Normalized carry digits remain below `2^32`; propagation-only sums are below
`2^33`. Fixed propagation loops include every possible high carry cell.

REDC selects each digit to cancel the current low word. Its output represents
`(T + q*m)/R`, where `0 <= q < R` and `T < m^2`. Since `m < R`, that result is
below `2m`. One masked subtraction across the low eight digits plus a ninth
carry digit yields a canonical residue. Modular addition has the same `<2m`
bound. Subtraction uses explicit radix borrows and masked modulus addition;
its temporaries also fit below `2^33`. Raw digest and affine-x normalization
modulo `n` use one subtraction because their values are below `2n`. Public
coordinate/scalar admission checks happen before conversion and never silently
normalize an invalid key.

Points use Jacobian `x=X/Z^2`, `y=Y/Z^3`, with canonical infinity `Z=0`.
Doubling uses `a=-3`. General addition computes the ordinary formula and the
doubling candidate on a fixed schedule, then selects equal-point, inverse-point
and identity cases with masks. The ordinary formula itself is not claimed to
be complete. Scalar multiplication always executes 256 double/add/select steps;
no scalar bit controls a branch, loop bound, table index or address. Field and
order inversion use the fixed exponent `m-2`; compressed decoding uses the
fixed exponent `(p+1)/4` and checks the resulting square.

The scalar admission check branches on validity. Public point decoding and
signature verification may branch on public data. ECDH retains a final infinity
invariant check, which is false for every mathematically valid nonzero scalar
and finite admitted point. Source schedules and masks do **not** establish
constant-time machine code, side-channel resistance, fault resistance or
secret erasure. The compiler and target have not been audited for those claims.

Arithmetic work/storage is fixed by P-256. SHA256 message hashing is linear in
its validated view length, at most `i32MAX`; there is no separate work budget or
deadline in the message wrapper. Applications should bound their messages.
There is no signing, nonce generation, SHA384/P-384, RSA, certificate/path
validation or TLS integration in this module.

## Focused verification

All five focused gates passed on x86_64 Linux in **five separate exact
invocations**, each compiling a strict ELF. The accepted evidence comprises
five ELFs and 82 native processes with empty allocation traces. This is not a
single full-suite invocation.

| Gate | Exact-byte protocol commands | Native processes | Runtime |
| --- | --- | --- | --- |
| Ordinary published/copy consumer | — | 1 | 5.45 s |
| Published NIST/RFC vectors | 382 | 24 | 17.86 s |
| Affine/OpenSSL/exceptional model | 316 | 20 | 13.96 s |
| Component mutations | 350 | 22 | 17.67 s |
| Scalar/point/DER/metadata rejection | 240 | 15 | 6.48 s |

The four protocol gates executed 1288 commands in 81 native batches; the
ordinary consumer accounts for the remaining native process. The fresh Rust
driver build passed in 1.20 s. Production, driver, protocol, model and ordinary
fixture stayed unchanged throughout admission. The author prepared source and
oracles without Cargo, GPU or native test execution; root serialized all five
gates.

Logs are retained under `target/stdlib-work/p256-admission/`:

- `build-first.log`;
- `ordinary-first.log`;
- `published-first.log`;
- `model-first.log`;
- `mutations-first.log`;
- `invalid-first.log`.

The admitted executable is
`target/stdlib-build/debug/deps/extended_p256_execution-939d78f4388ec548`.
The frozen source SHA256 identities are:

| Source | SHA256 |
| --- | --- |
| `extended/ext/p256.lani` | `12eb39bb540034709ff77e849172bb30b210afb131a969a9a698fb5af0570514` |
| `tests/extended_p256_execution.rs` | `90464ad1016b3120e7c327b446ee56c24ebab91ea47916f08d8791048a2925b1` |
| `tests/fixtures/extended/p256/plain.lani` | `4f3f69eeecdc1dbb0bbcc8663bc90f06e5870b41f5884d383dcb9e79bc63a575` |
| `tests/fixtures/extended/p256/protocol.lani` | `f5c1faecee292fcf469ff5682b581036f6b9801b30f86372b18a0bb523051df5` |
| `tests/fixtures/extended/p256/model.py` | `7237b068885cbf390e59a1d2775ba62098580658fa6b33affd9e85637bf056ab` |

The focused Rust target is `tests/extended_p256_execution.rs`:

- `p256_ordinary_published_ecdh_ecdsa_and_return_copies`: ordinary RFC5903/RFC6979
  consumer without projecting the P-256 Error enum; full public/ECDH bytes,
  compressed conversion, DER/raw verification and retained mutated-copy checks.
- `p256_published_nist_ecdh_ecdsa_and_rfc_vectors`: all 25 retained NIST ECCCDH
  P-256 vectors and 15 NIST P-256/SHA256 SigVer cases, plus RFC6979, across
  uncompressed/compressed forms and strided/packed layouts where applicable.
- `p256_independent_affine_openssl_and_exceptional_group_cases`: independent
  affine Python integer/group arithmetic, OpenSSL exact public/ECDH bytes and
  signature verification, deterministic random values, scalar boundaries,
  equal/inverse/identity cases, affine x at least `n`, and valid x-zero ECDH.
- `p256_signature_public_digest_and_message_mutations`: every byte of a
  published public key, signature, digest and message; high-S/low-S acceptance
  and out-of-range signature scalars.
- `p256_rejects_noncanonical_scalars_points_der_and_metadata`: malformed
  encodings, invalid coordinates/scalars, compressed nonresidues, DER limits,
  length/error priority and invalid logical metadata.

The native protocol publishes every output byte, not just lengths. Every case
runs with nonzero input offsets in native strided and packed byte layouts and
asserts that all input and guard bytes remain unchanged. Each native process
must exit successfully with empty stderr and an empty mmap/mremap/munmap/brk
trace. The driver batches 16 cases per native process and compiles one protocol
ELF for many cases within its invocation.

The independent Python oracle uses ordinary affine addition and Python modular
inverses, distinct from the production Montgomery/Jacobian algorithms. OpenSSL
is used only by test orchestration. Published examples come from
[RFC5903 section 8.1](https://www.rfc-editor.org/rfc/rfc5903.html#section-8.1) and
[RFC6979 appendix A.2.5](https://www.rfc-editor.org/rfc/rfc6979.html#appendix-A.2.5).
The accepted published gate retains all 25 NIST ECCCDH P-256 vectors and all
15 NIST P-256/SHA256 SigVer cases, along with the RFC examples. Its 382 commands
include both physical layouts and applicable compressed/uncompressed and
message/digest verification forms. Expected public/ECDH bytes and verification
outcomes are checked against the retained published data, rather than inferred
from production results. NIST vector use does not imply CAVP validation.

Direct NIST CAVP download requests returned HTTP403 during preparation. The
retained data therefore uses explicitly attributed mirrors: ECCCDH from
[BoringSSL](https://raw.githubusercontent.com/google/boringssl/main/crypto/ecdh/ecdh_tests.txt)
and ECDSA SigVer from
[Go](https://raw.githubusercontent.com/golang/go/master/src/crypto/ecdsa/testdata/SigVer.rsp.bz2).
The fixture headers preserve the original NIST URLs, mirror URLs and SHA256 of
the complete downloaded mirror file. Only the relevant data sections are
retained; no third-party production implementation is copied.

Root used the following bounded wrapper for each separately selected gate,
substituting its exact name from the list above:

```sh
RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
  timeout --kill-after=2s 100s flock -E 75 -w 35 \
  target/stdlib-work/library-gpu.lock timeout --kill-after=2s 60s \
  target/stdlib-build/debug/deps/extended_p256_execution-939d78f4388ec548 \
  --exact p256_ordinary_published_ecdh_ecdsa_and_return_copies \
  --nocapture --test-threads=1
```

Cargo uses `CARGO_TARGET_DIR=target/stdlib-build`, `CARGO_INCREMENTAL=0`,
`CARGO_PROFILE_DEV_DEBUG=0` and `CARGO_PROFILE_TEST_DEBUG=0`. GPU execution here
runs the compiler; user GPU-kernel behavior is unverified.
