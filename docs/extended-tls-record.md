# TLS 1.3 protected records

`ext::tls_record` provides the TLS 1.3 protected-record layer with explicit
selection of `TLS_AES_128_GCM_SHA256` or `TLS_CHACHA20_POLY1305_SHA256`.
It derives keys and IVs from 32-byte SHA-256 traffic secrets, constructs and
authenticates record headers, encodes inner content types and padding,
maintains independent directional sequence numbers, and derives the next
application traffic secret. AES traffic state owns a cached, immutable
[AES-GCM key schedule](extended-aes-gcm.md); ChaCha state does not initialize
an unused AES key. All state is inline, with no allocation or host service.

The previous ChaCha-only implementation was accepted on 2026-10-24 for
native x86_64 Linux output from GPU compilation: an ordinary consumer and
308 protocol commands. The current Suite/AES integration is also accepted
on that target: the unchanged 308-command ChaCha regression and new
220-command AES model, each with an ordinary consumer, passed. Its AES and
AES-GCM primitive dependencies have
separate accepted [block](core-aes.md) and [AEAD](extended-aes-gcm.md) gates;
that evidence does not establish the new record integration. User GPU
kernels and other execution targets remain unverified.

Key/IV label encoding and traffic-secret updates now use the shared
[SHA-256 schedule](extended-tls-schedule.md): `expand_label` for `key`/`iv`
and `update_traffic` for `traffic upd`. Factories require an explicit suite;
record methods retain their failure and publication contracts.

This is a protocol prerequisite, not a TLS connection. Handshake negotiation,
traffic-secret establishment, peer authentication, certificates, trust policy,
transcript validation, handshake fragmentation/reassembly, alerts/closure,
KeyUpdate message processing, transports and other cipher suites remain outside
this layer. AES-256-GCM/SHA-384 is not declared here: its SHA-384 TLS schedule
is a separate dependency, although the general AES-GCM primitive supports
256-bit keys. The caller must establish the correct directional traffic secret
and obey the higher-level TLS state machine.

## API

All byte arguments are `core::slice::View<u8>`.

| API | Result |
| --- | --- |
| `sealer(suite: Suite, secret)` | `Result<Sealer, Error>` |
| `opener(suite: Suite, secret)` | `Result<Opener, Error>` |
| `Sealer.seal(content, content_type: u8, padding: i32, destination)` | `Result<i32, Error>`; full framed length |
| `Opener.open(record, scratch)` | `Result<Opened, Error>` |
| `Sealer.key_update()` / `Opener.key_update()` | `Result<i32, Error>`; zero on success |
| `suite()` | The chosen `Suite`, preserved across key updates |
| `sequence()` | The next sequence; AES retains its excluded limit after exhaustion, ChaCha retains `u64::MAX` |
| `exhausted()` | Whether the suite's per-key record/sequence limit was consumed |
| `key_update_due()` | Whether only the final old-key record remains, or state is exhausted |
| `Opener.is_poisoned()` | Whether a fatal record error was observed |
| `borrow()` | A reference to the same directional state |

`Suite` has exactly `Aes128GcmSha256` (wire ID `0x1301`) and
`ChaCha20Poly1305Sha256` (`0x1303`). Negotiation validates wire selections
before choosing this enum. There is no implicit/default suite constructor.
All in-repository callers of the former one-argument factories now pass the
explicit ChaCha variant; their expected wire bytes are unchanged.

`Opened { content, content_type }` borrows authenticated content in scratch.
It remains valid only while the scratch storage remains alive and unchanged;
opening another record into that storage invalidates the previous contents.
Construction copies the traffic secret and retains no input borrow. Cached
AES state owns its expanded key and GHASH subkey; updates derive and cache a
complete replacement before committing any fields.

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
Padding bytes are zero. With either suite's 16-byte tag, the largest generated
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
the sequence once. ChaCha sequence `u64::MAX` is used once; afterward
`exhausted()` is true and `sequence()` retains that final number. It never
wraps.

AES-GCM enforces `AES_GCM_RECORD_LIMIT = 16777216` (`2^24`) successful
protected records per directional traffic key. Empty, alert, handshake and
application records all count. This is a conservative policy below the
`2^24.5` full-size-record guidance in
[RFC 8446 section 5.5](https://www.rfc-editor.org/rfc/rfc8446.html#section-5.5).
The last permitted AES sequence is `16777215`; consuming it sets
`sequence()` to `16777216` and `exhausted()` to true. Further logically valid
record operations return `Exhausted`, preserving buffers and state.

Before sealing application data, query `key_update_due()`. It becomes true
when the next AES sequence is at least `16777215`, when the next ChaCha
sequence is `u64::MAX`, or after exhaustion. Reserve that final old-key
record for a KeyUpdate message; the record layer permits it but does not
interpret its contents or automatically initiate an update. A received final
permitted record never authorizes sequence wrap or old-key reuse. A failed
authentication is fatal on its first occurrence, rather than granting a
fresh verification budget under the same state.

Key and IV derivation use
[HKDF-Expand-Label](https://www.rfc-editor.org/rfc/rfc8446.html#section-7.1)
with labels `key` and `iv`, empty context, and output lengths 16/12 for AES
or 32/12 for ChaCha.
`key_update` uses label `traffic upd`, empty context and output length 32, then
rederives the key and IV, preserves the suite, replaces cached AES state when
selected, and resets the sequence/record count to zero. These labels include
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
and inner plaintext in destination and encrypts that body in place. Each AEAD
call then has a constructed valid key, fixed nonce/tag lengths, supported
body length and sufficient capacity. Its remaining preflight errors are
unreachable under the state/backing contracts; sealing does not return a
fallible AES error after staging destination bytes. AES and ChaCha bodies
are encrypted exactly in place; source content and destination remain
disjoint as required above.

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

## Suite/AES integration admission

The current source changes the canonical factory signature rather than
adding a legacy default wrapper. The unchanged expectations in
[extended_tls_record_execution.rs](../tests/extended_tls_record_execution.rs)
remain the 308-command ChaCha regression, with only explicit suite arguments
added in its Lanius fixtures. Existing composed authentication and performance
fixtures have the same direct migration; their expected byte artifacts are
unchanged.

[extended_tls_record_aes_execution.rs](../tests/extended_tls_record_aes_execution.rs)
adds an independent SHA-256/HMAC label peer and OpenSSL EVP AES-128-GCM
record oracle. It supplies authenticated ciphertext to the opener rather
than relying only on native round trips. Accepted gates are:

| Accepted gate | Protocol commands |
| --- | ---: |
| `aes_tls13_records_match_openssl_over_types_sizes_padding_and_strides` | 86 |
| `aes_record_limits_reserve_old_keyupdate_slot_and_reset_only_with_new_key` | 32 |
| `aes_record_failures_poison_without_publishing_and_retry_metadata_atomically` | 102 |
| `ordinary_aes_record_consumer_owns_secret_and_updates_cached_key` | Separate executable |

Cases include all protected types, full-size content and padding, both
physical layouts, nonzero offsets, guards/suffixes, retryable bounds/capacity
errors, authenticated invalid inner messages, poison persistence, and wrong
suite, sequence or secret. The same-secret wrong-suite packet is independently
sealed with OpenSSL ChaCha20-Poly1305 and must fail AES authentication before
scratch changes.

Private fixture seams make sequences immediately below, at and above the
AES record cap reachable without millions of operations. They are not a
public arbitrary-state import/resumption API. A limit lifecycle sends an
application record at `limit−2`, a complete KeyUpdate handshake frame at
`limit−1`, then updated-secret records at sequence zero and one; all four
wire records are checked against the independent peer. It asserts the due
signal, exhaustion, unchanged destination on refusal, suite preservation and
the reset after complete derivation. The ordinary consumer owns its secret
after source overwrite and checks records before/after update without error
projection or private state access.

The unchanged three-test ChaCha target passed in **12.37 s**, with all
**308 protocol commands** and its ordinary consumer. The new four-test AES
target passed in **15.90 s**, with **220 protocol commands** and its ordinary
consumer. Each driver invocation compiled a protocol ELF once through
`OnceLock` and an ordinary consumer separately: **four strict ELFs total**.
ChaCha ran two protocol native processes plus its consumer; AES ran three
protocol processes plus its consumer: **seven native processes total**.
All memory traces for `mmap`, `munmap`, `mremap` and `brk` were empty.
Protocol timeouts are 30 seconds and ordinary-consumer timeouts 10 seconds.
The fresh joint Rust driver build took **1.31 s**. These are whole admission
timings, not AEAD throughput measurements.

Accepted source SHA-256 is
`fc1be5f65cc9719dc4551ea1f7ba4fbd6741ab8c9347e9616b9cbb887f77ff7c`;
the new AES driver is
`06aff23ecf90375aaea59a6504ffa6b5fe4ae669f33f16634ba0120f7a07e02a`.
Local ignored logs under `target/stdlib-work/tls-connection-admission/` are
`build-records.log`, `record-regression.log` and `record-aes.log`.
The AES whole-target invocation was:

```sh
RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
LANIUS_DEBUG_STAGE_ERRORS=1 timeout --kill-after=2s 100s \
  flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s \
  target/stdlib-build/debug/deps/extended_tls_record_aes_execution-281831baaa9a8bc4 \
  --nocapture --test-threads=1
```

The ChaCha invocation used the same environment, wrapper and flags with
`target/stdlib-build/debug/deps/extended_tls_record_execution-ece0ab2532f0d157`.
Binary suffixes identify these local builds and may differ after a fresh
build. Independent source/oracle review of the frozen integration found no
concrete issues; it did not add execution or security-audit claims.

The [current source comparison](library-foundation-performance.md#explicit-record-suites-and-aes-gcm-integration)
uses the existing authentication workload and the same compiler binary for
both variants. Its warmed compilation median increased by 4.1% and its ELF
grew by 36.6%; the source closure adds AES and AES-GCM. This measures the
library integration's compilation/output cost, not AES throughput. Previous
performance evidence below applies to the earlier ChaCha implementation.

## Prior ChaCha admission

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
The earlier paired performance comparison above predates the new schedule
dependency. The [current authentication workload](library-foundation-performance.md#tls-authentication-foundation-workload)
measures a combined consumer containing this expanded closure, without a
paired baseline. Record correctness does not establish handshake sequencing,
peer authentication or a complete TLS connection.

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
