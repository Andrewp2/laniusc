# Direct HTTPS server Exchange tests

These fixtures execute the actual `ext::https_server::Exchange` over a real
connected nonblocking TCP socket. The Python client verifies the server's
native certificate and negotiated TLS version. The consumer destroys its
caller-owned `ServerContext` before stepping the retained session. TLS records,
verification and cryptography remain in native OpenSSL; the shared duplex
observer is reused without modification.

## Initial executable gates

The `steps` group has six cases:

- TLS 1.2 public server with a binary fixed-length request and echoed body.
- TLS 1.3 public server with a binary chunked request and trailers.
- TLS 1.2 and TLS 1.3 required-client servers, each with a verified client
  certificate, a real `100 Continue` exchange and the binary body.
- The same two required-client policies without a client certificate. No HTTP
  event, request byte or response byte may be published before verification;
  rejection retains the native handshake diagnostic.

The `closure` group has two early-final cases, one per TLS version. The client
sends a valid request head and withholds its 257-byte upload. The server stages
a 413 response with a 64 KiB body. Small checked socket buffers and a client
that withholds response reads until the observed native write `WANT_WRITE`
establish real backpressure. The observer checks stable write bytes, pointer,
length and count cell across retries. The client independently parses the
complete response, authenticates the server's alert, sends the remaining
upload and completes its own alert. The server must retain confirmed response
progress, discard the 257 bytes and reach authenticated peer EOF before its
terminal event. This finite native-peer case does not establish all peers'
behavior after receiving an early alert.

The consumer mutates and destroys handler-local response headers/body after
`respond` returns. Request/head borrowed views are hashed throughout progress,
terminal completion and abort, remaining valid until `Exchange.destroy`.
Repeated terminal steps publish no second event, invoke no further SSL I/O and
cannot close a descriptor twice.

## Step and ownership evidence

Markers surround `step`, `before_wait`, external polling and application
decisions. Every step checks a native observer I/O-call delta of zero or one,
equal to its public `tls_stats().calls` delta. Decision and wait preparation
calls must perform zero native SSL I/O. The trace permits `poll` only inside
the explicit external poll frame. Successful cases also exercise stable
terminal replay.

`ledger.py` classifies source mappings using exact generated allocation and
release instruction sites. It keeps the one actually inherited TCP descriptor
as a separate initial owner; native file opens and source-created sockets have
their own observed owners. Loader/libc/OpenSSL heap mappings are outside the
source mapping ledger. Before exit, source owners balance, native context and
SSL counters are zero, and `/proc` shows only descriptors 0, 1 and 2 while the
consumer is still waiting for an acknowledgement. Nine CPU mutation controls
check hidden polling, inherited-fd leaks/double-close, unverified source sites,
mapping sizes/releases and marker balance.

## Status

The `steps` group passed six native cases on Linux x86_64 with OpenSSL 3 on
2026-10-26. The root validated the linked x86_64 ELF and host dependencies
before execution. The receipt is
`target/stdlib-work/https-server-exchange-verified-steps-explicit-option-retry.log`
(exit 0; 12.87 s). Its finite scope is the two public fixed/chunked transfers,
the two verified required-client Expect exchanges, and the two missing-client
handshake rejections listed above. These cases exercise the actual server
Exchange's one-SSL-call step bound, external polling, HTTP verification gate,
terminal cleanup and source/native/descriptor ledgers.

The separate early-final `closure` group also passed two native cases, one each
under TLS 1.2 and TLS 1.3, by reusing that accepted consumer ELF. Receipt:
`target/stdlib-work/https-server-exchange-early-closure-native-first.log`
(exit 0; `https-server-exchange-closure cases=2`). These cases establish the
specified real response backpressure, stable pending write retries, complete
413 response, local notification, 257-byte upload discard and authenticated
peer EOF for these native peers. They do not establish behavior for every peer
implementation.

The two additive cleanup groups also passed, for **16 accepted direct HTTPS
cases** across all four current groups. Their receipts are:

| Receipt under `target/stdlib-work/` | Result | Scope |
| --- | --- | --- |
| `https-server-exchange-fatal-preparation-cleanup-first.log` | exit 0; 12.11 s | Four real Reply.stage work-failure/abort cases under TLS 1.2/1.3, including two reached close EIO injections |
| `https-server-exchange-normal-close-primary-first.log` | exit 0; 11.40 s | Four normal-close baseline/failure cases under TLS 1.2/1.3, including two reached close EIO injections |

These cleanup cases establish the primary/secondary distinction and sticky
fatal replay described below, with the native-created listener harness and
pre-exit native/source/descriptor ownership checks. They do not establish
constructor allocation-failure coverage or direct TLS/I/O quota boundaries.
Python syntax, literal byte lengths, Rust
formatting, diff checks and the nine CPU ledger controls pass. Each shell
command stays under two minutes. These receipts establish native host
execution, not GPU kernel execution of TLS services.

The first `steps` attempt stopped at fixture compilation, before native cases:
`target/stdlib-work/https-server-exchange-verified-steps-first.log` reports
`LNC0027` for `Vec.try_set` after 4.59 s. The actual public operation is
`Vec.set`; both owned fixture call sites were corrected after checking
`stdlib/alloc/vec.lani`. This is a fixture API mistake, not native behavior or
an accepted runtime result. The other used Vec operations (`try_resize`,
`as_view`, `len`, `destroy`) match the current public signatures.

The next attempt also stopped before native execution: receipt
`https-server-exchange-verified-steps-vec-api-retry.log` reports `LNC0006`
(`AssignMismatch`, detail `2097152`) at an unannotated match-to-Option binding
after 4.28 s. The receiving local now explicitly names
`Option<ext::openssl_tls::Error>`, and three sibling HTTP Failure Option
bindings received their concrete annotations. The original shape and a small
[confirmed reduction/control pair](compiler_admission/README.md) are retained
in `compiler_admission/`: the untyped reduction rejects with `LNC0006` at 8:97,
while the typed control compiles and exits 0 after both assertions. This
expression-context dependency is separate from native TLS behavior and has no
compiler repair or broader inference claim.

The first two test filters in
`tests/extended_https_server_exchange_execution.rs` are:

```text
verified_server_steps_gate_public_required_client_http_and_expect_binary_bodies
early_final_tls_responses_finish_stable_backpressure_then_notify_and_discard_uploads
```

Fatal preparation/cleanup has its own accepted gates above. Quota and allocation
campaigns are separate focused gates; the initial two groups do not establish
their acceptance.

## Additive constructor and quota gates (native acceptance pending)

`constructor.lani` opens its listener and accepted socket inside the native
child. A Python peer connects after the tracer starts and sends no TLS or HTTP
bytes. Six cases isolate the composition before any HTTP event can occur:

- A zero TLS-call allowance returns driver `InvalidOptions` at `Configure`,
  without a TLS or HTTP I/O attempt.
- An already-destroyed caller context returns TLS `Closed` / `Session` at
  driver `Attach`, after the one HTTP I/O charge for checking socket flags.
- A one-call TLS allowance permits one real handshake `WANT_READ`, then fails
  with `TlsLimit` before another native call or wait, even without readiness.
- An HTTP I/O allowance of one is consumed by construction. The first step
  fails with HTTP `IoLimit` / `Head` at driver `Handshake`, before SSL I/O.
- An HTTP I/O allowance of two permits that flag check and one real handshake
  `WANT_READ`. The external `before_wait` reservation fails with `IoLimit`
  before any poll or another native call.
- A successful constructor performs no SSL I/O; explicit abort closes its
  owners, remains `Aborted`, and replays no event through step or before_wait.

Every failure consumes the socket exactly once. Returned metadata checks zero
received/request/response bytes, no rejection, no premature HTTP event where
an Exchange exists, exact call totals, and truthful final cleanup statistics.
Fatal owners replay the cached error through both step and before_wait without
additional native calls. A positive-capacity peer read must observe pre-exit
TCP EOF with no server bytes. Native context/session counters and child `/proc`
descriptor checks run before the final acknowledgement.

The source uses a 256-byte raw request cap and an 8,192-unit work allowance;
the constructor's 512-unit cursor precharge is explicitly checked. A 97-byte
TLS I/O cap gives the reader and writer distinguishable bounded source
allocations. `B/b` markers enclose only `begin_connected`, after socket
acquisition. `constructor_ledger.py` verifies emitted source allocation/release
instruction sites separately from loader/libc/OpenSSL heap mappings, requires
one close of the accepted descriptor and zero live source/descriptor owners
at the final report write before acknowledgement, and rejects hidden polling.
It currently passes 17 CPU controls. No native OpenSSL allocation is an
injection target.

The bounded first test filter is:

```text
constructor_and_tls_io_quotas_fail_before_http_and_replay_without_native_io
```

The first quota gate stopped at fixture compilation before any native case:
`target/stdlib-work/https-server-exchange-constructor-quotas-first.log` reports
`LNC0016` at `constructor.lani:35:10` after 4.01 s. Bare `else if` is not
accepted by the current source grammar; that single occurrence was changed to
the equivalent nested `else { if (...) { ... } }`, preserving all assertions.
This is a fixture syntax correction, not an accepted runtime result. Retried
compiler admission, the six native quota cases and the separate reached-source
constructor allocation sweep remain pending.

`constructor_allocations.py` prepares that separate finite campaign: one
successful constructor/abort control followed by a reached failure of every
verified source allocation actually observed inside the constructor. The
baseline must contain at least one such request; its private allocation layout
and count are not fixed by this test. Each injection binds to that baseline's
global mmap ordinal, exact generated source instruction, requested size and
constructor frame; the full mmap request prefix must also match after
normalizing native DSO addresses.
The failed run must attempt only the corresponding source prefix and return
TLS `AllocationFailed` / `Session` at driver `Attach`, with no native SSL I/O,
one successful socket cleanup and no live source/native/descriptor owners.
The independent prefix controls reject source-site, size and protection drift;
21 CPU ledger/prefix controls pass. This finite source campaign neither injects
nor establishes recovery from native OpenSSL heap failures.

Its separate Rust test definition is included from
`constructor_allocation_driver.rs`. The intended exact filter is:

```text
constructor_reached_source_allocations_unwind_protocol_socket_and_native_session
```

It can also reuse the first accepted constructor ELF directly through
`python3 -B constructor_allocations.py <ELF> <certificate-directory>`. Both
native acceptance and compiler admission of the new constructor source are
still pending; no added case changes the 16 accepted-case receipt above.

## Additive cleanup regressions

`preparation_abort.lani` uses the actual `server_poll::Reply.stage` sink to
exhaust the Protocol work allowance after a verified request head, while the
Exchange still owns its native session and socket. Successful actual cleanup
must return `abort() -> Ok(true)`, retain the original fatal as `Failed`, and
replay that cached error through both `step` and `before_wait`. Its final close
statistics must show one attempt and no cleanup error. No secondary failure is
invented from the Protocol's already-latched primary.

The preparation fixture uses a 256-byte raw request/head cap, a 128-byte line
cap, four request headers, and no request body/trailers. The actual short
`POST /close` request has only Host and Content-Length headers. Its cursor
constructor precharge is `2 * request_bytes = 512`, within the 8,192-unit
Protocol work allowance. The fixture asserts that the verified Head event is
reached with at least that precharge and some allowance still available.
Response limits separately permit a 64 KiB body, a 256-byte head, 128-byte
lines, four headers and 128 KiB raw response. Staging that body alone requires
at least 262,144 work units under the canonical response-preparation charge,
so the intended `WorkLimit` occurs at `Prepare`. A work budget below the
default 2 MiB request cap's constructor precharge would not test this path;
the cleanup fixture therefore sets its raw cap explicitly.

A paired reached `close` EIO must return only the new `Cause::Io(Host(5))` at
driver `Close`, without a duplicate secondary field. The saved original HTTP
primary retains its original stages and receives truthful final close stats
plus the real secondary close error. Repeated abort and destruction cannot
perform more native I/O or close another descriptor.

`normal_close.lani` separately finishes a verified response and authenticated
TLS teardown. Its injected close EIO is the sole canonical primary:
`Cause::Http` containing HTTP `Close` / `Cause::Io(Host(5))`, with no duplicate
outer or inner secondary cleanup field. A successful baseline locates that
actual reached close instruction and ordinal before injection.

Each regression is paired under TLS 1.2 and TLS 1.3. The two authored groups
have four process cases each, including the necessary baseline runs. The
active campaign targets `WorkLimit`; the optional clock-failure branch in the
preparation fixture has no execution claim. `cleanup_ledger.py` verifies the
exact injected close ordinal, source site and operation frame. Because strace
skips that kernel close, the descriptor remains live in the ledger until the
fixture's explicit test repair succeeds. Seven CPU controls reject missing
repair, repeated close, wrong descriptor/errno and absent injection markers.

The additive cleanup fixtures create their own listener and accepted socket
inside the native child. A 16-byte little-endian `(1213421622, port)` startup
packet publishes the loopback port; the oracle opens its client only after
spawning the tracer, then sends `+` to permit the native accept. `C/c` brackets
listener creation, publication, accept, listener close and Exchange attachment.
No connected descriptor is passed through `pass_fds`, and the cleanup ledger
starts without inherited socket owners. It tracks both actual `socket` and
`accept4` acquisitions, including the caller's separate listener close.

This fixture-boundary correction preserves the pre-exit peer EOF assertion.
The root diagnostic in `target/stdlib-work/plain-abort-tracer-ownership.trace`
showed why the earlier inherited-fd setup could wait indefinitely: the native
child had only descriptors 0/1/2, but strace still held the connected socket;
peer EOF arrived only after the native child/tracer exited. This is a harness
ownership issue, not a production close failure. The eight accepted initial
HTTPS cases observe authenticated TLS alerts and remain unchanged.

The final 128-byte report and acknowledgement are unchanged. The native child
reports the actual accepted descriptor for trace binding, and each injected
close is targeted after the constructor's listener close. `A/a` brackets
explicit abort, `S/s` normal step closure, and `K/k` only the test's skipped
kernel-close repair. Native/FD cleanup and peer EOF are checked before the
oracle acknowledges process exit.

`cleanup_driver.rs` supplies these accepted cleanup tests through an explicit
include in the integration driver. Their exact filters are:

```text
fatal_reply_preparation_abort_distinguishes_success_and_new_close_failure
otherwise_successful_https_close_failure_has_one_canonical_primary
```
