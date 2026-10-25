# Owned nonblocking TLS over TCP

[`ext::tls_tcp`](../extended/ext/tls_tcp.lani) owns a connected nonblocking
Linux TCP socket, preallocated buffers and a readiness set above the portable
[`ext::tls_connection`](../extended/ext/tls_connection.lani) engine. Protocol,
certificate validation and cryptography remain in Lanius. OpenSSL appears
only in the independent test peers.

This adapter inherits the engine's explicit TLS profile and certificate
policy. It adds transport ownership, bounded host attempts, absolute monotonic
deadlines and retained partial I/O. It does not supply DNS resolution,
connection establishment, a listener, implicit trust anchors or client
certificate authentication. Numeric connect and accept can happen outside
attachment using single-attempt socket methods and the shared host budget.

**SHA-384 suite-migration admission passed all 122 native cases.** Nine
focused selections ran across three shared strict protocol ELFs and three
driver invocations. Current source uses the
owned [`tls_suite::Policy`](../extended/ext/tls_suite.lani) contract for
ChaCha20-Poly1305/SHA-256, AES-128-GCM/SHA-256 and AES-256-GCM/SHA-384.
X25519 and secp256r1 remain independent group choices under the
[group contract](tls-group-integration-plan.md). The accepted 91-case group
checkpoint and earlier receipts below identify their exact historical
snapshots separately from this migration.

## Attachment and ownership

```lanius
host_budget(calls: u64) -> HostBudget
HostBudget.borrow() -> &HostBudget
HostBudget.remaining() -> u64
HostBudget.permit() -> Result<i32, Error>
HostBudget.reserve(calls: u64) -> Result<i32, Error>
HostBudget.now() -> Result<Instant, Error>
HostBudget.check(deadline: Deadline) -> Result<Instant, Error>

attach_client(socket: &Socket, config: tls_connection::ClientConfig,
              deadline: Deadline, budget: &HostBudget)
    -> Result<Connection, Failure>
attach_server(socket: &Socket, config: tls_connection::ServerConfig,
              deadline: Deadline, budget: &HostBudget)
    -> Result<Connection, Failure>
```

The caller retains the original socket on **every attachment failure**. The
adapter checks the actual kernel `SO_TYPE`, `SO_PROTOCOL` and `SO_DOMAIN`,
then `is_nonblocking()` and the connected peer address. Socket metadata alone
cannot establish these properties. A blocking socket, UDP descriptor, wrong
family or unconnected descriptor fails before entropy or handshake I/O.
Attachment never changes descriptor flags, connects or duplicates the socket.
The adapter validates the owned suite policy before host access or
acquisition. `ClientConfig.suites` and `ServerConfig.suites` replace the
former preferred-suite field; no implicit fallback may escape the active
policy. The engine owns selected-hash binding, transcript state, key
derivation and exporter limits. The adapter does not infer a hash from a
group or reinterpret a 32-byte shared secret as a 48-byte secret.

All allocations precede entropy and engine construction:

- Six packed `Vec<i32>` owners back the engine's record, decryption, handshake,
  retained hello/cookie, pending wire and application regions. Sizes come from
  `tls_connection::required_buffers(config.limits)`; no capacity rounding is
  assumed.
- One typed vector contains the engine's path workspace.
- One packed vector retains at most 1,024 newly received raw bytes.
- Two vectors form a one-request `PollSet`. Their fixed acquisition is
  explicit so each allocation has a deadline check and partial acquisition
  cleanup is counted.

The ten owners never grow after attachment. The adapter asks
`tls_connection::entropy_layout(config.groups)` for its exact 64-byte
single-group or 96-byte dual-group layout, obtains fresh OS bytes, constructs
the actual engine, and checks the original
deadline again. Only success calls the input socket's `take_handle()` and
transfers ownership. Returned connection copies do not create a second valid
socket, memory or nonce owner. Use one active value and its `borrow()` method.
Keep immutable config, certificate DER, anchor descriptors and other borrowed
config backing live until the connection is destroyed. Preserve all
factory-established state fields; public record fields are not a serialized
resume format or a way to fabricate authentication.

Constructor rollback disarms any constructed engine and releases only newly
acquired buffers. It leaves the caller's socket live. Successful attachment
leaves that original socket owner inactive. Explicit `destroy()` or `abort()`
retires the sole active connection; no automatic destructor is implied.

## Host attempts, entropy and deadlines

`permit()` spends one attempt before one host call. `now()` spends one before
one native monotonic-clock call and rejects reversal. `check(deadline)` first
validates normalized deadline metadata, calls `now()`, then rejects an expired
deadline. Applications can use these methods around their own bounded
file/connect/accept/stdin/stdout calls under the same original deadline. No
counter refunds occur. Copying a host budget forks its allowance; use a shared
borrowed budget for an aggregate bound.

Attachment conservatively reserves **21 call credits** before acquisition:
ten allocations, ten possible release attempts and one invalidating socket
close. Unused credits are not refunded. Actual transport, entropy, clock,
poll and shutdown calls consume additional credits individually. The finite
cleanup allowance stays authorized after ordinary deadline or budget
exhaustion, so stopping cannot force a resource leak. Cleanup has no retry and
cannot become an unbounded extension of the transport operation.

Fresh ephemeral input comes only from
[`std::entropy::read_some`](stdlib-entropy-bounded.md), using one charged
`getrandom(GRND_NONBLOCK)` attempt at a time. Every positive prefix and
Interrupted retry is followed by an original-deadline check. EAGAIN and other
entropy failures stop attachment; partial entropy is discarded and the local
buffer is cleared. There is no xoshiro, timestamp, fixed seed or caller
entropy fallback. This does not claim optimizer-resistant secret erasure.
[Linux getrandom semantics](https://man7.org/linux/man-pages/man2/getrandom.2.html)
explain why nonblocking entropy is needed for this attempt/deadline contract.

The engine's `EntropyLayout` is the only slot-layout authority. ClientHello
random occupies the first 32 bytes; a single enabled group's scalar follows.
With both groups enabled, X25519 occupies `[32,64)` and P-256 `[64,96)`,
independently of preference order. Policy validation precedes host access.
Before and after each constructor admission, the adapter charges a fresh
clock check under the original deadline and shared `HostBudget`.

Only `Engine(InvalidEphemeralScalar)` admits a retry. The engine guarantees
that this rejection precedes X25519 derivation and caller-buffer writes.
The adapter draws at most seven further 32-byte fills into the indicated
P-256 slot, for **eight P-256 candidates total**. Random and X25519 slots
stay unchanged; there is no reduction, clamping, deterministic repair or
group fallback. An eighth rejection returns that original engine error.
Other constructor errors and entropy failures stop immediately. Partial
fills and Interrupted retries consume the same host allowance and original
deadline. All 96 temporary bytes are cleared on every outcome, without a
secure-erasure claim. A successful late constructor is aborted and its new
owners released before the input socket can transfer.

Every connection keeps monotonic history independently of the supplied
operation budget. Renewing an Established operation budget cannot hide clock
reversal. A handshake retains its original absolute deadline, using the
earlier of that deadline and each operation's deadline. The adapter's
irreversible handshake-success flag is committed only after a successful
clock check following protocol/I/O progress. An engine entering Established
after a late Finished acknowledgement cannot renew that deadline or release
application data; the adapter terminates and cleans up instead.

Only an already Established operation's `Deadline` or `CallLimit` stop is
resumable with the same connection state and an explicitly new operation
deadline/budget. Clock reversal, other clock failures, transport failures
and terminal engine errors stop the owner. Clock EINTR retries inside a
connection checkpoint consume attempts; socket/poll Interrupted results are
observed and return bounded progress for a later turn.

Native calls can take time to return despite the selected nonblocking
interfaces, allocation can fault, and the OS can deschedule the process.
Deadlines govern observed progress and publication; they are not hard
real-time cancellation guarantees.

## Transport turns and application bytes

```lanius
struct Progress {
    sent: i32, received: i32, consumed: i32,
    pending_wire: i32, pending_input: i32, pending_plaintext: i32,
    established: bool, peer_closed: bool, local_closed: bool
}
Connection.step(deadline: Deadline, budget: &HostBudget)
    -> Result<Progress, Failure>
Connection.queue_plaintext(input: View<u8>, deadline: Deadline,
                           budget: &HostBudget) -> Result<i32, Failure>
Connection.read_plaintext(output: View<u8>, deadline: Deadline,
                          budget: &HostBudget) -> Result<tls_connection::Read, Failure>
```

One `step()` makes at most one ordinary `Socket.send`, one `Socket.receive`,
one `PollSet.poll_ms`, and one write-half shutdown attempt. A terminal engine
error may add one best-effort fatal-alert send. It uses no `*_until`,
`core::io::write_all` or hidden retry loop. Readiness is advisory: ERR/HUP do
not invent TLS EOF; a later receive observes the actual outcome. Poll timeout
is rounded up from the original deadline's remaining duration and capped at
`i32::MAX` milliseconds. EINTR and EAGAIN consume attempts too.
[Linux send](https://man7.org/linux/man-pages/man2/send.2.html),
[receive](https://man7.org/linux/man-pages/man2/recv.2.html) and
[poll](https://man7.org/linux/man-pages/man2/poll.2.html) define the underlying
progress and readiness behavior.

`sent` and `received` count actual confirmed host bytes in that turn;
`consumed` counts the prefix copied into the engine, including previously
retained input. A successful positive send advances the engine's exact wire
suffix **before** the post-call clock/budget check. A later stop preserves
that cursor; it never reseals or asks the caller to resubmit already accepted
plaintext. A positive receive or EOF is stored before its post-call check.
Late received bytes remain raw and unfed; a resumed Established operation
processes that same event without repeating the host receive. Terminal host
errors retain their primary cause even if the post-call clock also fails.

`queue_plaintext()` has a fresh deadline check before its bounded local
copy/seal. It reports the actual accepted plaintext prefix separately from
transport progress. It may accept zero or report ordinary engine
`WantInput`/`WantRead`/`WantOutput` backpressure; never infer whole-record
acceptance from an empty pending slot. Keep unaccepted application bytes and
drive both reading and writing to avoid bidirectional deadlock.

`read_plaintext()` performs its final fresh deadline check immediately before
the engine copies authenticated bytes into the caller's logical view. No
later clock failure can mislabel an already-mutated destination as an atomic
timeout. It copies no new bytes before adapter handshake confirmation and
never exposes record/handshake scratch. Empty non-EOF progress and ordinary
engine backpressure are distinct from `Read.eof`. Application views can have
nonzero starts and logical strides with live disjoint backing; they are not
retained after these copying calls.

`negotiated()` returns profile information only after adapter authentication.
`export(label, context, output, deadline, budget)` likewise checks the clock
before writing exporter output. Exporter labels/contexts/outputs follow the
portable engine's bounds and disjointness contracts.

## Closure and failure preservation

`begin_close()` requests local close_notify after pending application output.
It can return ordinary backpressure. `request_key_update(bool)` requests a
bounded engine epoch update; it does not call the host. Preserve the engine's
control/error result and drive it with `step()`. A peer close_notify closes
only the read direction; the server may still send its retained echo before
requesting local closure.

Only after the complete local close_notify wire is acknowledged does `step()`
issue `Socket.shutdown(Write)`. Raw TCP EOF without authenticated peer
close_notify is truncation, including a partial TLS frame. Already published
authenticated application bytes are not undone by a later truncation error.

`try_finish()` succeeds only after peer close_notify, local write shutdown,
and draining wire, raw input and authenticated plaintext. `Remaining` leaves
all ownership intact. Success closes the descriptor and releases each buffer
once. Repeated finish/destroy/abort returns the stored cleanup report without
more close/deallocation calls. Explicit `abort(cause)` abandons pending data.

```lanius
struct CloseReport {
    primary: Option<Error>, close_error: Option<core::io::Error>,
    release_attempts: i32, cleanup_calls: u64
}
struct Failure { cause: Error, progress: Progress, cleanup: Option<CloseReport> }
```

Failure progress is captured before terminal cleanup. The first primary
failure remains separate from a later close error. Close invalidates the
owner before its sole host attempt; EINTR/error never causes a close retry.
The existing allocator deallocation API returns `void`: `release_attempts`
counts release attempts and owner disarming, **not proven successful frees**.
The adapter cannot observe a munmap failure through that API. Normal test
traces independently require successful matching releases.

Failed-engine outgoing data is a new fatal alert only when the engine
explicitly marks `fatal_alert_pending()`. The adapter may attempt one bounded
send before cleanup. Existing pending sealed data suppresses that alert;
failure never transmits stale application output or rolls back a spent nonce.
Alert, clock and close failures do not replace the original engine cause.

## SHA-384 migration coverage and admission

The six retained selections still contain 91 cases. Their native fixture
explicitly uses only the preceding two SHA-256 suites, with the original
268,435,456 abstract work credits. Three new exact selections add 31 cases:

- `aes256_sha384_openssl_peers_cover_groups_hrr_key_updates_and_exporters`:
  14 singleton-AES-256 cases cover both roles and groups, fragmented binary
  application bytes, requested-group HRR in both directions, real KeyUpdate
  generation changes and independent OpenSSL exporter agreement.
- `aes256_sha384_tcp_limits_faults_prefixes_and_full_exporter_cap`:
  15 cases compare all 12,240 maximum exporter bytes with the independent
  CLI result, reject 12,241 without changing output or guards, retain six
  real deadline/budget prefix witnesses across both groups, and check
  trust/name/time, EPIPE, terminal work exhaustion and pre-host invalid
  policy rejection. The cap fixture's stdout carries test exporter bytes,
  with zero application bytes accepted; it is not application-data evidence.
- `aes256_sha384_real_tcp_pressure_preserves_default_one_megabyte_streams_in_both_roles`:
  two real 1 MiB duplex streams reuse the exact byte/progress/trace/closure
  and owner-ledger oracle in both roles. They require the untouched default
  64 Gi engine allowance, with no live work-counter mutation or exhaustion
  seam, and retain the small real socket buffers. Actual positive short
  sends and EAGAIN are observed rather than fabricated or required flakily.

Every successful fixture checks the actual negotiated suite ID and group.
OpenSSL CLI peers pin their TLS 1.3 cipher with `-ciphersuites`, so AES-256
cases cannot silently negotiate a SHA-256 alternative. All nine selections
passed, totaling **122 native cases**. The 64/96-byte entropy layouts,
eight-candidate maximum, single owner, original deadlines, shared host
allowance and exact pending
wire/raw-input cursors retain their preceding contracts.

The engine's enlarged default work allowance is 64 Gi abstract credits,
allowing bounded 1 MiB duplex traffic under the conservative AES-256
per-block tariff described in the [hash integration
plan](tls-hash-integration-plan.md). It grants no extra records, bytes,
signature attempts, host calls or wall time, and is not an instruction count
or performance guarantee. The focused AES-256 work-exhaustion fixture instead
uses an explicit 512 Mi credits and maximum-size public exporter requests;
the original SHA-256 exhaustion seam retains 256 Mi credits. No test edits
the live engine's remaining work to manufacture that error.

The first AES-256 pressure attempt is **not admitted**. Its first role
stopped after publishing 524,288 bytes: a post-processing monotonic check
observed 12.1314 s against the fixture's original 12-second deadline. The
expected-success fixture then asserted rather than accepting partial data.
This is evidence of the production deadline being enforced, not a byte
mismatch. The retained failure is
`target/stdlib-work/tls-sha384-tcp-pressure-first.log` (38.68 s including
compilation and orchestration). Its full extracted capture is in ignored
`target/stdlib-work/tls-sha384-pressure-extract/`.

Only the new AES-256 1 MiB pressure cases now receive **one shared 35-second
operation deadline**, never renewed between steps. Their process watchdog
is 45 seconds including bounded cleanup; the helper reserves four seconds
for kill/reap and clips its waits to its case bound. All preceding cases
retain their 12-second fixture deadlines. Production and application
deadlines, 1 MiB/default-work/byte/progress/ownership assertions are unchanged.
This test allowance reflects unoptimized software AES and is not a throughput
claim. The root uses a separate bounded pressure-gate command with a
90-second inner and 100-second outer timeout; GPU compilation retains its
45-second limit. The corrected two-case scale component passed as recorded
below.

Failure diagnostics now print only statuses, lengths, SHA-256 digests,
32-byte prefixes/suffixes and bounded peer/trace tails. Full failure captures
are written only under ignored `target/stdlib-work/tls-tcp-failures/`;
gate output no longer embeds megabytes of escaped plaintext and syscalls.

### Accepted AES-256 scale component

The corrected exact selection
`aes256_sha384_real_tcp_pressure_preserves_default_one_megabyte_streams_in_both_roles`
passed in **73.39 s**, compiling one strict x86_64 Linux ELF and running two
native processes. Both roles completed the full independent 1 MiB duplex
byte oracle, actual-progress accounting, clean close and owner ledger under
the untouched default 64 Gi work allowance and one original 35-second
operation deadline per case. The trace observed **zero positive short
sends in either role**, with 63 EAGAIN events in role 0 and eight in role 1.
This receipt makes no positive-short-send or throughput claim.

The focused Rust rebuild took 1.27 s. Receipts are
`target/stdlib-work/tls-sha384-tcp-pressure-deadline-build.log` and
`target/stdlib-work/tls-sha384-tcp-pressure-deadline-fixed.log`. The frozen
versions were adapter `cfeed85a`, engine `635898ed`, Rust driver `d03638a3`,
fixture `c3b6daba` and helper `7dcdec45`; production and test assertions
were unchanged by this admission. The root used the same 45-second GPU compilation timeout,
`RUST_MIN_STACK=16777216`, a 100-second outer timeout, a 35-second lock wait
and a 90-second inner timeout, selecting this test with `--exact`,
`--nocapture` and `--test-threads=1`.

### Accepted complete current migration

The other eight selections passed in two disjoint filter groups, each
reusing one strict protocol ELF for all its native processes. Together with
the scale selection, the accepted migration comprises **three strict ELFs,
122 native processes and three driver invocations** on the frozen sources
above. Receipts are under `target/stdlib-work/`:

| Driver selection | Native cases | Elapsed | Receipt |
| --- | ---: | ---: | --- |
| AES-256 1 MiB pressure | 2 | 73.39 s | `tls-sha384-tcp-pressure-deadline-fixed.log` |
| AES-256 interop 14, retained X25519 interop 18, P-256 interop 14 | 46 | 40.09 s | `tls-sha384-tcp-interop-first.log` |
| AES-256 limits 15, resume 6, P-256 entropy 14, retained pressure 2, faults 37 | 74 | 42.65 s | `tls-sha384-tcp-boundaries-first.log` |

The latter two invocations used disjoint `--skip` filters with the same
100-second outer timeout, 35-second lock wait, 90-second inner timeout,
45-second GPU compilation timeout and stack setting stated above. TLS
execution was native x86_64 Linux. All full-byte, actual-prefix, cleanup and
owner-ledger assertions passed. The retained SHA-256 cases kept their
12-second operation deadlines and explicit preceding suite/work policies.
No case was repeated apart from the classified AES-256 pressure deadline
correction above.

The retained SHA-256 pressure cases observed one real positive short send
and 65 EAGAIN events in role 0; role 1 observed zero positive short sends
and 263 EAGAIN events. This is separate from the AES-256 scale receipt's
zero positive short sends in both roles. Elapsed gate times include
compilation and orchestration and make no throughput claim. Historical
receipts below apply only to their recorded snapshots.

## Admission of the preceding group checkpoint

The driver retains the preceding 63 cases with an explicit X25519-only
policy and adds two focused selections totaling 28 cases:

- `p256_openssl_peers_cover_single_dual_requested_groups_and_entropy_retry`:
  14 real-peer cases cover P-256 alone, dual policies, both record suites,
  requested-group HRR in both role directions, and an initially rejected
  scalar followed only by fresh OS fills of the P slot. The fixture checks
  the actual negotiated group before accepting application output.
- `p256_entropy_rejection_cap_refill_failure_and_shared_budget_preserve_socket`:
  14 cases cover eight rejected candidates, exact P-slot refill requests,
  an invalid refill count, shared-budget exhaustion immediately after a
  refill attempt, and non-scalar constructor errors without retry. The
  fixture retains and closes the original socket on every attachment failure.

These entropy faults deliberately suppress selected `getrandom` calls;
the entropy adapter's zero-initialized staging then supplies a known invalid
scalar. Injected positive counts are test controls, not evidence of fresh
OS randomness. Successful recovery cases require real later OS P-slot bytes
and independent OpenSSL agreement. The cap cases accept no engine and send
no handshake bytes. Budget-stop credits derive from the observed charged
host prefix plus the documented acquisition reserve; no allowance resets.
All six selections passed, totaling **91 native cases and six independently
compiled strict ELFs**. Each ELF was reused within its exact gate. GPU
compilation produced x86_64 Linux native executables; TLS processing runs
natively. The frozen sources were adapter `b5125b31`, engine `eaf51c4c`,
negotiation `3f089664`, Rust driver `77a309c1`, fixture `610970bc` and helper
`a384f802`. The joint Rust build of four targets took 1.75 s
(`group-build-frozen.log`); that is separate from compilation/execution inside
the focused gates. Receipts are under
`target/stdlib-work/tls-connection-admission/`:

| Gate | Native cases | Elapsed | Receipt |
| --- | ---: | ---: | --- |
| P-256 interoperability/recovery | 14 | 28.40 s | `group-tcp-interop-first.log` |
| P-256 entropy rejection/limits | 14 | 25.79 s | `group-tcp-entropy-first.log` |
| Retained X25519 interoperability | 18 | 31.69 s | `group-tcp-x-interop-first.log` |
| Constructor, fault and cleanup | 37 | 30.02 s | `group-tcp-faults-first.log` |
| 1 MiB pressure streams | 2 | 29.28 s | `group-tcp-pressure-first.log` |
| Established deadline/budget resume | 6 | 30.74 s | `group-tcp-resume-first.log` |

All binary-output, progress, resource-ledger and closure assertions passed.
The current pressure gate again observed one **real kernel positive short
send** in the native client, with 67 EAGAIN events; the native server
observed zero positive short sends and 263 EAGAIN events. Successful
attachments retain ten pre-handshake allocation owners; failed acquisition
retains and releases only the actual acquired prefix. The original caller
socket remains live on failed attachment. The root ran all current gates;
there were no author-side executions for the group migration.

## Verification of the preceding X25519 checkpoint

All four focused gates passed on **x86_64 Linux**, totaling **63 native
cases**. Each gate was invoked separately: four strict ELFs were generated
by the GPU compiler, each reused for that gate's native cases. TLS processing
executes natively, not as a GPU kernel. All accepted gates used adapter
`b916a2ce`, engine `b26122db`, Rust driver `cae568bf` and helper `4ab7feeb`.
Fixture snapshots differ as recorded below; acceptance is not a claim that
all groups were rerun after every fixture-only correction.
The independent peer was OpenSSL 3.0.13; syscall observation used strace 6.8.

Receipts are under `target/stdlib-work/tls-connection-admission/`:

| Gate | Native cases | Elapsed | Fixture | Receipt |
| --- | ---: | ---: | --- | --- |
| Constructor, fault and cleanup | 37 | 26.82 s | `b3c80ed9` | `tcp-faults-first.log` |
| OpenSSL interoperability | 18 | 26.17 s | `ff58319f` | `tcp-interop-scheduled.log` |
| 1 MiB pressure streams | 2 | 27.03 s | `ff58319f` | `tcp-pressure-first.log` |
| Established deadline/budget resume | 6 | 27.02 s | `7138fd26` | `tcp-resume-preconditions.log` |

The 18-case interoperability group passed both roles and suites, exact binary
output, confirmed syscall byte counts, clean closure and the ten-allocation
ledger. KeyUpdate cases checked both traffic generations; exporter cases
matched the independent peer. Every case observed EAGAIN, with 2–19 such
events per case. No positive short send was observed in this group.

The separate two-case pressure gate passed in **27.03 s**
(`tcp-pressure-first.log` in the same directory), using the same production,
fixture, driver and helper versions. Both role directions transferred exact
1 MiB streams in each direction and passed the resource ledger and clean
closure checks. The native client observed **one real positive short send**
and 69 EAGAIN events; the native server observed zero positive short sends
and 263 EAGAIN events. This supplies actual kernel partial-send evidence
without injected successful counts.

The corrected six-case resume group passed both suites' expired-read,
limited-send and limited-receive probes. Actual held authenticated plaintext
and caller sentinels survived expiry; real positive sends advanced the exact
wire cursor before CallLimit; real positive receives remained in the raw slot
without advancing the engine's received-record count. Renewed budgets then
produced exact peer bytes, clean closure and matching resource ledgers. The
six EAGAIN counts were `(12, 3, 4, 11, 2, 3)`; this group observed no positive
short send.

### Admission history

The first 18-case interoperability gate stopped on its second case after
21.97 s: the native client completed the one-byte ChaCha20 exchange with
matching report, native output and resource ledger, but the OpenSSL server's
captured application output was empty. The original helper closed server
stdin immediately after supplying its outgoing bytes. The helper now keeps
stdin open until the native process finishes, using its existing bounded
wait, so stdin EOF cannot prematurely end the independent peer's receive
loop. Production code and test assertions are unchanged. The failed attempt
is recorded in `target/stdlib-work/tls-connection-admission/tcp-interop-first.log`;
the exact failing case then passed with the preserved ELF and corrected
helper in 0.186 s. OpenSSL returned status zero, native output was `c1`, peer
output was `0b`, and the native report confirmed one accepted/received byte,
ten release attempts and eleven cleanup calls. That narrow diagnostic is
recorded in `tcp-single-stdin-fixed.bin` and `.err` in the same directory.

The corrected full group next reached its eleventh case before failing after
37.45 s: the native server's one-byte ChaCha20 exchange had matching native
output/report, but OpenSSL client output was empty. Native and peer syscall
traces showed the fixture retained a newly read echo, then called a blocking
transport step before its next loop turn could queue that echo. The peer
waited for the echo until stdin EOF began its shutdown; the late echo was
then discarded by the peer's shutdown drain. The fixture now queues held
echo before any potentially blocking step. Assertions, peer bytes and
timeouts remain unchanged. This classified attempt is recorded in
`tcp-interop-stdin-fixed.log`; the full gate passed after the fixture
scheduling correction as recorded above.

The constructor/fault/cleanup gate passed before the scheduling correction
at its separately recorded fixture snapshot. The root ran all admission
gates; the fixture author ran only two bounded preserved-ELF diagnostic
reproductions of the second interoperability failure.

The first six-case resume gate stopped on its second case after **24.51 s**
(`tcp-resume-first.log`), using fixture `ff58319f`. The expired-read case
passed, but the limited-send case still had post-handshake input retained.
Its four-credit fixture allowance omitted the post-feed clock check and
therefore stopped before the intended send, triggering the fixture's
positive-progress assertion. The corrected fixture adds one credit exactly
when retained input needs a feed, accounts that actual consumed prefix, and
keeps the positive-send and exact remaining-wire assertions. Its receive
probe now starts only with empty raw, plaintext and output slots and no
pending EOF/error, before queuing application bytes; successful completion
must have exercised that probe. Production code, peer data and timeouts are
unchanged. The corrected resume gate passed at fixture `7138fd26` as recorded
above. These three failed attempts exposed test-helper or fixture
precondition errors; none required an adapter production change.

[`extended_tls_tcp_execution.rs`](../tests/extended_tls_tcp_execution.rs)
compiles one strict ELF fixture per driver invocation and reuses it within
that process. Its four accepted groups cover:

- 18 real OpenSSL peer exchanges in both role directions, both SHA-256 suites
  (ChaCha20-Poly1305 and AES-128-GCM), binary/empty/fragmented application
  data, KeyUpdate and independent exporter comparisons.
  The Lanius client verifies its explicit CA and DNS reference; the OpenSSL
  client uses explicit CA, `-verify_return_error` and `-verify_hostname`.
  The server profile authenticates the server and leaves the client anonymous;
  these are not mutual-TLS tests. Both peers must close cleanly.
- Two separate 1 MiB pressure streams exercise both roles with small real
  socket buffers. This group is isolated to preserve bounded gate duration.
- 37 constructor/owner/fault cases: every allocation position, actual TCP
  metadata/blocking rejection, entropy EINTR/EAGAIN/zero/invalid counts,
  interrupted/WouldBlock transport calls, zero/oversize send counts, I/O and
  clock failures/reversal, wrong trust/name/time, raw/partial EOF, expiry, and
  separately observable primary plus close failures. Public exporter calls
  exhaust engine work and must leave failed output unchanged while retiring
  the terminal owner with its original cause.
- Six Established resume cases across both suites. An expired read preserves
  held authenticated plaintext and destination sentinels. A finite allowance
  accounts for any retained-input feed, then stops after a real positive
  send; a four-call receive probe starts with empty slots and stops before
  feeding its newly received bytes. Both retain actual progress across a
  renewed budget and must produce exact peer bytes.

The test fixture inherits one real connected TCP descriptor and uses
allocation-free argument decoding. Exact binary outputs, confirmed syscall
counts, ten pre-handshake allocations, matching address/size releases, no
later growth and one fd0 close attempt are checked independently. Injected
positive invalid counts test rejection only, never fabricated data progress.
Small real socket buffers exercise pressure; actual kernel positive short
sends and EAGAIN counts are reported. Positive short sends are not a flaky
mandatory assertion. The pressure gate's real positive short send and the
portable engine's three-byte acknowledgement models provide independent
evidence for partial-record progress.

Python/OpenSSL setup and fragmentation are loopback-only test plumbing, not
production TLS. Each harness case and host peer has a finite timeout. The
evidence above covers all six current adapter gates and the earlier
checkpoint. The separate [application guide](extended-tls-exchange.md)
tracks application admission and its earlier parser/source corrections. No security
certification claim follows from these focused gates. General PKIX, mandatory
TLS algorithm coverage and the remaining [whole connection
contract](tls-connection-contract.md) remain open.
