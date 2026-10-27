# Persistent Server controls

These controls target the actual public `ext::server_poll::Server`, not a
local replacement scheduler. Root serializes compilation and native execution.

## Accepted preparation and lifecycle control

The initial preparation control passed all three native cases in 15.58 seconds,
including compilation, a validated x86_64 ELF and the independent pre-exit
resource checks. Receipt:
`target/stdlib-work/server-poll-fatal-preparation-visibility-retry.log`.
The root retained its executable at `/tmp/server_poll_native_201688_0`.

Its first invocation stopped before native execution in 4.35 seconds with
`LNC0021 InvalidTraitImplementation`: fixture implementations of imported
public traits had private visibility. All four imported trait implementations
and their required methods were corrected to public visibility. No assertion
or production source changed for that retry. First receipt:
`target/stdlib-work/server-poll-fatal-preparation-first.log`.

Three cases distinguish fatal response-stage WorkLimit followed by Ok(Abort),
ordinary Abort, and recoverable unsupported-status preflight followed by Abort.
The fatal case requires InvalidDecision(ResponseFailure) and the exact saved
preparation diagnostic, while the other two remain Aborted. The report's final
cleanup snapshot is checked separately from the original preparation snapshot.

The control calls real new/step/prepare_wait/resume/take/take_report/destroy,
checks Pending cannot be taken, inactive owner behavior, released work/byte
reservations, and repeated report destruction. Its scripted Driver feeds real
Protocol directly but owns actual accepted loopback TCP descriptors. Each peer
must observe actual EOF after scheduler retirement. This establishes no HTTP
wire or TLS behavior; those belong to the separate real application gates.

The native child pauses after destruction. The independent Python harness
checks `/proc` descriptors and balances all source mmap/munmap and socket/close
owners before acknowledging process exit, then checks the completed trace.
The unlinked ELF has no CRT/native-library allocation ledger mixed into source
allocations. Backing and descriptor cleanup cannot pass merely because the
kernel reclaims them at process exit. Failure evidence is preserved in the
printed temporary directory.

## Accepted publication, refill and reservation controls

The separate `publication.lani` entry and Rust helper are integrated under
`external_publications_retirement_refill_and_reservation_caps_execute`.
All four native cases passed in 14.62 seconds, including compilation, a
validated x86_64 ELF and the independent pre-exit resource checks. Receipt:
`target/stdlib-work/server-poll-publication-refill-reservations-first.log`.
The root retained its executable at
`/tmp/server_poll_publication_native_206274_0`. Together with the first group,
seven actual owner controls have passed separately:

- Nonempty readiness publication rejects bad epoch/length, supersedes earlier
  epochs, consumes a valid resume once, consumes cached advisory readiness once,
  and invalidates a publication after mutation.
- A scripted connection-local Timeout from before_wait releases the active
  owner and returns immediate work without a wait permit; the next step admits
  a queued socket before another blocking publication.
- A single byte reservation reduces configured concurrency two to one active
  owner, then permits queued admission after retirement.
- Consumed work remains charged after a connection retires: insufficient
  remaining cumulative work reports global WorkLimit and leaves the queued
  socket unaccepted, while retaining the original local Timeout outcome.

These are actual scheduler/Protocol and descriptor-owner controls. The driver
scripts local Timeout and advisory-readiness consumption; these cases do not
establish real deadline expiration or HTTP transfer. Six actually accepted
peers must observe EOF; source maps and native descriptors must balance before
the final acknowledgement. Both harnesses use the locally supported strace
`--kill-on-exit` option to terminate a tracee when its tracer is killed.

These finite receipts do not establish the real HTTP/HTTPS programs, TLS
progress, physical poll-once/service-loop behavior, genuine clock expiration,
all quota boundaries or allocation/fault campaigns. Those require their own
execution receipts. No further cases are planned without a concrete uncovered
risk.
