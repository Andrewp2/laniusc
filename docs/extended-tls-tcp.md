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

The ten owners never grow after attachment. The adapter then obtains exactly
64 fresh OS bytes, constructs the actual engine, and checks the original
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

## Prepared verification; native admission pending

The first 18-case interoperability gate stopped on its second case after
21.97 s: the native client completed the one-byte ChaCha20 exchange with
matching report, native output and resource ledger, but the OpenSSL server's
captured application output was empty. The original helper closed server
stdin immediately after supplying its outgoing bytes. The helper now keeps
stdin open until the native process finishes, using its existing bounded
wait, so stdin EOF cannot prematurely end the independent peer's receive
loop. Production code and test assertions are unchanged. The failed attempt
is recorded in `target/stdlib-work/tls-connection-admission/tcp-interop-first.log`;
corrected interoperability admission remains pending.

Replaying only that failed case against the preserved, unchanged ELF with the
corrected helper passed in 0.186 s: native output was `c1`, OpenSSL output was
`0b`, both process statuses were zero, and the native report recorded one byte
accepted and one received. The binary receipt and helper stderr are retained
as `tcp-single-stdin-fixed.bin` and `.err` in the same admission directory.
This narrow reproduction does not replace the complete 18-case gate.

[`extended_tls_tcp_execution.rs`](../tests/extended_tls_tcp_execution.rs)
prepares one strict ELF fixture, reused within the driver process, and four
focused groups totaling **63 native cases**:

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
  destination sentinels; a four-call operation allowance stops after a real
  positive send or receive, proving acknowledged wire progress and retained
  unfed input survive a renewed budget and produce exact peer bytes.

The test fixture inherits one real connected TCP descriptor and uses
allocation-free argument decoding. Exact binary outputs, confirmed syscall
counts, ten pre-handshake allocations, matching address/size releases, no
later growth and one fd0 close attempt are checked independently. Injected
positive invalid counts test rejection only, never fabricated data progress.
Small real socket buffers exercise pressure; actual kernel positive short
sends and EAGAIN counts are reported. Positive short sends are not a flaky
mandatory assertion. The portable engine's three-byte acknowledgement models
cover exact partial-record progress independently; a missing observed kernel
positive-short case must remain an explicit coverage limit.

Python/OpenSSL setup and fragmentation are loopback-only test plumbing, not
production TLS. Each harness case and host peer has a finite timeout. The
guide currently records prepared source and static syntax checks;
compilation, native execution, interoperability and allocation results
remain pending the parent's serialized admission. No runtime or security
certification claim follows from source review alone. General PKIX, mandatory
TLS algorithm coverage and the remaining [whole connection
contract](tls-connection-contract.md) remain open.
