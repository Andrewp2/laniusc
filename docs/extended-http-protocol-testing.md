# Direct HTTP Protocol execution contracts

`tests/extended_http_protocol_execution.rs` compiles
`tests/fixtures/extended/http_protocol/contracts.lani` through the production
GPU compiler into a Linux x86-64 syscall-only ELF, checks the executable format
and generated jumps, then executes its assertions under `strace`.

The fixture drives the public concrete `ext::http_client::Protocol` directly.
Its in-memory driver supplies accepted send prefixes and acknowledges cleanup
of its empty transport. It owns no socket, TLS session, or pending native
operation. These checks target HTTP state and ownership contracts; the existing
plain Exchange and HTTPS tests establish actual transport behavior separately.

## Focused state space

| Family | Executed assertions |
| --- | --- |
| Preparation and owned completion | Release every caller request allocation before transfer; disarm the actual Prepared; reject repeated transfer; copy a native strided receive view before its backing is overwritten; preserve final method/body/trailer and informational-head views after Protocol transfer; publish one Response only. |
| Send reservations | Bound reservations to 1024 bytes; partially commit; verify the next exact request prefix; cancel without advancing progress; reserve the same prefix again; finish the request; release an active Protocol once. |
| Early final response | Observe StopUpload while a reservation remains; acknowledge the policy without claiming write shutdown; permit that earlier reservation's positive partial commit; suppress new reservations; explicitly record shutdown; finish the response with the confirmed send count. |
| Premature transport acknowledgement | Reject acknowledgement before HTTP completion and after decode while a send reservation remains; retain the original failure until explicit release. |
| Exact Close caps | Return a positive one-byte EOF probe when raw and decoded caps are exact; accept genuine EOF; count a positive overflow byte before returning the raw or body limit; retain no overflow byte in a published response. |
| Trailing policy | Discard and count an already-read tail, or reject it with the final-message-relative offset and the separate informational-message connection offset. |
| Invalid operations and allowances | Reject a second reservation and a zero commit; keep per-Protocol poll/I/O allowance cumulative; reject transfer from a destroyed Prepared. |

Saved failures are compared across repeated operations, attempted replacement
of the cause, explicit abort, and repeated abort. The comparison includes cause
and HTTP offset, stage, connection message offset, all progress counters and
flags, and cleanup metadata. A failed Protocol retains its original diagnostics
after its buffers have been released; a completed or normally aborted owner
reports Inactive without inventing a saved failure.

All local-drain and send loops have explicit small turn limits. The fixture
uses one generous absolute deadline per preparation; it does not sleep or wait
on another process.

## Explicit cleanup evidence

The test-only Python harness reuses
`tests/fixtures/extended/http_batch/resources.py` without modifying it. The
existing syscall ledger requires every successful mapping to have one explicit
matching unmap with the same address and requested size, and rejects unknown or
duplicate releases. Process exit does not produce those unmaps and cannot hide
a missing destroy call. Both successful Response paths and deliberately failed
Protocol paths run in this trace.

The harness also requires zero socket, connect, poll, send, receive, shutdown,
and close calls. It checks the fixture's final success marker and exit status.
There is no second HTTP parser or protocol implementation in the harness.

## Acceptance

The focused test
`direct_protocol_reservations_boundaries_and_manual_owners_execute_without_transport`
passed on Linux x86-64 through the production GPU compiler in **7.94 seconds**.
The root's serialized receipt is
`target/stdlib-work/http-protocol-direct-contracts-first.log`. The separate Rust
driver build completed in 1.04 seconds and is recorded in
`target/stdlib-work/http-protocol-direct-driver-build.log`.

The native fixture reached its final success marker and exited successfully.
The shared ledger reported **247 successful mapping events**, each explicitly
released with its matching unmap, and zero traced network/poll/close calls:

```text
http-protocol states checked allocations=247 explicit-owner-ledger=balanced no-network
```

This is one executable state-contract group, including its deliberate API
failure paths. The 247 events describe that run's allocation activity; they are
not 247 allocation-denial tests. The fixture and production Protocol were
unchanged for this acceptance run.

The finite direct cases do not establish OpenSSL retry behavior, real network
readiness, delayed native return accounting, deadline fault behavior, exhaustive
allocation denial, parser conformance, or GPU execution of a network program.
Those contracts belong to their focused existing transport and wire tests.
