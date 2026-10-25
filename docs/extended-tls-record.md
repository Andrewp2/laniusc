# TLS 1.3 protected records

`ext::tls_record` provides the protected-record layer for
`TLS_CHACHA20_POLY1305_SHA256`. It derives ChaCha20-Poly1305 keys and IVs from
32-byte traffic secrets, constructs and authenticates record headers, encodes
inner content types and padding, maintains independent directional sequence
numbers, and derives the next application traffic secret.

Accepted on 2026-10-24 for native x86_64 Linux output from GPU compilation.
The ordinary consumer and all 308 protocol model commands execute. User GPU
kernels and other execution targets remain unverified. The module is written
entirely in Lanius and requires no allocation or host service.

Key/IV label encoding and traffic-secret updates now use the shared
[SHA-256 schedule](extended-tls-schedule.md): `expand_label` for `key`/`iv`
and `update_traffic` for `traffic upd`. The record API and failure contracts
remain the same.

This is a protocol prerequisite, not a TLS connection. Handshake negotiation,
traffic-secret establishment, peer authentication, certificates, trust policy,
transcript validation, handshake fragmentation/reassembly, alerts/closure,
KeyUpdate message processing, transports and other cipher suites remain outside
this layer. The caller must establish the correct directional traffic secret
and obey the higher-level TLS state machine.

## API

All byte arguments are `core::slice::View<u8>`.

| API | Result |
| --- | --- |
| `sealer(secret)` | `Result<Sealer, Error>` |
| `opener(secret)` | `Result<Opener, Error>` |
| `Sealer.seal(content, content_type: u8, padding: i32, destination)` | `Result<i32, Error>`; full framed length |
| `Opener.open(record, scratch)` | `Result<Opened, Error>` |
| `Sealer.key_update()` / `Opener.key_update()` | `Result<i32, Error>`; zero on success |
| `sequence()` | The next sequence number, or the last number after exhaustion |
| `exhausted()` | Whether the final number was already consumed |
| `Opener.is_poisoned()` | Whether a fatal record error was observed |
| `borrow()` | A reference to the same directional state |

`Opened { content, content_type }` borrows authenticated content in scratch.
It remains valid only while the scratch storage remains alive and unchanged;
opening another record into that storage invalidates the previous contents.
Construction copies the traffic secret and retains no input borrow.

Use constructors and methods. Internal fields are not a resumption format and
must not be fabricated or mutated. State value copies do not grant independent
rights to use the same key/nonce space: one logical sender and one ordered
receiver must own each directional traffic secret. Do not fork a Sealer to
send different records at the same sequence. Do not reset by reconstructing a
state with an already-used traffic secret. Sharing one secret for both traffic
directions would likewise reuse nonces.

## Record and size contracts

The module follows [RFC 8446 sections 5.1–5.5](https://www.rfc-editor.org/rfc/rfc8446.html#section-5.1).
Protected inner content types are alert `21`, handshake `22` and application
`23`. Protected change-cipher-spec `20` is forbidden. Handshake content must be
nonempty. Alert content is exactly two bytes. Application content may be empty.
The module validates these record-level constraints; it does not interpret the
handshake messages or alert level/description bytes.

Content is at most `MAX_CONTENT = 16384` bytes. Padding is nonnegative and
`content.length + 1 + padding <= MAX_INNER = 16385`, including the inner type.
This full-inner cap is required by section 5.4, even when the content is short.
Padding bytes are zero. With this cipher's 16-byte tag, the largest generated
ciphertext is 16401 bytes and the largest framed record is
`MAX_RECORD = 16406` bytes. Destination may be larger; its unused suffix is
preserved.

The outer header is exactly application-data `23`, version `0x0303`, and a
big-endian two-byte ciphertext length. `open` consumes exactly one complete
framed record: truncation, trailing bytes, or concatenated records are rejected.
It first enforces the generic TLS `MAX_CIPHERTEXT = 16640` limit, authenticates
with the five-byte header as associated data, then enforces this profile's
full-inner limit. A generic-maximum peer frame can therefore require 16624
scratch bytes before returning authenticated `RecordOverflow`, although valid
inner plaintext never exceeds 16385. An undersized scratch buffer is a
retryable error that can precede the eventual overflow error.

## State, key updates and transport

The initial sequence is zero. The nonce is the 12-byte IV XOR the sequence
encoded big-endian in the final eight bytes. A successful seal/open advances
the sequence once. Sequence `u64::MAX` is used once; afterward `exhausted()` is
true and subsequent records return `Exhausted`. It never wraps.

Key and IV derivation use
[HKDF-Expand-Label](https://www.rfc-editor.org/rfc/rfc8446.html#section-7.1)
with labels `key` and `iv`, empty context, and output lengths 32 and 12.
`key_update` uses label `traffic upd`, empty context and output length 32, then
rederives the key and IV and resets the sequence to zero. These labels include
the `tls13 ` prefix in their encoded HKDF labels, with no trailing NUL. All
replacement material is derived before state changes. Updating an exhausted
state is allowed; updating a poisoned opener returns `Poisoned`.

The caller coordinates the
[KeyUpdate protocol](https://www.rfc-editor.org/rfc/rfc8446.html#section-4.6.3):
send the KeyUpdate handshake message under the old key, update afterward, and
update receive state only after authenticating and validating the peer's
message. Calling this primitive does not send or process a KeyUpdate. The
caller also enforces handshake alignment across changes and any required
KeyUpdate response before application traffic.

A successful `seal` consumes its sequence before transport publication. Retain
and send the returned packet bytes. A partial write is continued from those
same bytes; do not reseal a suffix or reconstruct a state for retransmission.
Seal cannot roll back transport progress or determine whether the peer received
a packet. An unrecoverable publication failure requires abandoning that
connection state.

## Failure and storage behavior

Errors are `Bounds`, `InvalidSecretLength`, `InvalidType`,
`InvalidContentLength`, `InvalidPadding`, `RecordOverflow`, `BufferTooSmall`,
`Exhausted`, `Poisoned`, `InvalidRecord`, `Authentication`, `InvalidInner`, and
`Derivation`.

Constructors check logical bounds before exact secret length. `seal` checks,
in order: both logical views, exhaustion, content type, content length,
padding/full-inner length, and destination capacity. Every returned sealing
error preserves the entire destination and state. The content must be disjoint
from destination and state. After this preflight, sealing builds the header
and inner plaintext in destination and encrypts that body in place.

`open` checks, in order: both logical views, poison, exhaustion, minimum frame
header, generic ciphertext overflow, exact header/framing/minimum tag-plus-type
length, scratch capacity, authentication, full-inner overflow, and inner
content type/length. Logical `Bounds` and `BufferTooSmall` preserve scratch and
state, so the same record can be retried with corrected views/capacity. Invalid
framing, overflow, authentication, and inner-message errors poison the opener;
all later logically valid calls return `Poisoned`, and key updates cannot clear
it. The failure leaves the sequence unchanged but the poisoned state is terminal.

Authentication completes before decryption, so `Authentication` preserves
scratch. Authenticated malformed inner plaintext can remain in scratch on
`InvalidInner` or authenticated `RecordOverflow`; no `Opened` value is returned.
The caller must not publish any scratch bytes from an unsuccessful call.
Record, scratch and opener state must be mutually disjoint. Output beyond the
actual decrypted inner length is preserved. No operation flushes, closes,
allocates, owns caller buffers or implicitly erases memory.

Every view must have writable/readable physical backing for its complete
logical range. Logical range validation cannot prove physical backing.
Nonzero offsets, native strided arrays and packed bytes share the same API.
Input storage is immutable throughout each call. The fixed state and temporary
key material are ordinary memory; overwriting current fields during update is
not a secure-erasure guarantee.

Key material does not select source-level primitive control flow or memory
indices. Padding/type parsing does branch on authenticated plaintext. Neither
this module nor its tests prove constant-time generated machine code, compiler
side-channel properties or secure erasure. This foundation has not received an
independent cryptographic security audit.

## Admission

[extended_tls_record_execution.rs](../tests/extended_tls_record_execution.rs)
uses a Python test peer with independent `hashlib`/`hmac` label derivation and
`ctypes` calls to `libsodium.so.23` for AEAD. A single protocol ELF handles many
binary commands. A separate ordinary consumer imports no error projections and
checks round trips after the original traffic-secret storage changes.

The accepted states include normal and maximum records; all three valid inner
types; forbidden and unknown types; empty application/handshake/alert behavior;
size and padding limits; packed and strided views; explicit offsets and guards;
multiple sequences including the final value; repeated records; synchronized
updates; retryable bounds/capacity failures; tag/ciphertext tampering; malformed
headers; authenticated malformed inner messages; poisoning; and no-allocation
memory traces. Sequence-boundary fixture setup mutates private implementation
state solely to make `u64::MAX` reachable; no public arbitrary-sequence import
API is provided.

| Accepted gate | Runtime cases |
| --- | ---: |
| `ordinary_record_consumer_roundtrips_without_error_projection_and_owns_the_secret` | One consumer, two records and a key update |
| `record_failures_preserve_retryable_state_and_poison_fatal_input_without_publication` | 96 protocol commands |
| `tls13_records_match_independent_peer_over_sizes_padding_types_strides_and_sequences` | 212 protocol commands |

The original three-test invocation passed in **11.28 seconds**. It produced two strict
ELFs and executed three native processes; both protocol groups shared their
compiled fixture through `OnceLock`. Drivers asserted empty allocation traces
for `mmap`, `munmap`, `mremap` and `brk`. The fresh joint Rust build with the
array-capacity regression took 38.82 seconds and produced
`target/stdlib-build/debug/deps/extended_tls_record_execution-ece0ab2532f0d157`.

The accepted runtime command was:

```bash
RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
LANIUS_DEBUG_STAGE_ERRORS=1 timeout --kill-after=2s 100s \
  flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s \
  target/stdlib-build/debug/deps/extended_tls_record_execution-ece0ab2532f0d157 \
  --nocapture --test-threads=1 \
  > target/stdlib-work/tls-crypto-admission/tls-record-after-capacity.log 2>&1
```

These are correctness, state-transition and allocation observations. The
[performance record](library-foundation-performance.md#authenticated-bytes-key-exchange-and-tls-records)
compares the combined crypto/record consumer and an existing 1 MB workload with
one pinned shader set, before/after/after/before ordering and six samples per
variant/workload. All 32 emitted programs passed; no slowdown was observed.
The measurements do not establish a causal speedup or cross-compiler ratio.

### Shared schedule integration

After replacing the record module's repeated label encodings with
`tls_schedule::expand_label` and `tls_schedule::update_traffic`, the unchanged
full three-test driver passed again in **11.27 seconds**: the ordinary consumer
and all 308 model commands. Its two strict ELFs executed three native processes
with the same empty allocation-trace assertions. The fresh joint Rust build
with the sign-bytes driver took 1.57 seconds. The runtime command was:

```bash
RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
LANIUS_DEBUG_STAGE_ERRORS=1 timeout --kill-after=2s 100s \
  flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s \
  target/stdlib-build/debug/deps/extended_tls_record_execution-ece0ab2532f0d157 \
  --nocapture --test-threads=1 \
  > target/stdlib-work/tls-auth-admission/record-shared-labels.log 2>&1
```

Local build evidence is `target/stdlib-work/tls-auth-admission/build-record-and-sign.log`.
The earlier performance comparison above predates the new schedule dependency;
performance comparison of this expanded import closure remains pending. Record
correctness does not establish handshake sequencing, peer authentication or a
complete TLS connection.

### Original compiler failure and repair

The first invocation took 5.98 seconds: the ordinary consumer passed and both
protocol groups failed while compiling their shared fixture, before any model
command executed. The public diagnostic was `LNC0057`. A subsequent diagnostic
run identified target capacity exhaustion: 187055 target rows were required,
with 135168 available. Large nonzero array repeats and value copies exceed the
compiler's original eight-target-rows-per-HIR estimate.

The [dependency record](tls-record-lowering-dependency.md) preserves the
original failure, a smaller independent reproduction, and the accepted repair.
Host orchestration now grows target/artifact capacity from measured demand,
plans the replacement device graph, and bounds monotonic full-graph retries
at three. Production TLS code, the complete protocol fixture and its model
expectations were unchanged for the accepted rerun. The repair changes no
shader, compiler IR record, ABI or formal proof.

Local evidence remains under the ignored
`target/stdlib-work/tls-crypto-admission/`: `tls-record.log` and
`tls-stage-error.log` preserve the initial failures;
`build-capacity-native.log` and `tls-record-after-capacity.log` record the
accepted build and runtime gate. This record-layer admission does not establish
a complete TLS connection.
