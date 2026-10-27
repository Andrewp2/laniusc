# Concurrent service acceptance

This is test infrastructure for the actual `http_serve.lani` and
`https_serve.lani` programs. No new Lanius test consumer replaces either
program. Production HTTP, scheduling and TLS remain in the library programs;
Python supplies bounded peers, independent h11/`http.client` readers and
syscall observations. TLS records and certificate operations use real OpenSSL.

## Initial causal cases

| Mode | Dependency before releasing the first peer |
| --- | --- |
| `plain-refill` | The first accepted peer sends a partial HTTP head. A healthy second peer must complete, then a queued third must be accepted and complete, while the first descriptor remains live. Only then finish the first head. |
| `tls-refill` | The first TCP peer wraps with `do_handshake_on_connect=False` and sends no TLS bytes. A verified second and queued third TLS peer must complete before the first performs its verified handshake/request. |
| `plain-reader` | A peer sends a bounded 4 MiB echo, reads only its response head, then withholds body reads. Require actual server output followed by EAGAIN, then a healthy sibling's completion before resuming the held body. |
| `tls-reader` | The same held response-reader dependency uses verified TLS and stable native OpenSSL progress. |

The initial TLS cases pin TLS 1.3. Native closure policy covers both versions
in its own raw tests; this fixture does not inherit those cases as connected
TLS 1.2 program coverage. After exact response decoding, `SSLSocket.unwrap()`
sends and requires `close_notify`; raw TCP EOF and the product's successful
close syscall are required afterward. Missing notification is not tolerated.

`trace_events.py` binds each successful `accept4` to its client source port,
acceptance ordinal and fd generation. Reuse of a closed fd does not preserve
the old owner's authority. Both refill cases require completion order 1, 2, 0
and reports in acceptance order 0, 1, 2. A held first owner must still be live
after later peers finish. The third TCP connection is established in the
listener backlog while both initial accepted owners remain active; it must
not be accepted until the second retires. Plain peer 1 withholds write EOF,
and TLS peer 1 withholds its alert, to establish that queue state explicitly.
The reader cases require an actual write EAGAIN
after at least 256 KiB of positive output in that owner's generation. They
do not substitute elapsed ratios or `sleep` for proof of backpressure.
The fixture leaves the ordinary TCP receive-buffer policy intact. It records
the initial and resumed capacities for diagnosis. Withholding body reads is
the imposed backpressure condition; a large payload alone does not establish
backpressure. The real EAGAIN witness must still occur before the healthy
sibling is admitted. After that sibling completes and the held descriptor is
still proven live, reading resumes and the complete 4 MiB response must pass
both independent readers and explicit EOF checks.

Active accepted connections peak at two; listener plus connection sockets
peak at three. Native certificate/loader file descriptors are tracked
separately and do not consume the socket cap. Socket and file close syscalls
must explicitly balance before successful process exit. The initial suite
does not yet claim source mapping/native SSL allocation ledgers or injected
fault/allocation coverage.

## Ownership and process bounds

Each invocation creates its own private temporary directory. The oracle
imports only guarded certificate/context helper modules, never CLI oracles
that execute their matrix at import. Existing helper and oracle files remain
unchanged. h11 checks HTTP framing, headers and exact binary body; a separate
`http.client.HTTPResponse` parses the complete response again.

Every service runs under `strace --kill-on-exit`; failure cleanup kills the
tracer and therefore its tracee. A GNU `timeout` bounds the Python process
group to 38 seconds with a two-second kill grace; Rust's outer bound is 45
seconds. Individual socket, startup, trace-wait and process-collection calls
have shorter deadlines. Each response advancement also has an absolute
eight-second deadline, so repeated small reads cannot reset its budget. The
oracle has a 30-second internal deadline, a 25-second stack snapshot, and
immediate failure stack/phase capture. Success removes its directory unless
`LANIUS_KEEP_TEMP_ARTIFACTS` is set. Failure retains the trace, output and
diagnostic in the printed `lanius-server-concurrency-*` directory.

`oracle-events.log` flushes connect/admission, request-send, response-head,
256 KiB receive progress, sibling retirement, reader-resume and EOF phases.
It includes client source ports and the accepted fd generation. Both the
initial and current `SO_RCVBUF` values are recorded before the
held response resumes; a successful reader summary includes both capacities.
The fixture does not set this socket option. `oracle-stacks.log`, `failure.txt` and collected native output
provide evidence when an internal deadline fires. These diagnostics do not
replace the actual EAGAIN, sibling completion, cap or exact-body assertions.

The Rust driver validates actual x86_64 executable output, generated jumps,
and the HTTPS native ELF profile/OpenSSL dependencies. Compilation remains
in the root's serialized GPU/native queue. Each command must remain below
two minutes; select a single group when admission or tracing approaches that
bound.

## Status

The final saved application schema is reflected in these fixtures:

```text
received sent response interim drain tail io cleanup cleanup-errors work scan
id rejected shutdown eof closed code [tls] failed
```

Each token is `name=value`; `received` starts the line and `failed` ends it.
TLS reports require `tls`, while plain reports omit it. Normal requests require
`code=failed=rejected=cleanup-errors=0`, `shutdown=eof=closed=1`, one successful
cleanup attempt, exact confirmed request/final-response byte counts, and
positive I/O/work/TLS attempt counts. IDs and report rows follow kernel
acceptance order, even when completion reverses it. No report may appear
while the held first owner remains active after its siblings complete.

Source/static and CPU mutation controls are the only checks performed during
fixture development by its owner. Root has accepted the first actual plain
queued-refill invocation: one case, three accepted connections, active peak
two and listener-plus-connections peak three. Its receipt is
`target/stdlib-work/server-concurrency-plain-refill-first.log`, with
`traced-seconds=0.060573`. This is a traced process observation, not a throughput
or compiler-speedup measurement. The executable came from the first plain
program compile, before the planned empty-EOF stage diagnostic correction;
this successful nonempty-request case does not establish that distinct path.
The ordinary-buffer plain held-reader retry also passes: one case, two
accepted connections, active peak two and socket peak three in
`target/stdlib-work/server-concurrency-plain-reader-normal-window-retry.log`.
It records `traced-seconds=5.149525`, with initial and resumed receive capacities
both 131,072. The complete 4 MiB binary body, actual write EAGAIN after at least
256 KiB of confirmed output, healthy-sibling completion while the held fd
remains live, independent response readers, explicit EOF and final report
assertions all execute in this case. Together these are two finite plain
application passes across separate invocations.

Both TLS 1.3 causal cases also pass against the actual program, for four causal
application cases in total across separate invocations:

| Receipt under `target/stdlib-work/` | Accepted | Active/socket peaks | Traced seconds |
| --- | --- | --- | --- |
| `server-concurrency-plain-refill-first.log` | 3 | 2 / 3 | 0.060573 |
| `server-concurrency-plain-reader-normal-window-retry.log` | 2 | 2 / 3 | 5.149525 |
| `server-concurrency-tls-refill-first.log` | 3 | 2 / 3 | 0.158297 |
| `server-concurrency-tls-reader-first.log` | 2 | 2 / 3 | 6.473137 |

The TLS reader confirms the complete 4 MiB binary echo, actual output EAGAIN,
healthy-sibling progress and authenticated closure. Its initial/resumed receive
capacities are both 131,072, as in the plain reader. These finite observations
do not establish all network schedules. Broader plain application fault/resource
and populated owned-error/scheduler-cap gates remain separate. The direct TLS
teardown cases have their own receipt in the HTTPS Exchange guide.

### First held-reader timeout investigation

The root's first plain held-reader attempt ended at its outer 45-second
bound with exit 124 and no PASS output in
`target/stdlib-work/server-concurrency-plain-reader-first.log`. Its preserved
`/tmp/lanius-server-concurrency-pbno1a13/syscalls.log` contains 122,681 completed
events. CPU-only inspection parsed the complete trace in approximately
0.28 seconds; parsing a memory-only 4 MiB response through both independent
HTTP readers took approximately 0.12 seconds. These observations do not
establish a network throughput result.

The product accepted two owners, confirmed 2,606,080 response bytes on the
held fd, then encountered actual send EAGAIN. The healthy sibling completed
and closed while that first owner remained live. All subsequent polls
requested POLLOUT for the held fd; none returned it writable. The product
closed the held fd at its approximately 12-second owner deadline, balanced
its socket closes and emitted two reports. The trace therefore shows neither
a wrong held-output interest nor an ignored writable wake. It does not
capture Python's receive-window call or receive progress, so the peer's
post-witness phase remains unclassified. The existing window-restoration
call preceded the held peer's full response read; its presence alone did
not prove execution or the values returned in this attempt.

The bounded diagnostic retry also failed, with a useful receive timeout
rather than an outer kill. Its receipt is
`target/stdlib-work/server-concurrency-plain-reader-bounded-diagnostic-retry.log`;
artifacts are in `/tmp/lanius-server-concurrency-wwrricen`. The flushed journal
proves the artificial buffer changed from original capacity 131,072 to 8,192,
then was restored to actual capacity 262,144 at 4.740148 seconds. The full-body
read started immediately; at 10.831300 seconds only 269,312 response wire bytes
had arrived. The product had confirmed 2,604,032 output bytes before EAGAIN.
Its later polls retained POLLOUT, with no writable result for the held fd.
The healthy owner succeeded; the held native owner reached its approximately
12-second timeout and reported `closed=1`, `cleanup-errors=0`, `failed=1`.
The oracle's absolute response budget ended with a receive TimeoutError at
12.740530 seconds. This is finite evidence of a throttled receiver and a
native owner timeout with correct poll registration, not a passing concurrency
case or evidence of a missed writable wake.

The current fixture removes that artificial buffer mutation. The 4 MiB body,
mandatory EAGAIN after substantial output, sibling ordering, fd caps, complete
HTTP/TCP or authenticated TLS closure, reports and absolute deadlines are
unchanged. Ordinary buffer capacities are recorded instead. This revision
passes the ordinary-buffer plain and TLS retries recorded above. Broader
resource/failure coverage remains pending.

## Separate scale observation

`scale.py` runs an existing compiled application; it never invokes the compiler.
Each mode requests 64 distinct connections, each echoing a checked 65,536-byte
binary body (4,194,304 body bytes total), with server concurrency four and eight
client workers. Before any HTTP/TLS bytes are sent, eight TCP peers connect;
the trace must show exactly four accepted, still-live owners and four queued
client source ports. The workers then release and refill all 64 jobs. This
establishes demand above the service cap without a timing ratio assertion.

The actual accepted-owner peak must be four; listener plus connections must
peak at five. Every source port maps to an acceptance ordinal and fd generation.
All 64 exact responses pass h11 and `http.client`; normal cleanup, exact byte
counts and acceptance-order report IDs must also pass. TLS pins verified
TLS 1.3/localhost and requires `unwrap()` plus actual TCP EOF for every peer.
Ordinary socket receive buffers remain unchanged.

`scale_ledger.py` reuses the existing `https_batch/resources.py` executable-site
verifier unchanged for the native-linked TLS output. The current plain output
is a sectionless ELF, which that verifier's section/symbol walk cannot admit.
Its explicit profile uses the same exact allocator byte pattern inside checked
executable LOAD ranges and disassembles that helper from its known entry to
verify both syscall boundaries. It admits only those runtime pairs, with no
named-source allowance; a rejected linked ELF never falls back to this path.
Each low `MAP_32BIT` source allocation must have a
verified allocation IP and an exact address/requested-size/verified-IP release.
The printed source allocation count and peak simultaneously live requested
source bytes cover these owners across the complete native process. Requested
sizes are not page-rounded or cumulative bytes. The separate bootstrap mapping,
native loader/libc/OpenSSL mappings, native heap, kernel socket memory and RSS
are outside this ledger. Native certificate file descriptors are tracked
separately from the socket cap; all observed file and socket owners must close.

The printed wall time is labelled `traced-seconds`. It starts just before native
process launch and ends after final report collection, including native startup,
client/network/handshake/closure work and tracing. Compilation, credential
generation, executable-site validation and final trace audit are excluded.
There is no throughput threshold, compiler comparison or deployment-capacity
claim. This fixture adds no allocation-failure campaign.

Each invocation has an 85-second internal deadline, a 75-second stack snapshot,
shorter socket/HTTP/client/process bounds, and flushed artifact diagnostics.
Run plain and TLS separately, each under two minutes:

```sh
timeout --kill-after=2s 95s python3 -B \
  tests/fixtures/extended/server_concurrency/scale.py plain \
  target/stdlib-work/http-serve-concurrent
timeout --kill-after=2s 95s python3 -B \
  tests/fixtures/extended/server_concurrency/scale.py tls \
  target/stdlib-work/https-serve-concurrent
```

Both native modes pass through separate root invocations:

| Receipt under `target/stdlib-work/` | Connections / body bytes | Active/socket peaks | Source allocations | Peak live requested source bytes | Traced seconds |
| --- | --- | --- | --- | --- | --- |
| `http-serve-concurrent-scale-first.log` | 64 / 4,194,304 | 4 / 5 | 1,224 | 1,165,325 | 3.346761 |
| `https-serve-concurrent-scale-first.log` | 64 / 4,194,304 | 4 / 5 | 1,419 | 1,352,377 | 4.226492 |

Each connects demand eight before release, completes every 65,536-byte binary
echo, validates all 64 acceptance-order reports and balances the verified source
owners and observed descriptors. The metrics retain the exclusions and timing
definition above. These finite traced observations do not complete the broader
plain application fault/resource campaign or replace the separate direct TLS
teardown and scheduler ownership/cap receipts.

Syntax, both actual executable-site profiles and 27 CPU ledger controls also
pass; those static/CPU checks execute no application. The controls exercise
overlap/reuse peaks, verified source sites, exact releases, exclusion of native
maps, fd reuse/generations, socket caps, incomplete traces, ownership errors
and rejection of malformed sectionless ELF/runtime profiles:

```sh
timeout --kill-after=2s 10s python3 -B \
  tests/fixtures/extended/server_concurrency/scale_controls.py
```

Run CPU-only oracle controls independently:

```sh
timeout --kill-after=2s 10s python3 \
  tests/fixtures/extended/server_concurrency/controls.py
```

These controls exercise trace identity/cap/error rejection and independent
HTTP reader rejection. They are not native service execution cases.
