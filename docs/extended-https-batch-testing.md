# Connected HTTPS exchange and batch tests

The focused driver is
[extended_https_batch_execution.rs](../tests/extended_https_batch_execution.rs).
Its [batch packet consumer](../tests/fixtures/extended/https_batch/protocol.lani)
uses `ext::https_batch::run_until`. The separate
[resumable consumer](../tests/fixtures/extended/https_batch/exchange.lani)
drives `ext::https_client::Exchange` directly. Both use the canonical
[HTTP Protocol](extended-http-client.md), verified OpenSSL transport and the
single generic batch scheduler. Test infrastructure supplies no production
HTTP parser, TLS implementation or cryptography.

This profile is Linux x86_64/glibc with OpenSSL 3 `libssl`/`libcrypto`.
It requires the compiler's native C link profile, Python with h11,
OpenSSL's CLI, a C compiler, `strace`, binutils and `/proc`. Numeric IPv4/IPv6
loopback peers and generated local certificates avoid external DNS and
remote services. These tests do not establish support for another platform.

## Focused groups

| Group | Planned finite executable scope | Acceptance |
| --- | --- | --- |
| Verified overlap | Five invocations: two connection/request barrier waves, held-first refill, concurrency one, IPv6 with IP verification; stack/Vec job backing, strided/packed byte backing and extracted response ownership | Passed: 5 cases |
| Framing and buffered plaintext | Four invocations: fixed, chunked, authenticated close-delimited and HEAD; binary bytes, trailers, tiny TLS read buffers and peer-held open connections | Passed: 4 cases |
| Typed peer policy | Eleven invocations: DNS/IP mismatch, expiry, absent intermediate, wrong purpose; verified TLS 1.2/1.3 client chains; absent, expired, wrong-purpose and untrusted client credentials | Passed: 11 cases |
| Duplex transport | Six invocations: bounded 4 MiB early-final upload under TLS 1.3 and TLS 1.2, abrupt EOF, cut encrypted record, already-received surplus plaintext, informational heads with chunked trailers | Passed: 6 cases |
| Limits and cancellation | Sixteen invocations: empty zero budgets, invalid/zero budgets, preparation before network, exact/below retained-result caps, per-job TLS/I/O exhaustion and a common deadline retaining one completed response | Passed: 16 cases |
| Resumption, faults and resources | Cross-direction WANT, native fatal errors, context-retain failure, every source allocation reached by one two-job baseline, recovery, and six direct resumable/abort invocations | Passed: 66 cases, including 42 source-allocation positions |

The observed two-job baseline reached 42 source-allocation positions; 16
faulted positions were reached after socket creation.
This is a finite schedule, not an enumeration of all TLS record partitions,
network interleavings, native heap allocation paths or HTTP features.

## Causal overlap and independent protocol readers

[peers.py](../tests/fixtures/extended/https_batch/peers.py) reuses the existing
OpenSSL-backed MemoryBIO peer. Each wave first requires every selected TCP
connection to be accepted before any server handshake output is generated.
It then requires every complete HTTP request before any HTTP response.
A driver that blocks on one connection's handshake or response before
starting the next cannot satisfy these dependencies. An external child
deadline bounds failure; elapsed-time ratios are not evidence of concurrency.

Responses within a wave are released in reverse order. A separate schedule
holds input 0 while later inputs complete through the other slot. Exact
response bytes must still occupy their original input slots. The kernel
socket ledger checks the maximum simultaneous socket count independently
of the batch's own peak counter. A peer's delayed observation of EOF is not
used as a kernel socket-close timestamp.

h11 independently checks emitted method, target, authority, Connection,
Content-Length and binary body. Python `http.client` reads each successful
returned final message. The oracle also compares the original expected wire
and body; two parsers agreeing on the wrong selected message is insufficient.
Informational prefix storage counts toward retained wire bytes even though
`Response.as_view()` exposes the final message only.

The request and response ownership checks overwrite caller request bytes,
release job Vecs and the caller Context, then read responses. A taken response
survives report destruction and is released separately. Repeated report
destruction and repeated take of the disarmed slot are checked. The direct
consumer destroys its original Context and overwrites identity/request
backing immediately after successful begin, before connection/handshake.

## TLS progress and termination

The direct consumer surrounds each `step` and `before_wait` with test markers.
The trace must contain no poll inside either interval. Source assertions
compare the native observer's counter with TLS statistics: a step performs
at most one native handshake/read/write/shutdown attempt; before_wait
performs none. Active TCP connect/SO_ERROR/peer checks also occupy at most
one leaf per step. Mandatory cleanup can close on a failing turn. A native
TLS call can itself perform multiple BIO syscalls and synchronous native
work; this is not a one-OS-syscall or preemption claim.

The shared [per-SSL observer](../tests/fixtures/extended/openssl_tls_duplex/observer.c)
is linked read-only. One-shot WANT and fatal results never manufacture a
successful byte count. Successful retries call real OpenSSL. The observer
checks stable write pointer, length, bytes and native count-cell identity
per SSL owner. Strict pending-read pointer tracking is disabled for the
adapter because its valid internal read quiescence is invisible to C.

The TLS 1.3 early-final peer withholds final response body bytes until it
observes authenticated client close_notify. It checks the exact uploaded
prefix and that the complete 4 MiB request was not sent. Its kernel receive
buffer is bounded. The TLS 1.2 peer sends the response body without demanding
pre-body close_notify, matching the driver's documented deferred policy.
These controls do not promise arbitrary TLS 1.2 half-close behavior.

Native OpenSSL generates the encrypted record used for truncation; the peer
sends a strict prefix of that record. Abrupt TCP EOF and authenticated TLS
EOF have different expected results. Already-received surplus HTTP plaintext
must preserve the nested HTTP rejection rather than publish a response.
Framed response completion does not require waiting for peer EOF to discover
bytes sent later. This follows the transport's trailing policy and is not a
claim to detect all future peer traffic.

Typed errors retain HTTPS stage, nested HTTP cause/stage/offset/cleanup,
TLS cause/phase/SSL error, the complete 64-bit OpenSSL code, signed 64-bit
verification result and system errno. Policy failures must leave siblings
usable. Native peers require their own completed verified handshake before
parsing HTTP. Client credentials use freshly generated clientAuth chains;
no private keys are stored in the repository.

## Native ownership and source allocation failures

Both ELFs undergo explicit x86_64 executable classification and the dedicated
[native-linked ELF checker](../tests/fixtures/native_c/validate_linked_elf.py),
including executable entry, dynamic profile, W+X rejection and generated
instruction/jump checks. The packet ELF must link OpenSSL 3 libraries.

[resources.py](../tests/fixtures/extended/https_batch/resources.py) reuses the
verified [allocation-site recognizer](../tests/fixtures/stdlib_foundation/resolve/allocation_sites.py).
It identifies exact emitted allocator/deallocator instruction sequences,
including runtime thunks outside sized source function symbols. Every
Lanius MAP_32BIT mapping must originate at a verified site and have one
successful release of the same address and requested length. Low unowned,
repeated, wrong-size or unverified releases fail the ledger.

Native loader, libc and OpenSSL mappings are outside this source-owner
ledger. OpenSSL may keep process-global caches; this suite does not claim
whole-process native heap balance. The per-SSL observer separately requires
zero external Context references, zero live Session owners and zero invalid
native frees after cleanup. Opened descriptors must balance, and a final
stdin acknowledgement pauses the tracee after report/response destruction.
Its live `/proc/<pid>/fd` must contain only inherited descriptors 0, 1 and 2.
Process-exit reclamation cannot hide an open socket.

The ENOMEM campaign selects every source allocation reached between explicit
BEGIN/END markers in one baseline. Caller argument/context/job/body setup
precedes BEGIN and is not part of this sweep; its successful source owners
must still balance in the complete trace. Each injected fault must bind the
exact global mmap ordinal, source IP, requested size and exclusive ENOMEM
marker. The preceding mmap request shapes must match the baseline. Source
IPs remain exact; native shared-library IPs are normalized because ASLR
changes their absolute addresses. A different allocation prefix fails the
harness instead of becoming evidence for an unreached leaf.

Two peers overlap before rich chunked responses are released in reverse
order. Actual post-request reset/alert/EOF may release a fault wave; timeout
does not stand in for termination. Recovery uses the same compiled code.
The sweep covers its observed source-owner schedule, not native OpenSSL
malloc failures or every concurrent receive schedule. Shared deadlines and
quotas still require cleanup when their allowance is exhausted.
Batch cancellation is driven by its common deadline and global allowances;
there is no separate external cancellation handle. The direct consumer also
checks the explicit Exchange abort operation.

The direct abort-close regression injects one exact EIO close result.
`strace` skips the underlying kernel close, so the test consumer explicitly
closes that borrowed test descriptor after the Exchange is disarmed. The
trace checks the marker, ordinal, IP and later matching release. This proves
Aborted terminal replay remains Inactive and last_failure preserves the
Close diagnostic; it does not pretend the failed close released the fd.
`strace --kill-on-exit`, finite children and bounded peer joins prevent an
external timeout from leaving a product child running.

## Acceptance

The initial two native groups passed on Linux x86_64/glibc with OpenSSL 3:
five verified overlap cases and four framing/buffered-plaintext cases. The
two-group invocation finished in 11.01 seconds with zero failures; its local
receipt is `target/stdlib-work/https-batch-initial-two-groups-first.log`.
The next three groups passed 11 typed-policy, six duplex-transport and 16
limits/cancellation cases in a separate 14.04-second invocation with zero
failures. Its local receipt is
`target/stdlib-work/https-batch-policy-transport-limits-first.log`.
The last group passed 66 cases in 37.52 seconds with zero failures:
42 reached source-allocation ENOMEM positions and 24 controls, including
six direct resumable/abort invocations. Sixteen allocation faults occurred
after socket creation. Its local receipt is
`target/stdlib-work/https-batch-resource-direct-typed-retry.log`.
All runs used the shared scheduler with the wait-retirement correction.

All six groups have native acceptance through these separate invocations,
covering 108 cases on the profile stated above.
The first resource-group attempt stopped before any Python campaign case:
the direct consumer's nested `Cause::Io(Error::Host(number))` pattern was
parsed but rejected with `AssignMismatch` / `LNC0006` at the bound value.
The unchanged original, diagnostic, confirmed 14-line rejection and executed
two-match control are preserved in
[compiler_admission](../tests/fixtures/extended/https_batch/compiler_admission/README.md).
The active consumer selects the typed I/O payload before matching Host(5),
retaining both exact error assertions, and passed the complete retry above.
The standalone nested-pattern reduction also rejects with LNC0006; the explicit
two-match control compiles and executes all four assertions with exit zero. The initial
10.24-second compile rejection is not evidence of a production TLS failure.
Python syntax and scoped whitespace checks have passed; they are test
infrastructure checks, not additional HTTPS execution receipts. The
`https_fetch` program, earlier raw TLS and HTTP batch tests have separate
scope; these library receipts do not accept the revised application.
