# Direct server Protocol and plain Exchange tests

This test-only probe targets the frozen shared server contract in
`docs/library-server-contract.md`. The five main groups have finite Linux
x86-64 runtime/resource receipts for 48 cases (4 steps, 11 decisions, 4 drain,
6 lifecycle and 23 faults), plus two additive abort cases: 50 distinct direct
cases. The stronger typed allocation/count diagnostics described below await
one recompiled probe and their focused reruns. Root serializes compilation and
native execution; fixture authors run CPU checks only.

The first steps gate stopped during compilation after 4.24 seconds with
`LNC0021 InvalidTraitImplementation`: the probe had public implementations of
its private helper trait. Both implementations now use private visibility.
This was a fixture declaration error; no native case ran and no compiler
change was needed. Receipt:
`target/stdlib-work/http-server-exchange-steps-first.log`. The corrected gate
then stopped during type checking after 5.51 seconds: the probe called
`Vec::try_set` instead of its actual `Vec::set` method. That fixture call is
corrected; that attempt ran no native cases. Receipt:
`target/stdlib-work/http-server-exchange-steps-visibility-retry.log`.
The 22 CPU trace guards and 11 peer-collector controls pass separately (33
controls total). The new collector controls distinguish reset from clean EOF.

The corrected steps group passed four native cases in 13.27 seconds; receipt
`target/stdlib-work/http-server-exchange-steps-vec-api-retry.log`. The next
invocation passed decisions (11 cases) and lifecycle (five cases), but its
drain group stopped before its first response: the fixture declared a
999,999-byte request under a 65,536-byte raw-request cap and incorrectly
expected a Head decision. The library correctly published a BodyLimit
rejection. Receipt:
`target/stdlib-work/http-server-exchange-decisions-drain-lifecycle-first.log`
(two groups passed, one failed, 12.78 seconds). Drain cases now explicitly
use the existing server profile's 2,097,152-byte raw cap; their small drain
caps and real backpressure/EOF requirements are unchanged.

That retry passed the three exact-drain cases before the duplex case reached
its real 12-second deadline. Receipt:
`target/stdlib-work/http-server-exchange-drain-coherent-request-cap-retry.log`.
The retained trace shows 323 successful 1024-byte sends (330,752 bytes), 20
send EAGAIN results, all 65,536 upload bytes drained and actual peer EOF.
447 of 463 caller polls timed out while the peer retained its deliberately
small receive buffer; later successful writes arrived in bursts about
1.16 seconds apart. This is evidence of continued transport progress under
the fixture's window constraint, not an accepted full-response result.
The fixture now enlarges only the peer receive buffer after actual send
EAGAIN and positive concurrent drain are proved, then reads nonblockingly.
It records both the witness and actual buffer sizes. The 1 MiB response,
64 KiB upload, deadline, exact response, EOF and resource assertions remain.
The current compiled main probe passed all four drain cases with this released
window fixture. Receipt:
`target/stdlib-work/http-server-exchange-drain-release-window-current.log`.
This includes the exact-cap cases and full 1 MiB response/64 KiB concurrent
upload after the real EAGAIN witness, with response/EOF/resource checks.

The current main probe compiled to
`target/stdlib-work/http-server-exchange-current` and its lifecycle group
passed six native cases, including the added pure control for empty EOF
entering FinishTransport at StageClose and withholding Empty until transport
cleanup is acknowledged. Receipt:
`target/stdlib-work/http-server-exchange-empty-eof-lifecycle-current.log`.
This supersedes the earlier five-case lifecycle receipt for the current probe.

The first current fault run stopped in the peer collector after the deliberate
receive EIO. The native driver returned the expected typed failure, closed its
descriptor, completed pre-exit cleanup checks and exited successfully; closing
with the queued request unread reset the peer. Receipt:
`target/stdlib-work/http-server-exchange-faults-current-first.log`. The collector
now records reset separately from EOF and accepts it only when a case explicitly
opts in after Failed/Aborted, a retired fd and one recorded cleanup attempt.
Only the receive-EIO case opts in. Successful/Complete response and clean EOF
requirements remain strict, as do the injected error, zero received-byte and
ownership assertions. The corrected fault campaign passed 23 native cases,
including 15 reached source allocation positions. Receipt:
`target/stdlib-work/http-server-exchange-faults-explicit-reset-retry.log`.
Its original Rejected path accepted the broad Http cause without checking
the nested subtype. The probe/oracle now require exact allocation diagnostic
details for both Rejected and returned Failure; the stricter typed receipt
remains pending. The two existing invalid-confirmed-count cases now likewise
distinguish WriteZero from InvalidCount. No native case was added. Root can
rerun the affected groups against the new compiled probe with `faults` and
`invalid-counts`; lifecycle still includes those same two count cases.

`probe.lani` owns either a real connected plain HTTP Exchange or a standalone
Protocol. A test-only trait provides one command loop for both owners. Real
mode accepts one Python loopback peer, configures bounded socket buffers before
transferring the accepted descriptor, and closes the caller-owned listener.
The driver itself never owns listener admission. Pure mode manually records
confirmed transport progress; its partial-Continue commits are explicit
Protocol controls, not fabricated successful native writes.

## Cases and independent evidence

The Rust driver has five direct-operation filters plus one additive abort gate:

| Filter | Intended executable scope |
| --- | --- |
| `server_steps_have_one_active_socket_leaf_and_external_waits` | Fixed/chunked binary requests, fragmented wire, explicit caller waits, stable views and actual empty EOF. |
| `server_protocol_decisions_expect_and_stable_views_survive_backing_growth` | Latched decisions, required/unsupported/preloaded Expect, partial 100 reservations, atomic response preflight, copied caller scratch, handled rejections and retained rejection after send error. |
| `server_early_rejection_duplex_backpressure_and_exact_eof_probe_execute` | Early final response, actual send EAGAIN while unread upload drains, half-close and exact/below/over drain limits with positive-capacity EOF probes. |
| `server_terminal_replay_abort_and_destruction_release_each_owner_once` | Empty EOF's Close stage and cleanup-gated terminal event, sticky failure/completion, abort and repeated destruction, application-pause deadline and invalid confirmed send counts. |
| `server_direct_errors_keep_progress_and_reached_allocation_failures_release_owners` | EINTR/fatal receive/send/shutdown/clock, exhausted active-I/O budget and each reached source allocation in one representative baseline. |
| `server_fatal_preparation_abort_distinguishes_primary_and_new_close_error` | Actual Reply.stage WorkLimit at Prepare followed by successful plain abort or a reached close EIO; preserve the primary and report new cleanup separately. |

The additive abort gate passed both native cases in 10.51 seconds, including
one reached close EIO and cleanup before exit acknowledgment. Receipt:
`target/stdlib-work/http-server-exchange-abort-native-listener-retry.log`.
Its first native attempt completed its assertion/report path but failed peer
EOF after 13.16 seconds;
receipt `target/stdlib-work/http-server-exchange-abort-close-primary-first.log`.
The native child closed its fd successfully and confirmed EBADF afterward.
A focused parent diagnostic then found the tracing process still held the
inherited TCP fd: the child had only fds 0/1/2, and peer EOF arrived only after
the tracer exited. Receipt:
`target/stdlib-work/plain-abort-tracer-ownership.trace`. This was a fixture
descriptor alias, with no production change. The fixture now creates the
listener/accepted socket inside the native child and passes no socket through
strace. Its separate `abort_cleanup.lani` and `abort_oracle.py` leave the five
direct-operation fixtures unchanged. A 16-byte startup packet publishes magic
and loopback port; the independent peer connects, sends its full request and
acknowledges readiness with `+` before native accept. The caller-owned listener
closes before the accepted nonblocking socket enters the Exchange.
Reply.stage attempts a 64 KiB response under an explicit
2,048-byte raw-request cap and 8,192 work units; the constructor/head fit,
while response preparation must fail WorkLimit before output or cleanup.
The native probe checks the original preparation snapshot, final full Stats,
retained head bytes, cached primary, repeated step/before-wait replay and
idempotent abort/destruction. A baseline identifies the actual abort close's
instruction address and global ordinal. The second run injects EIO at that
exact close: abort must report Io(EIO) at Close with no secondary error, while
the cached WorkLimit at Prepare gains EIO as secondary cleanup. The skipped
kernel close remains a live fd in the ledger until a separately marked raw
Linux test repair closes it successfully. Both source mappings and descriptors
must balance before exit is acknowledged. Nine CPU ledger controls pass;
they reject missing repair, false release, changed errno/target and hidden
replay cleanup or internal polling, and do not establish native acceptance.

The existing `http_server_oracle.py` request encoder, h11 response checker and
mapping/fd ledger are loaded unchanged from their function definitions. That
script has an unguarded CLI entry, so the support module loads only the named
definitions rather than execute another test process. Responses must match
independently expected status/body bytes, managed fields and Date syntax.

Every public operation has 128-byte before/after records. A strict syscall
parser rejects unknown or malformed trace events. Step epochs permit at most
one actual send, receive or shutdown attempt, each transfer at most 1024 bytes;
mandatory cleanup close is separate. Step, decision, metadata and before-wait
epochs permit no poll or hidden socket admission. Only explicit caller poll
epochs permit a physical poll. Metadata inspection must not allocate, close,
read the clock or transfer bytes. Counters and cached views are checked through
terminal states until destruction.

After destruction, the oracle checks source mappings and descriptors before
acknowledging process exit, including `/proc` fd inspection. The complete trace
must also balance after exit. Close-error injection is outside this physical
release ledger: it does not pretend a skipped kernel close released a real fd.

The allocation campaign counts actual mmap ordinals from a successful baseline,
selects only allocations reached inside library operations, and binds each
injected ENOMEM to the exact instruction address, size and prior allocation
prefix. Startup argument and probe poll-storage allocations are excluded from
that source campaign. This is finite single-fault coverage of one baseline.
CPU mutation controls check that trace guards reject invalid observations;
they do not add native process cases or establish API acceptance.

On failure, the printed `http-server-exchange-*` directory retains the command,
input packets, native stdout/stderr, response wire, records, peer actions and
complete trace. A case cannot pass by killing a live child during cleanup or
by replacing a required EOF/progress dependency with an elapsed-time ratio.

## Probe packet

Commands are eight little-endian i32 words followed by the declared payload.
Actions 0..15 advance one step with fresh advisory readiness bits; 16 checks
before-wait and performs a separately marked caller poll when permitted; 17/18
choose Read/ContinueThenRead; 19 stages a copied response; 21 aborts; 22 destroys;
23 inspects the current event/revision; 26 enters the final exit checkpoint.
Pure Protocol controls 28..36 feed, EOF, reserve, commit, cancel, record local
shutdown, discard, record close and finish transport. Action 27 is initial
plain listener admission before the Exchange exists.

Record words are magic, epoch tag, status, fd, interest, published event, Need,
cause, stage, errno, cleanup, received, retained, decoded, buffered discarded,
new drain, response bytes, response sent, Continue sent, active I/O, work, scan
work, cleanup calls/errors, flags, saved head/body hashes, rejection cause and
original received snapshot, diagnostic detail, payload length and operation result.
Optional request-body/send-reservation bytes follow their record. Rejection
and sticky Failure values are cross-checked in Lanius before publication.

Word 29 is the actual current Failure detail, or the retained rejection detail
when no error is returned: 1 means AllocationFailed, 2 means
Http(AllocationFailed), 3 means Io(WriteZero), 4 means Io(InvalidCount), and 0
means another cause. Only the initial real-mode startup packet uses that word
for the loopback port. Reached ENOMEM requires the exact (cause, detail) pair
(3,1) or (7,2), so another Http subtype cannot pass. Word 31 remains the
operation auxiliary value, including reservation size/readiness/event revision.
These are test packet diagnostics, with no production ABI change.
