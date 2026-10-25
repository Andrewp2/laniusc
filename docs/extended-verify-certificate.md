# verify-certificate

[`sample_programs/library/verify_certificate.lani`](../sample_programs/library/verify_certificate.lani)
verifies an ordered certificate chain against one explicitly chosen anchor,
service identity, and UTC time. All application behavior runs in Lanius. It
composes [`ext::x509_path`](../extended/ext/x509_path.lani),
[`ext::service_identity`](../extended/ext/service_identity.lani), and the owned
[signature dispatcher](extended-signature.md).

**Multi-algorithm caller admission is pending.** The application now passes an
explicit default certificate policy to the shared path validator and keeps
its CLI, I/O, publication and cleanup contract. The historical Ed25519-only
84-case receipt is preserved separately below; it does not verify the new
signature routes or expanded inline path storage.

## CLI and input

```text
verify-certificate ANCHOR_DER dns|ip IDENTITY UNIX_TIME < peer-chain.der
```

There are exactly four arguments. `ANCHOR_DER` is one raw path of 1–4,095 bytes,
which need not be UTF-8. Its contents must be exactly one DER certificate.
The program does not consult a system trust store or infer trust from a
self-signed certificate supplied by the peer. The caller chooses the trusted
anchor and is responsible for that choice.

`dns` treats `IDENTITY` as an ASCII DNS reference name. It accepts numeric
labels, normalizes ASCII case and one optional trailing root dot, and rejects
wildcards, non-ASCII text, and malformed labels. It performs no IDNA conversion,
DNS lookup, or search-list expansion. DNS names match certificate SAN DNS-IDs;
the subject CN is never a fallback.

`ip` parses a strict unscoped IPv4 or IPv6 literal through `core::net`, then
matches its network-order octets against SAN IP-IDs. Brackets and scope IDs
are not accepted. The mode is explicit: `dns 192.0.2.1` requests a DNS-ID
containing that text, while `ip 192.0.2.1` requests a four-byte IP-ID. There is
no implicit DNS/IP or IPv4/IPv6-mapped crossover.

`UNIX_TIME` is an ASCII decimal number with an optional leading minus sign,
at least one digit, and at most 20 characters. A plus sign and whitespace are
invalid. Leading zeroes and negative zero are allowed. Checked accumulation
accepts **−62,135,596,800 through 253,402,300,799**, covering UTC years 1–9999.
The program never reads a host clock. An invalid time argument returns 2;
a supported time outside a certificate's validity interval returns 5.

Stdin contains concatenated DER certificates, **leaf first, followed by the
ordered intermediates**. Each certificate's DER tag and exact length provide
its framing; there is no added length prefix, PEM envelope, or separator.
Trailing junk and truncated frames fail. At least one and at most eight peer
certificates are accepted. The final peer certificate may repeat the exact
configured anchor DER under the shared path validator's rule. That optional
copy still consumes one of the eight input slots and its bytes count toward
the input limit. The application adds no separate duplicate or path policy.

All arity, path, mode, reference, and time checks finish before signal setup,
opening the anchor, or reading stdin. Arguments are copied with
`snapshot(1,4,4372)`, excluding argv[0]. There are no options or implicit
identity/time defaults.

## Current multi-algorithm caller gates: runtime pending

The focused driver retains its original three exact test names and all prior
owner, descriptor, EOF, input-limit and shared-call-budget controls. Eleven
additional default-policy/single-anchor cases consume the independent OpenSSL
mixed corpus: RSA→P-256→Ed25519 and P-256→RSA→Ed25519 issuers, RSA and P-256
leaf keys, RSA-PSS and PKCS#1 certificate signatures, exact included roots,
ECDSA/RSA tampering and an unsupported child signature algorithm. Common
supported paths are checked independently with `openssl verify` before they
are supplied to the native application.

The planned total is 95 native cases: 61 CLI/path cases, 27 owner/fault cases
and seven cumulative-limit/I/O-budget cases. All application outputs remain
exact `verified\n` on success and empty before-publication failures. No
allocation occurs in path verification or publication; the existing
address/length/generation allocation and descriptor ledgers remain in force.
Only the source's explicit certificate policy call and profile comment change;
its input/I/O/cleanup body is preserved. No runtime result for this migration
is claimed until root completes the serialized gates.

## Historical Ed25519-only native admission

The executable calls `validate_server` with the complete chain, one configured
anchor, the prepared reference, caller-provided scratch, and a fresh default
shared path budget and explicit `signature::default_certificates()` policy.
Only a successful `ValidatedServer` authorizes output.
It never releases a key obtained merely by parsing the leaf.

This is the shared validator's **bounded ordered server profile**, with
Ed25519, ECDSA/P-256/SHA-256, RSAE PKCS#1/SHA-256 and
RSA-PSS/SHA-256/MGF1-SHA-256/salt32 certificate-edge verification. The explicit
default certificate policy permits `0807,0403,0804,0401`; a child's public-key
family is independent of its issuer's signature algorithm. It retains exact
encoded issuer/subject name links, validity
and calendar checks, issuer/anchor CA constraints, applicable key usage and
server EKU restrictions, path-length checks, supported extension policy, and
SAN service identity matching. Unsupported algorithms or constraints fail
explicitly. It does not reorder peers, search for missing issuers, or fetch
certificates. The configured anchor follows the same documented profile;
choosing it does not waive its validity or CA checks. See the
[`x509_path` source](../extended/ext/x509_path.lani) for the exact policy.

Success writes exactly these nine bytes:

```text
verified
```

There is one final newline. The copied validated leaf key is deliberately not
exported by this CLI. Stderr is unused.

This program does not implement general PKIX policy, revocation checking,
OCSP/CRL retrieval, or TLS CertificateVerify, Finished, or transcript checks.
Its success means the supplied certificate path, identity, and time passed
the supported profile relative to the chosen anchor. It does not establish
that a live TLS peer possesses the leaf private key or authenticated a
particular handshake.

## Storage, host I/O, and limits

The application reserves one owned buffer for at most **1,048,576 cumulative
bytes**, including the anchor file and every stdin byte. It reads the anchor
into the prefix, closes that file, then appends stdin. Each stream requires
actual EOF. At the cumulative cap, an actual one-byte probe distinguishes EOF
from excess input; a positive probe consumes one extra byte without storing
it and returns 7. An anchor read, byte-limit, or close failure prevents stdin
consumption. Parsing begins only after all required input reads succeed.

The anchor opens read-only with no-follow, nonblocking, and close-on-exec
flags. No-follow applies to the final path component; earlier path components
follow OS rules. There is no separate regular-file assertion. A descriptor
must supply complete bounded contents and EOF. Every successful open gets
exactly one invalidating close attempt before stdin; close is never retried,
and its failure returns 3 even after a read or exhausted-budget failure.
Stdin and stdout are borrowed and are never closed.

Peer framing uses up to eight borrowed DER views. Path parsing uses inline
storage for nine slots, enough for eight peers and one anchor. Each Slot now
contains an optional owned multi-algorithm key cache, including RSA's larger
inline state; the prior Ed25519 storage footprint is not a bound. The default
path budget bounds aggregate input to 1 MiB, signature attempts to 64, and
combined path/signature work to 1,073,741,824 abstract units. This explicitly
raises the historical work allowance for primitive and owned-cache costs;
`verification.message_limit` derives from the nonnegative parser input cap.
Its shared X509 parser budget additionally
bounds DER items to 100,000 and parser work to 16,777,216 units. These budgets
stay shared through path and identity validation; no cursor receives a fresh
allowance. Logical caps and work units do not specify RSS, physical View
stride, total stack usage, isolated throughput, or elapsed execution time.

One shared **131,072-attempt** budget covers anchor reads and its EOF probe,
stdin reads and its EOF/excess probe, and stdout writes. Interrupted retries
count. Open, close, signal setup, and argument services are outside that
counter. Reads request at most 1,024 bytes and only the remaining cumulative
allowance, except for the one-byte cap probe. The program retries Interrupted
reads and writes, advances by valid acknowledged counts, and rejects invalid
counts or a zero-progress write. SIGPIPE Ignore is installed after CLI checks
and before input-buffer allocation, allowing EPIPE to return normally.

Every borrowed input and argument remains alive until validation finishes.
The application destroys the input buffer and argument snapshot before its
first stdout call. All error exits release their owned storage. Verification
itself and publication allocate no new owned storage. Failure before
publication leaves stdout empty. A host failure or call-budget exhaustion
during publication may leave a prefix of `verified\n`; output is not a
transaction or durability guarantee. Attempt limits do not bound how long a
blocked host call can wait.

| Status | Meaning |
| --- | --- |
| 0 | The supported path, identity, and time checks passed and the report was written |
| 2 | Invalid CLI, path syntax, identity reference, or time argument |
| 3 | Argument host access, signal setup, open/read/close/write, or returned-count failure |
| 4 | Argument or input-buffer allocation failed |
| 5 | DER, schema, signature, path/profile, identity, or certificate-time rejection |
| 7 | Cumulative input, chain count, parser/path work, signature, or I/O call limit exceeded |

## Focused driver

[`tests/extended_verify_certificate_execution.rs`](../tests/extended_verify_certificate_execution.rs)
compiles the real app with stdlib and extended source roots, then applies the
unchanged strict ELF/jump checker before native execution. One `OnceLock`
shares the compiled app across groups selected in one driver process.
Separate exact test selections compile one app ELF each.

The test-only Python corpus constructs DER independently and uses OpenSSL to
derive public keys and sign each exact TBSCertificate. It checks selected
compatible direct, intermediate, long-chain, identity, time, and tamper cases
with a separate `openssl verify` invocation using explicit trust, purpose,
time, and hostname/IP options. It supplies no default trust store. Ordered
input, duplicate, SAN-only, and unsupported-profile expectations remain
explicit where the library deliberately has a narrower policy than general
OpenSSL path building.

The reference commands follow the official
[OpenSSL verify documentation](https://docs.openssl.org/3.0/man1/openssl-verify/)
and [verification options](https://docs.openssl.org/3.0/man1/openssl-verification-options/).
Neither OpenSSL nor Python is linked into or called by the Lanius executable.

| Exact test | Accepted evidence |
| --- | --- |
| `verify_certificate_signed_paths_identity_time_and_cli` | Real signed direct/intermediate/eight-peer paths, optional included root, explicit DNS/IP and pre-epoch time, signature/anchor/identity/profile failures, exact DER framing, and CLI rejection before input |
| `verify_certificate_owners_descriptors_partial_io_and_faults` | Every reached allocation denial, matching address/size releases, one close attempt per opened anchor, no-follow behavior, partial/retry/error I/O, actual EPIPE, and owner retirement before publication |
| `verify_certificate_cumulative_caps_eof_and_shared_io_budget` | Exact cumulative byte cap, real EOF/excess probes on both input streams, shared I/O exhaustion, and close-error precedence after an exhausted read budget |

The trace watches `rt_sigaction`, `openat`, `close`, `read`, `write`, `mmap`,
`munmap`, `mremap`, and `brk`. It checks reached injected faults and preserves
both input files. A synthetic successful short write verifies response to the
reported progress: strace skips that kernel write, so captured output is the
remaining suffix. It is not evidence that the skipped byte was delivered.
Controlled short reads similarly use explicitly injected data. Ordinary real
file reads also return short successful counts before their EOF probes.

## Accepted runs and reproduction

The three exact invocations passed with the frozen application and corpus:

| Exact test | Native cases | Time | Log |
| --- | ---: | ---: | --- |
| `verify_certificate_signed_paths_identity_time_and_cli` | 50 | 9.78 s | `verify-certificate-ordinary.log` |
| `verify_certificate_owners_descriptors_partial_io_and_faults` | 27 | 9.82 s | `verify-certificate-faults.log` |
| `verify_certificate_cumulative_caps_eof_and_shared_io_budget` | 7 | 21.48 s | `verify-certificate-limits.log` |

Each selection compiled one app ELF and reused it for its native cases. The
owner/fault gate checked every reached allocation denial, matching storage
release, file-owner close attempts, actual EPIPE and no-follow rejection, and
the explicitly synthetic reported-progress controls. The limit gate checked
the actual aggregate 1 MiB EOF/excess probes, 131,072 shared data-call attempts,
and close-error precedence after exhausting the read budget.

The initial Rust driver build failed with E0271 because the corpus decoder's
index closure inferred `i32` while slicing required `usize`. Adding the
explicit `|i: usize|` annotation corrected this test-host build issue. That
failed build exited 101 before any GPU compilation or native app attempt;
it is separate from the accepted counts above. Neither the Lanius application
nor the corpus or expected assertions changed.

The corrected Rust build passed in 1.48 seconds. Its binary was
`target/stdlib-build/debug/deps/extended_verify_certificate_execution-96832fa4b4caa6b9`.
The failed build log is `build-verify-certificate.log` and the corrected one
is `build-verify-certificate-corrected.log`. All logs named here are under
`target/stdlib-work/tls-peer-auth-admission/`; they are ignored local artifacts
and are not checked in. These build/gate times are not isolated signature or
path-verification throughput measurements.

OpenSSL, Python 3, strace, timeout, and flock are test dependencies. From the
repository root, the corrected driver build uses:

```sh
timeout --kill-after=2s 100s \
  flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s \
  env CARGO_TARGET_DIR="$PWD/target/stdlib-build" \
    CARGO_INCREMENTAL=0 CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
    cargo test --test extended_verify_certificate_execution --no-run
```

The accepted runtime selections use this bounded, serialized form, one
invocation per exact test. The binary name is specific to this checkpoint:

```sh
verify_certificate_gate() {
  timeout --kill-after=2s 100s \
    flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
    timeout --kill-after=2s 60s \
    env RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
      target/stdlib-build/debug/deps/extended_verify_certificate_execution-96832fa4b4caa6b9 \
      --exact "$1" --nocapture --test-threads=1
}
verify_certificate_gate verify_certificate_signed_paths_identity_time_and_cli
verify_certificate_gate verify_certificate_owners_descriptors_partial_io_and_faults
verify_certificate_gate verify_certificate_cumulative_caps_eof_and_shared_io_budget
```

No compiler, IR, ABI, or proof change is part of this application.
