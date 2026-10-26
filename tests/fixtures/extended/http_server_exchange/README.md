# Direct server Protocol and plain Exchange tests

This test-only probe targets the frozen shared server contract in
`docs/library-server-contract.md`. The production implementation and these
fixtures have no runtime acceptance receipt yet. Root serializes compilation
and native execution; fixture authors run CPU checks only.

The first steps gate stopped during compilation after 4.24 seconds with
`LNC0021 InvalidTraitImplementation`: the probe had public implementations of
its private helper trait. Both implementations now use private visibility.
This was a fixture declaration error; no native case ran and no compiler
change was needed. Receipt:
`target/stdlib-work/http-server-exchange-steps-first.log`. The corrected gate
then stopped during type checking after 5.51 seconds: the probe called
`Vec::try_set` instead of its actual `Vec::set` method. That fixture call is
corrected; the current steps gate remains pending, with no native acceptance
yet. Receipt: `target/stdlib-work/http-server-exchange-steps-visibility-retry.log`.
The 22 CPU trace-guard controls pass separately.

`probe.lani` owns either a real connected plain HTTP Exchange or a standalone
Protocol. A test-only trait provides one command loop for both owners. Real
mode accepts one Python loopback peer, configures bounded socket buffers before
transferring the accepted descriptor, and closes the caller-owned listener.
The driver itself never owns listener admission. Pure mode manually records
confirmed transport progress; its partial-Continue commits are explicit
Protocol controls, not fabricated successful native writes.

## Cases and independent evidence

The new Rust driver has five focused filters:

| Filter | Intended executable scope |
| --- | --- |
| `server_steps_have_one_active_socket_leaf_and_external_waits` | Fixed/chunked binary requests, fragmented wire, explicit caller waits, stable views and actual empty EOF. |
| `server_protocol_decisions_expect_and_stable_views_survive_backing_growth` | Latched decisions, required/unsupported/preloaded Expect, partial 100 reservations, atomic response preflight, copied caller scratch, handled rejections and retained rejection after send error. |
| `server_early_rejection_duplex_backpressure_and_exact_eof_probe_execute` | Early final response, actual send EAGAIN while unread upload drains, half-close and exact/below/over drain limits with positive-capacity EOF probes. |
| `server_terminal_replay_abort_and_destruction_release_each_owner_once` | Sticky failure/completion, abort and repeated destruction, application-pause deadline and invalid confirmed send counts. |
| `server_direct_errors_keep_progress_and_reached_allocation_failures_release_owners` | EINTR/fatal receive/send/shutdown/clock, exhausted active-I/O budget and each reached source allocation in one representative baseline. |

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
original received snapshot, startup port, payload length and operation result.
Optional request-body/send-reservation bytes follow their record. Rejection
and sticky Failure values are cross-checked in Lanius before publication.
