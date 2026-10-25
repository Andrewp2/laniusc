# TLS SHA-256 transcript and key schedule

`ext::tls_transcript` hashes complete framed handshake messages.
`ext::tls_schedule` implements the TLS 1.3 SHA-256 key schedule, checked
HKDF-Expand-Label, Finished, exporters and ticket PSKs. Both are Lanius code
with fixed local storage and no allocation. Accepted on 2026-10-24 for native
x86_64 Linux output from GPU compilation. User GPU kernels and other execution
targets remain unverified.

The algorithms follow [RFC 8446 sections 4.4.1, 4.4.4 and 7](https://www.rfc-editor.org/rfc/rfc8446.html#section-4.4.1),
with published intermediate anchors from [RFC 8448 section 3](https://www.rfc-editor.org/rfc/rfc8448.html#section-3).
These modules do not establish a TLS connection, authenticate a peer, validate
certificates or enforce the semantic handshake state machine. SHA-384 cipher
suites are outside their scope. The caller selects the correct directional
secrets and transcript checkpoints.

## Checked label derivation

All byte arguments are `core::slice::View<u8>`:

```text
expand_label(base, label, context, output) -> Result<i32, Error>
derive_secret(base: Secret, label, transcript_hash) -> Result<Secret, Error>
finished(base, transcript_hash) -> Result<Secret, Error>
verify_finished(base, transcript_hash, received) -> Result<bool, Error>
update_traffic(base) -> Result<Secret, Error>
```

`Secret { bytes: [u8; 32] }` owns its bytes; `Secret.view()` borrows them.
`expand_label` requires an exact 32-byte base, a raw label of 1 through 249
bytes, context of at most 255 bytes, and requested output of 0 through 8160
bytes. It adds the six-byte `tls13 ` prefix and encodes the two-byte output
length, one-byte prefixed-label length, label, one-byte context length and
context. No NUL terminator is added. The output view's length is the requested
length, including zero. Binary labels/context are preserved exactly; application
protocols enforce any registered-label restrictions themselves.

Logical bounds for all arguments precede semantic limits. `expand_label` then
checks base length, label length, context length and output length, in that
order. Its errors are `Bounds`, `InvalidSecretLength`, `InvalidHashLength`,
`InvalidLabelLength`, `ContextLimit`, `OutputLimit`, `InvalidVerifyLength` and
`Derivation`. Derive-Secret requires an exact 32-byte supplied transcript hash;
it does not hash that hash again. Its logical bounds precede hash length and
label validation. All returned errors preserve caller output. Output must be
writable, physically backed and disjoint from every input and the source state.

## Typed phases

| API | Meaning |
| --- | --- |
| `no_psk() -> Early` | Extract 32 zero IKM bytes using the zero salt |
| `early(psk) -> Result<Early, Error>` | Extract the supplied PSK bytes, including a supplied empty PSK |
| `Early.binder(BinderKind::{External,Resumption}) -> Secret` | `ext binder` / `res binder`, with Hash(empty) |
| `Early.traffic(client_hello_hash) -> Result<Secret, Error>` | `c e traffic` |
| `Early.exporter(client_hello_hash) -> Result<EarlyExporter, Error>` | `e exp master` |
| `Early.handshake(shared) -> Result<Handshake, Error>` | Extract supplied DHE bytes using Derive-Secret(`derived`, Hash(empty)) as salt |
| `Early.handshake_no_dhe() -> Handshake` | The same extraction with 32 zero IKM bytes |
| `Handshake.traffic(Side::{Client,Server}, server_hello_hash) -> Result<Secret, Error>` | `c hs traffic` / `s hs traffic` |
| `Handshake.master() -> Master` | Derive `derived` with Hash(empty), then Extract 32 zero IKM bytes |
| `Master.traffic(side, server_finished_hash) -> Result<Secret, Error>` | `c ap traffic` / `s ap traffic` generation zero |
| `Master.exporter(server_finished_hash) -> Result<Exporter, Error>` | `exp master` |
| `Master.resumption(client_finished_hash) -> Result<Resumption, Error>` | `res master` |
| `Resumption.ticket(ticket_nonce) -> Result<Secret, Error>` | Expand label `resumption`, nonce context of 0 through 255 bytes |

Phase methods derive independent values; they do not consume or mutate the
phase. Copies retain independent secret bytes. They retain no borrow of PSKs,
shared secrets or transcript hashes. Use constructors and methods; public
implementation fields are not a validated serialized state format. The
explicit no-PSK/no-DHE path uses **32 zero bytes**, which is different from an
explicitly supplied empty input message. A PSK-only protocol may call the
no-DHE path only where its negotiation permits it.

The hash named `server_finished_hash` includes the server's Finished frame.
The resumption hash includes the client's Finished frame. A Finished value is
computed using the hash **before** its own frame is appended. PSK binder
Finished generation uses the separately derived binder key as its base and a
correctly truncated ClientHello transcript hash supplied by the caller.
CertificateVerify signature context construction and validation remain the
handshake implementation's responsibility; this module performs no signature
operation.

`finished` expands `finished` with empty context and HMACs the supplied
32-byte transcript hash. `verify_finished` checks all three logical ranges,
base length, hash length and exact 32-byte received value before computation.
It compares every byte, with no early mismatch return; a mismatch returns
`Ok(false)`. The caller must make a failed verification terminal at the TLS
connection layer. `update_traffic` derives `traffic upd` with empty context.

## Exporters

`Exporter.export(label, raw_context, output)` and
`EarlyExporter.export(label, raw_context, output)` have distinct receiver types
and both return `Result<i32, Error>`. They compute:

```text
derived = Derive-Secret(exporter_master, label, Hash(empty))
output = HKDF-Expand-Label(derived, "exporter", Hash(raw_context), output.length)
```

Raw context can exceed 255 bytes because its 32-byte hash is the HKDF label
context. Empty context represents both absent and empty application context.
Bounds, label length and output length are checked before hashing or writing.
Callers use the regular exporter unless their protocol explicitly selects the
early exporter. No API conflates those master secrets.

## Complete handshake transcripts

`tls_transcript::new()` returns a State. `State.update(frame)` requires exactly
one complete handshake frame: one type byte, a big-endian 24-bit body length,
and exactly that many body bytes. Record headers, fragmented input and
concatenated frames are not accepted. Unknown real message types are hashed
without interpreting their bodies. Synthetic `message_hash` type 254 is
reserved for the explicit HRR operation and rejected by ordinary update.

`State.snapshot()` finishes a copy of the running SHA state and returns an
independent `core::sha256::Digest`; the original remains open for updates.
State copies fork transcripts. `messages()` counts original handshake messages,
including ClientHello1 after a rewrite, and `used_hrr()` reports whether the
special operation occurred. `borrow()` supplies a reference. Construct a new
state for a separate handshake; no implicit reset occurs.

`State.rewrite_for_hrr(hrr_frame)` accepts only an exactly framed ServerHello
large enough to contain the full RFC HelloRetryRequest magic random, whose
32 bytes at frame offset six must match. The state must contain exactly one
prior message, that message must be a ClientHello type 1, and no previous
rewrite may have occurred. It replaces the running transcript with:

```text
254 || 00 00 20 || SHA256(ClientHello1) || HelloRetryRequest
```

The caller validates the rest of the ServerHello schema, negotiation,
extensions and legal HRR timing. An ordinary ServerHello cannot pass the
magic check. A successful rewrite reports two messages and leaves the state
open for ClientHello2. Its synthetic header is hashed once.

Transcript errors are `Bounds`, `InvalidFrame`, `SyntheticMessage`,
`InvalidHrrState`, `LengthOverflow` and `Hash`. Update checks logical bounds,
exact framing, synthetic-type rejection, frame-count overflow and SHA total
length before committing state. Rewrite checks logical bounds, exact framing,
type/magic, then prior-state conditions. Every returned error leaves all state
unchanged. Inputs must be immutable, physically backed and disjoint from the
state. No input borrow survives a completed call. Aggregate SHA byte length is
limited to `2^61 - 1`; a single body is limited by its 24-bit encoded length.

## Resource and security limits

No call allocates or uses a host service. Work is linear in message/context
bytes plus HKDF's requested output block count; no wall-clock bound is
provided. Hash/phase/digest copies are ordinary value copies. Secret buffers
are not securely erased, and generated machine code has not been proven
constant time. Full-byte Finished comparison is a source-level contract.
Transcript parsing branches on public framing bytes. These modules are not a
substitute for a complete TLS handshake or a cryptographic security audit.

## Admission

[extended_tls_schedule_execution.rs](../tests/extended_tls_schedule_execution.rs)
compiles a protocol fixture and a separate ordinary consumer. The protocol uses
an independent Python `hashlib`/`hmac` peer over binary commands. RFC8448 section
3 handshake bytes are retained in `rfc8448-1rtt-handshakes.bin`; its five hashes
are ordered ClientHello, ServerHello, server Finished, client Finished, and
pre-server-Finished. Tests check published early/handshake/master/traffic/
exporter/resumption secrets, both Finished values and ticket PSK anchors.

Additional cases vary PSKs, DHE inputs, no-secret paths, exporter sizes,
maximum labels/contexts/output, packed and strided backing, malformed logical
ranges, phase hash lengths, all 32 Finished mismatch positions, frame errors,
transcript snapshots/copies and HRR acceptance/rejection. Test-only counter
setup reaches SHA and message-count overflow without inventing a public
arbitrary-state constructor. Sentinels check unchanged rejected output and
sources. Drivers assert empty allocation traces. The ordinary consumer avoids
error-enum projections.

| Accepted gate | Cases | Evidence |
| --- | ---: | --- |
| `checked_label_lengths_bounds_and_output_limits_preserve_all_output` | 46 protocol commands | Passed in the initial invocation |
| `complete_transcripts_snapshots_copies_hrr_and_error_atomicity_match_hashlib` | 26 protocol commands, 460 transcript actions | Passed in the initial invocation |
| `ordinary_imported_schedule_and_transcript_consumer_has_no_error_projection` | One native consumer | Passed in the initial invocation |
| `labels_phases_finished_exporters_and_rfc8448_anchors_match_independent_peer` | 42 protocol commands and 12 published RFC anchors | Passed in the corrected exact invocation, 6.95 s |

The unique accepted protocol total is **114 commands**, plus the ordinary
consumer. Accepted observations come from four native processes across two
driver invocations, producing three strict ELFs: the initial shared protocol
and ordinary consumer, and the corrected invocation's protocol. Including the
initial labels attempt gives five native attempts; that attempt is preserved
as failure history below. The driver asserts no `mmap`, `munmap`, `mremap` or
`brk` calls in its native memory traces.

The initial fresh joint Rust build took 1.46 seconds; the corrected schedule
and handshake driver build took 1.27 seconds. Both linked
`target/stdlib-build/debug/deps/extended_tls_schedule_execution-5d5de7218a67902b`.
The accepted runtime commands were:

```bash
RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
LANIUS_DEBUG_STAGE_ERRORS=1 timeout --kill-after=2s 100s \
  flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s \
  target/stdlib-build/debug/deps/extended_tls_schedule_execution-5d5de7218a67902b \
  --nocapture --test-threads=1 \
  > target/stdlib-work/tls-auth-admission/schedule-transcript.log 2>&1

RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
LANIUS_DEBUG_STAGE_ERRORS=1 timeout --kill-after=2s 100s \
  flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s \
  target/stdlib-build/debug/deps/extended_tls_schedule_execution-5d5de7218a67902b \
  --exact labels_phases_finished_exporters_and_rfc8448_anchors_match_independent_peer \
  --nocapture --test-threads=1 \
  > target/stdlib-work/tls-auth-admission/schedule-rfc-corrected.log 2>&1
```

The first command passed three tests and failed one in 8.01 seconds. The
second command is the successful rerun of the affected group. These are
correctness and allocation observations. The
[current authentication workload](library-foundation-performance.md#tls-authentication-foundation-workload)
now measures the combined schedule/transcript/codec/signature/record closure.
It has no paired baseline. Full TLS remains open.

### RFC anchor correction history

The initial labels group completed and matched all 42 commands against its
independent Python peer, then failed the separate published anchor assertion
for the server application traffic secret. The Rust anchor contained 63 hex
digits: one `4` had been omitted. Its decoder used `chunks_exact(2)`, which
also silently ignored an unmatched final nibble.

The [primary RFC 8448 section 3](https://www.rfc-editor.org/rfc/rfc8448.html#section-3)
confirms the 32-byte value:

```text
a11af9f05531f856ad47116b45a950328204b4f44bfb6b3a4b4f1f3fcb631643
```

Only that test constant and an even-length assertion in the test decoder were
changed. Production modules, Python oracle, native fixtures and assertion
coverage remained unchanged. All other eleven anchor strings already had 64
hex digits. The corrected exact group passed all twelve published anchors.
The original driver is retained locally as
`target/stdlib-work/tls-auth-admission/schedule-driver-original.rs`; build logs
are `build-auth-foundations.log` and
`build-schedule-corrected-handshake.log` in that directory.
