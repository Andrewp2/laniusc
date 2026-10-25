# TLS selected-hash transcript and key schedule

`ext::tls_transcript` hashes complete framed handshake messages.
`ext::tls_schedule` implements the TLS 1.3 SHA-256/SHA-384 schedule,
HKDF-Expand-Label, Finished, exporters and ticket PSKs. Both use fixed local
storage without allocation or host services. **The selected-hash migration
passed runtime admission on 2026-10-25 for GPU-compiled native x86_64 Linux
output.** Four separate exact invocations passed 232 protocol commands plus
one ordinary consumer. User GPU execution, other targets and throughput are
not established. Earlier SHA-256-only receipts remain separate below.

The algorithm follows [RFC 8446 sections 4.4.1, 4.4.4 and
7](https://www.rfc-editor.org/rfc/rfc8446.html#section-4.4.1). These components
supply hash/schedule mechanics, not semantic handshake sequencing, negotiated
suite provenance, certificate authentication or a TLS connection. The caller
selects the suite hash and the correct directional secrets/checkpoints.
ECDHE input length is independent: current X25519/P-256 shared secrets are
32 bytes even when SHA-384 produces 48-byte schedule values.

## Owned selected-hash values

```text
Secret { algorithm: ext::tls_hash::Algorithm, bytes: [u8;48] }
secret_from_view(algorithm, bytes: View<u8>) -> Result<Secret, Error>
Secret.view(&self) -> View<u8>
max_output(algorithm) -> i32
```

The two `Algorithm` variants are `Sha256` and `Sha384`. Use
`ext::tls_hash::hash_length(algorithm)` for 32 or 48. `secret_from_view` checks
logical metadata, then exact selected length, copies the active bytes, and
zeros the inactive tail. SHA-256 secrets own 48-byte storage with a canonical
16-byte zero tail; SHA-384 uses all 48. Returned derivations keep that
canonical form. The hash is never inferred from a supplied array width.

Transcript checkpoints use the separate owned
`ext::tls_hash::Digest { algorithm, bytes:[u8;48] }`. Import a raw checkpoint
with the hash module's checked `digest_from_view`, not a fabricated length.
The digest constructor reports its own `InvalidLength`; the schedule reports
`InvalidSecretLength` for raw secret construction. Public implementation
fields are not a validated restoration or serialization format.

`Secret.view` and `Digest.view` borrow stable `&self` receivers. Their active
views remain valid only while the same referent stays live, unchanged and at
the same location. Bind returned results to owned locals before borrowing;
never retain a view obtained from a copied receiver or chained temporary.
Schedule phase results, snapshots and durable outputs remain owned values.
The implementations retain no borrow of supplied PSKs, ECDHE inputs, hashes,
labels or contexts. Phase/digest copies have independent inline storage.

## Checked label derivation

Here `View`, `Result` and `Digest` abbreviate `core::slice::View`,
`core::result::Result` and `ext::tls_hash::Digest`.

```text
expand_label(base: Secret, label: View<u8>, context: View<u8>, output: View<u8>)
    -> Result<i32, Error>
derive_secret(base: Secret, label: View<u8>, hash: Digest)
    -> Result<Secret, Error>
finished(base: Secret, hash: Digest) -> Result<Secret, Error>
verify_finished(base: Secret, hash: Digest, received: View<u8>)
    -> Result<bool, Error>
update_traffic(base: Secret) -> Result<Secret, Error>
```

`expand_label` takes a raw label of 1..249 bytes, encoded context of at most
255 bytes, and requested output of 0..`max_output(base.algorithm)`. The caps
are 8160 for SHA-256 and 12240 for SHA-384, exactly 255 HKDF blocks. It adds
`tls13 ` and encodes the output length, prefixed-label length, label, context
length and context. No NUL terminator is added. The output view's length is
the requested length, including zero; binary labels/context are preserved.

All supplied view metadata is checked before semantic limits or writes.
`expand_label` then checks label, context and output lengths, in that order.
`derive_secret` checks label metadata, digest/secret hash agreement, then
label semantics through `expand_label`; it does not rehash the checkpoint.
`verify_finished` checks received metadata, hash agreement, then exact received
length. Hash mismatch returns `HashMismatch` before cryptographic work.
All returned errors preserve caller output. Views need actual backing;
writable output must be disjoint from every input and source state.

The schedule errors are `Bounds`, `InvalidSecretLength`, `HashMismatch`,
`InvalidLabelLength`, `ContextLimit`, `OutputLimit`, `InvalidVerifyLength`
and `Derivation`. The old raw-checkpoint `InvalidHashLength` API is removed;
checkpoint construction now belongs to `tls_hash`. No SHA-256 default or
compatibility overload remains.

## Typed phases and checkpoints

```text
early(algorithm, psk: View<u8>) -> Result<Early, Error>
no_psk(algorithm) -> Early
```

Each phase wrapper owns one tagged `Secret`. Methods derive independent
values without consuming or mutating the phase; the receiver carries the
algorithm, so methods take no second hash selector.

| API | Label or operation |
| --- | --- |
| `Early.binder(BinderKind::{External,Resumption}) -> Secret` | `ext binder` / `res binder`, with Hash(empty) |
| `Early.traffic(client_hello: Digest) -> Result<Secret, Error>` | `c e traffic` |
| `Early.exporter(client_hello: Digest) -> Result<EarlyExporter, Error>` | `e exp master` |
| `Early.handshake(shared: View<u8>) -> Result<Handshake, Error>` | Derive `derived`, then Extract actual ECDHE bytes |
| `Early.handshake_no_dhe() -> Handshake` | The same extraction with HashLen zero bytes |
| `Handshake.traffic(side, server_hello: Digest) -> Result<Secret, Error>` | `c hs traffic` / `s hs traffic` |
| `Handshake.master() -> Master` | Derive `derived`, then Extract HashLen zero bytes |
| `Master.traffic(side, server_finished: Digest) -> Result<Secret, Error>` | `c ap traffic` / `s ap traffic` |
| `Master.exporter(server_finished: Digest) -> Result<Exporter, Error>` | `exp master` |
| `Master.resumption(client_finished: Digest) -> Result<Resumption, Error>` | `res master` |
| `Resumption.ticket(nonce: View<u8>) -> Result<Secret, Error>` | Expand `resumption`, nonce context 0..255 bytes |

`Side` is Client or Server. Explicit no-PSK/no-DHE/master paths use **32 or
48 zero IKM bytes**, according to the receiver's algorithm. An explicitly
supplied empty PSK/shared message remains distinct. Actual ECDHE inputs are
not padded or truncated to HashLen. A PSK-only protocol must separately ensure
its negotiation permits the no-DHE helper.

Application/exporter checkpoints include server Finished; resumption includes
client Finished. A Finished value uses the checkpoint before its own frame is
appended. Binder computation needs the caller's correctly truncated ClientHello
checkpoint. CertificateVerify and negotiation belong to their own layers.
`finished` derives the selected-length key and authenticates the selected
checkpoint; verification compares every active byte before returning a mismatch.
That is a source-level contract, not a constant-time compiler claim.

`Exporter.export(label, raw_context, output)` and `EarlyExporter.export` keep
distinct receiver types. They derive with the selected Hash(empty), hash the
raw context with the same algorithm, then expand `exporter` to output.length.
Raw contexts can exceed 255 bytes because their digest becomes the encoded
context. Absence and empty context coincide. Bounds, label semantics and
selected output cap precede hashing or mutation. Traffic updates derive
`traffic upd` without changing the exporter master secret.

## Complete handshake transcripts

`tls_transcript::new(algorithm)` creates an owned state. `algorithm()`,
`messages()`, `used_hrr()` and `borrow()` observe it. `snapshot()` returns an
independent tagged Digest by finishing a copy; the original remains open.
State copies fork their progress and retain no input borrow.

`update(frame)` requires exactly one type/u24-length/body handshake frame,
including its four-byte header. It accepts no record header, concatenated
frames or fragments. Unknown real types are hashed without interpreting
bodies. Ordinary update rejects synthetic type 254. Metadata, framing,
synthetic-type rejection, message-count overflow and aggregate byte limit
precede commit. The shared byte ceiling is `2^61-1` for either hash; the
message counter is u64 and a body uses the encoded 24-bit length.

`rewrite_for_hrr(hrr_frame)` requires a completely framed ServerHello with the
32-byte HRR magic random at frame offset 6. It needs exactly one prior
ClientHello and no previous rewrite. The replacement hashes the synthetic
`message_hash` frame and then HRR. Synthetic staging owns 52 bytes but hashes
exactly 36 for SHA-256 or 52 for SHA-384: header `fe 00 00 20` or `fe 00 00 30`,
then the active CH1 digest. It never hashes an inactive tail. Success reports
two messages and permits CH2; all returned errors leave the original state
unchanged. The caller validates the remaining HRR schema and negotiation.

Transcript errors remain `Bounds`, `InvalidFrame`, `SyntheticMessage`,
`InvalidHrrState`, `LengthOverflow` and `Hash`. Input must be immutable,
physically backed and disjoint from State throughout each call. No call
allocates or uses a host service, and no secure-erasure guarantee is made.

## SHA-384 cost composition for budget owners

The schedule itself exposes **no public costing API**. Engine/authentication
owners charge their cumulative work budget before calls. SHA-256 tariffs stay
unchanged where work is unchanged. The selected SHA-384 branch uses the
reviewed compression unit `C=16384`, plus conservative copy/state allowances:
4096 per wrapper setup/state node and 32 per traversed logical byte. These are
source-based abstract work units, not ABI widths, instructions or time.

For the actual source call tree define:

```text
B(n) = ceil((n+17)/128)
N = ceil(o/48), info = 10+l+c
EC(l,c,o) = 0                                  if o=0
EC(l,c,o) = 2 + sum(i=1..N)[B(info+1+(i>1?48:0))+1] otherwise
H(n) = C*B(n) + 8192 + 32*(n+48)
M(n) = C*(3+B(n)) + 12288 + 32*(1024+n)
E(l,c,o) = C*EC(l,c,o) + 4096*(N+2)
           + 32*(1024+l+c+N*(info+97)+o)
```

`H` covers a fresh hash including finalization. `M` covers HMAC with a key no
longer than 128 bytes; all TLS SHA-384 secret keys are 48 bytes. `E` covers
ExpandLabel, including label staging even for zero output. HKDF seeds two pad
blocks once; each output block resets the owned state, hashes previous output
when present, info and counter, then the outer digest. The 97-byte term allows
48 previous bytes, one counter and 48 outer-digest bytes. State copying,
fixed 514-byte staging and canonicalization are covered by the node/fixed
allowance. Charge additional phase-wrapper bookkeeping consistently where a
budget owner includes it; these formulas do not reset or refund budgets.

| Operation | Composed allowance | SHA-384 compressions |
| --- | --- | ---: |
| `no_psk` | `M(48)` | 4 |
| `Early.handshake(shared32)` | `H(0)+E(7,48,48)+M(32)` | 9 |
| `Handshake.master` | `H(0)+E(7,48,48)+M(48)` | 9 |
| One handshake traffic value | `E(12,48,48)` | 4 |
| Complete handshake schedule, excluding snapshots/record owners | `2*M(48)+M(32)+2*H(0)+2*E(7,48,48)+2*E(12,48,48)` | 30 |
| Two application traffic values plus exporter master | `2*E(12,48,48)+E(10,48,48)` | 12 |
| Finished or verification | `E(8,0,48)+M(48)` | 8 |
| One record key32 / IV12 setup | `E(3,0,32)+E(2,0,12)` | 8 |
| Record KeyUpdate including new key/IV | `E(11,0,48)+E(3,0,32)+E(2,0,12)` | 12 |
| Export(label length l, context length n, output length o) | `H(0)+E(l,48,48)+H(n)+E(8,48,o)` | Formula above |

For exporter expansion with positive output, `EC(8,48,o)=3*N+1`; the later
blocks cross the SHA-384 padding boundary. At maximum label/context lengths,
encoded info is 514 bytes and each block costs at most five inner plus one
outer compression. Output cannot exceed 255 blocks. Add the actual transcript
snapshots separately: one final compression for residue below 112, else two.
An update adds `floor((residue+input_length)/128)` compressions. HRR needs the
CH1 snapshot and hashing of its 52-byte synthetic prefix plus HRR. Use checked
quota arithmetic and reject before mutation when a debit cannot be admitted.

These operation formulas track the current source and bound copies/traversals
without depending on physical View width. They do not establish performance
or a wall-clock bound. Exact and one-short budget tests belong to the consuming
engine/authentication gates.

## Accepted selected-hash verification

The current [driver](../tests/extended_tls_schedule_execution.rs) and
[fixtures/model](../tests/fixtures/extended/tls_schedule/) passed all four exact
gates on frozen sources, without a failed gate or source change in this cohort:

| Exact test | Accepted cases | Elapsed |
| --- | ---: | ---: |
| `labels_phases_finished_exporters_and_rfc8448_anchors_match_independent_peer` | 84 protocol commands, including 12 unchanged SHA-256 RFC8448 anchors | 8.10 s |
| `checked_label_lengths_bounds_and_output_limits_preserve_all_output` | 92 protocol commands | 7.42 s |
| `complete_transcripts_snapshots_copies_hrr_and_error_atomicity_match_hashlib` | 56 protocol commands / 1040 transcript actions | 7.81 s |
| `ordinary_imported_schedule_and_transcript_consumer_has_no_error_projection` | One native consumer exercising both hashes | 5.99 s |

The protocol total is 232 commands. The independent Python model uses
`hashlib`/`hmac` and binary transport, and selects its hash explicitly for each
command. Every observation compares complete active output bytes. Tests retain
packed/strided nonzero-start inputs, unchanged source regions and output
sentinels, all 32/48 Finished mismatch positions, mismatch error precedence,
secret copy independence, zero tails, exporter/HKDF output caps, HRR 36/52,
transcript forks/snapshots and error atomicity. Test-only counter changes reach
overflow without adding an arbitrary-state public constructor. Boundary actions
cover selected block/padding sizes and mutate returned snapshot copies.

`OnceLock` can share the protocol ELF within one driver process. These accepted
gates used **four separate exact invocations, four independently compiled
strict ELFs and four native processes**, rather than one whole-target run.
Every native mmap/munmap/mremap/brk trace was empty. The joint fresh Rust driver
build, which also included authentication, took **1.24 s**; it was not an
isolated application compilation measurement. Its ignored local log is
`target/stdlib-work/tls-sha384-schedule-auth-build-first.log`.

| Exact test selection | Ignored local runtime log |
| --- | --- |
| Ordinary consumer | `target/stdlib-work/tls-sha384-schedule-ordinary-first.log` |
| Labels/phases | `target/stdlib-work/tls-sha384-schedule-labels-first.log` |
| Bounds | `target/stdlib-work/tls-sha384-schedule-bounds-first.log` |
| Transcript | `target/stdlib-work/tls-sha384-transcript-first.log` |

The verified frozen SHA-256 source hashes are:

| Source | SHA-256 |
| --- | --- |
| `extended/ext/tls_schedule.lani` | `2fcd8958ab4b50157ef57fa6890307a3080e84ba7c50e77a17397ed248bf54bc` |
| `extended/ext/tls_transcript.lani` | `dd19a14e978c0949052a484c3fee4cc4b28865879c3117ae5084ed46e9cb2c5b` |
| `tests/extended_tls_schedule_execution.rs` | `0818edd1b95509ca9d0686a61f9ffbfc65b8c211e95678b79a05453ad6efdae9` |
| `tests/fixtures/extended/tls_schedule/plain.lani` | `9b24bcfbc0fc86252b61fb1d8b4d6eb961a9bffc7f9fe2b5a58ed8508ed1a40e` |
| `tests/fixtures/extended/tls_schedule/protocol.lani` | `6b1be549d0ae55ba1cf49f1c7d5170d7240baae216d44db58cd78ef15ea1a43c` |
| `tests/fixtures/extended/tls_schedule/model.py` | `63574667bebc375bd8f18500f94e0106c9fa7289881c04578e860df9a7e638a8` |

After admission, only the two module header comments changed to stable
ownership wording; executable code and line numbers are unchanged, and the
hashes above continue to identify the executed versions.

The source base was `e32b2fbfb77fa25ec0e5b0a83905d5c9c34faff3` with the
frozen integration additions. An equivalent bounded joint rebuild command is:

```sh
timeout --kill-after=2s 100s flock -E 75 -w 35 \
  target/stdlib-work/library-gpu.lock timeout --kill-after=2s 60s \
  env CARGO_TARGET_DIR=/home/andrew-peterson/code/laniusc/target/stdlib-build \
  CARGO_INCREMENTAL=0 CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  cargo test --test extended_tls_schedule_execution \
  --test extended_tls_authentication_execution --no-run \
  > target/stdlib-work/tls-sha384-schedule-auth-build-first.log 2>&1
```

Each exact runtime selection used this wrapper with the name and log above;
the example records the ordinary consumer. Repeat it separately for the other
three exact names in the table, rather than dropping `--exact`:

```sh
test_name=ordinary_imported_schedule_and_transcript_consumer_has_no_error_projection
RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
  LANIUS_DEBUG_STAGE_ERRORS=1 timeout --kill-after=2s 100s \
  flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s \
  target/stdlib-build/debug/deps/extended_tls_schedule_execution-5d5de7218a67902b \
  --exact "$test_name" --nocapture --test-threads=1 \
  > target/stdlib-work/tls-sha384-schedule-ordinary-first.log 2>&1
```

These are correctness, copy/error atomicity, interoperability and native
allocation observations. They do not establish a full connected TLS profile,
other targets or isolated performance.

## Historical SHA-256-only admission

These receipts describe the earlier SHA-256-only source and raw-view API.
They remain historical evidence; they do not admit the current selected-hash
implementation; its separate accepted gates are recorded above.

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
