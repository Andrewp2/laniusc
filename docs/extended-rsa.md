# Bounded RSA public verification

Accepted for **x86_64 Linux output from GPU compilation**.
Five focused executable gates passed, including independent signature
verification, encoding/budget failures and an ordinary consumer. Performance,
user GPU kernels and other execution targets remain unverified.

`ext::rsa` implements public RSA verification using
[RFC 8017, sections 4, 5.2.2, 8 and 9](https://www.rfc-editor.org/rfc/rfc8017.html).
It has two explicit schemes:

| Scheme | Encoding |
| --- | --- |
| `Pkcs1v15Sha256` | RSASSA-PKCS1-v1_5 with exact SHA-256 DigestInfo |
| `PssSha256Salt32` | RSASSA-PSS with SHA-256, MGF1-SHA-256, 32-byte salt and trailer `bc` |

Public moduli may have **2048 through 4096 bits**, including non-byte-aligned
sizes. Exponents are odd `u32` values from 3 through 4,294,967,295. These are
bounded interoperability choices, not a FIPS validation claim. In particular,
the exponent profile includes 3, below the key-generation minimum in
[FIPS 186-5, section 5](https://doi.org/10.6028/NIST.FIPS.186-5).
There is no signing, private-key operation, key generation or allocation
fallback in production.

## API and ownership

`Bytes` below means `core::slice::View<u8>`. Every fallible call returns
`core::result::Result<T, Error>`.

| Call | Success value |
| --- | --- |
| `default_limits()` | `Limits { max_message: 1048576, max_work: 16777216 }` |
| `budget(Limits)` | `Budget` |
| `from_components(modulus: Bytes, exponent: u32, budget: &Budget)` | `PublicKey` |
| `parse_pkcs1_public_key(der: Bytes, budget: &Budget)` | `PublicKey` |
| `parse_rsae_spki(der: Bytes, budget: &Budget)` | `PublicKey` |
| `signature_scheme(algorithm_identifier_der: Bytes, budget: &Budget)` | `Scheme` |
| `key.verify_digest(scheme, digest: Bytes, signature: Bytes, budget: &Budget)` | `bool` |
| `key.verify_sha256(scheme, message: Bytes, signature: Bytes, budget: &Budget)` | `bool` |
| `key.modulus_bits()` / `key.signature_length()` / `key.exponent()` | `i32` / `i32` / `u32` |
| `key.borrow()` / `budget.borrow()` | `&PublicKey` / `&Budget` |

The raw modulus is a canonical unsigned big-endian magnitude: nonempty,
odd, with no leading zero. A signature is exactly `ceil(modulus_bits / 8)`
big-endian bytes; leading signature zeros are significant and short forms
are rejected. `verify_digest` takes exactly 32 bytes already hashed with
SHA-256. `verify_sha256` hashes the supplied message once. Neither call
guesses the scheme or accepts an alternative digest algorithm.

`PublicKey` owns its modulus, Montgomery constants and fixed inline arrays;
it retains no source view. Copying a constructed key copies its state, and
overwriting the constructor input does not change either copy. Use the
constructors and keep cached fields immutable. Those fields are
implementation state, never serialized validation or trust tokens.
Fabricated or mutated key caches are outside the contract.

All logical views require stable, physically backed storage. Native signed
strides and packed byte slices use the same byte-indexing path. Read-only
inputs may overlap each other, but must be disjoint from the mutable budget
and key state. Logical bounds checks cannot establish physical capacity or
enforce those ownership rules. No API returns a borrowed output or publishes
partially decoded key state. Only the supplied budget changes.

## Encodings and TLS boundary

PKCS#1 keys must be one complete DER `RSAPublicKey` sequence containing
exactly two canonical positive INTEGERs. A single required sign-padding zero
is stripped; redundant padding, negative values, indefinite lengths and
trailing elements or bytes are rejected.

SPKI accepts only `rsaEncryption` (`1.2.840.113549.1.1.1`) with required
NULL parameters, a BIT STRING with zero unused bits and a complete PKCS#1
key. This follows [RFC 3279, section 2.3.1](https://www.rfc-editor.org/rfc/rfc3279.html#section-2.3.1)
and [RFC 4055](https://www.rfc-editor.org/rfc/rfc4055.html).
RSASSA-PSS-constrained public-key identifiers are rejected; their restrictions
are never discarded by treating them as RSAE keys.

`signature_scheme` consumes an entire AlgorithmIdentifier:

- `sha256WithRSAEncryption` accepts absent or NULL parameters, as required
  by [RFC 4055, section 5](https://www.rfc-editor.org/rfc/rfc4055.html#section-5).
- `id-RSASSA-PSS` requires explicit ordered `[0]` SHA-256, `[1]` MGF1 with
  SHA-256 and `[2]` salt length 32. Nested SHA-256 identifiers accept absent
  or NULL parameters. Trailer 1 is the DEFAULT and must be omitted in DER.
  SHA-1 defaults, other salt lengths, different MGF algorithms, repeated or
  reordered fields and explicit default trailers are rejected.

PKCS#1 v1.5 verification compares the entire encoded message, including all
`ff` padding, separator and the exact SHA-256 DigestInfo with NULL parameters.
PSS checks `emBits = modulus_bits - 1`, unused top bits, zero padding,
delimiter, salt, hash and trailer. When `modulus_bits % 8 == 1`, `emLen` is
one byte shorter than the signature; a nonzero excluded leading recovered
byte is rejected before accepting the encoding.

This primitive does not choose a trusted key or validate a certificate path,
identity, validity time, usage or peer possession. TLS callers must enforce
[RFC 8446, section 4.2.3](https://www.rfc-editor.org/rfc/rfc8446.html#section-4.2.3):
PKCS#1 signatures are for certificates, while RSAE CertificateVerify uses
PSS with matching hash/MGF and hash-length salt. The caller supplies the
exact certificate signed bytes or CertificateVerify context message and
enforces negotiation and transcript checkpoints. No TLS or X.509 caller is
changed by this module.

## Failure ordering and bounded work

`Limits { max_message: i32, max_work: u64 }` creates a mutable
`Budget { message_limit: i32, work_left: u64 }`. A negative message limit is
`InvalidLimits`; zero message bytes and zero credits are valid limits.
The message limit applies to `verify_sha256`, not the fixed 32-byte digest
entry point. Key DER is capped at `MAX_KEY_DER_BYTES = 1024`, and algorithm
DER at `MAX_ALGORITHM_DER_BYTES = 256`.

Every direct view's metadata is checked first: negative starts/lengths and
ends above `i32::MAX` produce `Bounds` before reading bytes or changing the
budget. An invalid budget follows. Subsequent ordering is:

| Entry point | Remaining checks/stages in order |
| --- | --- |
| Raw key | Empty/oversized modulus, exponent, reserve scan, canonical odd magnitude and bit range, reserve setup, construct cache |
| DER key / algorithm | Fixed input cap, reserve parse, strict schema, nested raw-key stages where applicable |
| `verify_digest` | Digest length, signature length, reserve verification, public operation and encoding checks |
| `verify_sha256` | Signature length, message limit, reserve hashing plus verification, hash and verify |

Errors are `Bounds`, `InvalidLimits`, `InputLimit`, `WorkLimit`,
`InvalidModulusEncoding`, `UnsupportedModulus`, `InvalidExponent`,
`InvalidKeyEncoding`, `UnsupportedAlgorithm`, `InvalidParameters`,
`InvalidDigestLength` and `InvalidSignatureLength`. DER key errors may
propagate a more specific raw modulus/exponent error after schema parsing.
An otherwise well-shaped incorrect signature, including a representative
greater than or equal to the modulus, returns `Ok(false)`.

Credits are reserved before each stage. An unaffordable reservation returns
`WorkLimit` without consuming that reservation; previously admitted stages
remain charged. Invalid contents and failed cryptographic verification are
charged once their stages were admitted. Retrying with a new budget is an
explicit caller decision; there is no hidden reset, refund or unbounded retry.

For an active limb count `L = ceil(modulus_bits / 32)`, signature size `k`,
exponent `e` and byte length `n`, the deterministic credit schedule is:

```text
scan/parse(n) = n + 128
setup(L)     = 64*L*(6*L + 16) + 4096
product(L)   = 3*L*L + 12*L + 256
products(e)  = bit_length(e) + popcount(e) + 2
hash(n)      = n + 64*floor((n + 72)/64)
verify       = products(e)*product(L) + 8*k + 4096
PSS extra    = 64*ceil((emLen - 33)/32) + hash(72)
```

`verify_sha256` adds `hash(message_length)`. A raw constructor reserves a
modulus scan and setup. PKCS#1 parsing adds its own parse charge; SPKI adds
both outer and nested PKCS#1 parse charges. These are conservative admission
credits for bounded stages, not measured instruction counts or time limits.
The caller must also bound the number of operations and external I/O.

Arithmetic uses at most 128 radix-2^32 limbs, a 257-digit temporary product,
Montgomery reduction and at most 66 Montgomery products for a public
exponent. There are no secret-key operations or secret-indexed tables.
Control flow depends on public key, signature and message values; no
compiled constant-time, secure-erasure, fault-resistance or hardware
acceleration guarantee is made. Constructor checks do not prove
factorization, `gcd(e, lambda(n))`, valid key generation or trust.

## Executable admission

[extended_rsa_execution.rs](../tests/extended_rsa_execution.rs) compiles one
binary protocol fixture per driver invocation and a separate ordinary
imported consumer. Protocol groups can share an ELF within an invocation;
this admission used five separate exact-filter invocations. The
test-only Python peer uses OpenSSL EVP verification and Python integer
`pow`; production imports neither. The ordinary consumer uses published
fixed signatures, copied keys and both message/digest entry points without
error-enum projection.

The local OpenSSL RSA generator returned a 2048-bit modulus for a requested
2049-bit key. The upstream
[SP 800-56B prime-generation path](https://github.com/openssl/openssl/blob/openssl-3.0.2/crypto/bn/bn_rsa_fips186_4.c)
takes `modulus_bits / 2` for each factor. The boundary fixture instead uses
[`BN_generate_prime_ex`](https://docs.openssl.org/3.0/man3/BN_generate_prime/)
to generate separate 1025/1024-bit primes, then Python integers derive the
exact 2049-bit modulus and private inverse. Actual EVP verification and a
separate public `pow` check validate the authored signatures. This is
test-only key generation; no bytes are padded and the native public-key
profile is unchanged.

The accepted groups cover:

- 69 byte-aligned original SHA-256 NIST outcomes for 2048/3072-bit keys,
  plus independently generated 2048/e=3, 2049/e=65537, 4096/e=65537 and 2048/e=u32MAX keys;
  both schemes and 16 KiB messages for the largest key.
- Signature representatives zero, `n-1`, `n` and all-ones, recovered encoding
  mutations, exact DigestInfo, PSS salt/MGF/trailer seams, the shorter
  2049-bit PSS `emLen` and incorrect messages/digests.
- Strict PKCS#1, RSAE SPKI and AlgorithmIdentifier encodings, malformed views,
  native/packed strides, complete source/guard comparisons, copied-cache and
  source-buffer independence.
- Exact and one-less work reservations, failed-attempt charges, message caps,
  length errors and metadata precedence. Native drivers require empty
  `mmap`, `munmap`, `mremap` and `brk` traces.

The published data comes from NIST's
[CAVP RSA verification archive](https://csrc.nist.gov/CSRC/media/Projects/Cryptographic-Algorithm-Validation-Program/documents/dss/186-3rsatestvectors.zip),
SHA-256 `8405aeb3572a4f98ed4b1a3ccb3f2f49e725462dd28ec4759d6a15d88855d19c`.
The TSV preserves all 72 original records, results and salt lengths. Three
original PKCS#1 negative records contain odd hexadecimal fields: a 255-nibble
message at `SigVer15_186-3.rsp` line 784 and 511-nibble signatures at lines
1204 and 1211. The peer pins those exact TSV rows and hashes and rejects
them as malformed source-format cases before byte-vector admission. It
does not invent a missing nibble, call them native verification results or
silently omit other malformed data. The remaining 69 records are the
accepted original native/OpenSSL anchors. Its 3072-bit PSS
vectors use salt length zero: their published positive outcomes remain
recorded, and this module intentionally rejects them under its salt-32
profile. Publicly supplied NIST test private values are used only to author
adversarial test signatures; they are insecure published test material.
OpenSSL supplies the independent acceptance result for those signatures.

### Receipts and reproduction

| Exact filter | Blocks | Protocol commands | Elapsed |
| --- | ---: | ---: | ---: |
| `published_sha256_vectors_and_bounded_key_profiles_match_openssl` | 27 | 123 | 12.84 s |
| `inconsistent_representatives_and_both_emsa_formats_reject` | 2 | 276 | 12.17 s |
| `canonical_rsae_key_and_signature_identifiers_are_checked` | 136 | 136 | 8.57 s |
| `work_reservations_and_metadata_priority_preserve_inputs` | 7 | 85 | 9.59 s |
| `ordinary_consumer_owns_public_key_and_verifies_messages_and_digests` | — | Separate executable | 7.47 s |

The four protocol groups passed **620 commands**. The five invocations
produced five strict x86 ELF executables and ran five native processes;
all allocation traces were empty. The fresh Rust driver build took
**1.34 s**. These are whole admission timings including compilation and
orchestration, not RSA throughput. Each protocol peer and native process
has its own 45-second timeout; the ordinary process has a 10-second timeout.

Production (`b2a4015d`), driver (`15cb5094`), protocol fixture (`b8f9b70b`)
and ordinary fixture (`c24e44b7`) were unchanged throughout admission.
The rejection, encoding and budget gates used the original peer
`05b0c6ac`. The accepted published gate used final peer `f9944556`, which
corrected only its published-data preparation and exact odd-size test-key
generation. Those fixes did not weaken production or native assertions.

Two earlier published attempts failed before GPU compilation or native
execution: the original peer stopped on the NIST odd-hex fields in
**0.06 s**; peer `5d25db29`, with those source-format cases explicitly
handled, reached the OpenSSL odd-size key-generation assertion and stopped
in **0.48 s**. The final peer preserves the original TSV, keeps the
2049-bit coverage and passed in 12.84 s. These preparation failures are
retained as history and are not counted as native test results.

The accepted local driver was
`target/stdlib-build/debug/deps/extended_rsa_execution-8d19dd6e2c29e635`.
The accepted build command, from the repository root, was:

```sh
CARGO_TARGET_DIR=/home/andrew-peterson/code/laniusc/target/stdlib-build \
CARGO_INCREMENTAL=0 CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
timeout --kill-after=2s 100s \
  flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s \
  cargo test --test extended_rsa_execution --no-run \
  > target/stdlib-work/rsa-admission/build-first.log 2>&1
```

The exact filters, runtime environment, timeout and lock settings can be
reproduced with:

```sh
rsa_gate() {
  RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
  LANIUS_DEBUG_STAGE_ERRORS=1 timeout --kill-after=2s 100s \
    flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
    timeout --kill-after=2s 60s \
    target/stdlib-build/debug/deps/extended_rsa_execution-8d19dd6e2c29e635 \
    --exact "$1" --nocapture --test-threads=1 \
    > "target/stdlib-work/rsa-admission/$2.log" 2>&1
}
rsa_gate ordinary_consumer_owns_public_key_and_verifies_messages_and_digests ordinary-first
rsa_gate inconsistent_representatives_and_both_emsa_formats_reject rejected-first
rsa_gate canonical_rsae_key_and_signature_identifiers_are_checked encodings-first
rsa_gate work_reservations_and_metadata_priority_preserve_inputs budgets-first
rsa_gate published_sha256_vectors_and_bounded_key_profiles_match_openssl published-exact-2049
```

The binary suffix identifies the accepted local build; a fresh build can
produce a different suffix. Ignored receipts are under
`target/stdlib-work/rsa-admission/`: `build-first.log`, the five logs above,
and the two preparation failures `published-first.log` and
`published-source-format-fixed.log`. Reproduction uses the current final
peer; the original mixed-version receipts remain distinguished above.

Other hashes, PSS salt policies, restricted PSS keys, signing and TLS/X.509
integration remain outside this module's supported profile. Certificate
trust, identity and policy are separate caller responsibilities. Performance
and execution on user GPU kernels or other targets remain unverified.
