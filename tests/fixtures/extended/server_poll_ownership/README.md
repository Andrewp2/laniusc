# Actual Server owned error controls

All three finite profiles passed in 13.60 seconds, including compilation,
validated x86_64 ELF execution, six peer EOF checks and pre-exit source/native
ownership checks. The authoritative receipt is
`target/stdlib-work/server-poll-owned-errors-current.log` (exit 0); the native
executable was retained at `/tmp/server_poll_ownership_native_238461_0`.
The exact Rust filter is
`actual_server_retains_owned_factory_driver_application_and_abort_errors`.

An earlier shell command referenced a missing test binary and exited 127.
Neither the compiler nor a native case ran in that invocation. It is not a
failed library or fixture execution receipt.

All error outcomes originate in the actual persistent Server rather than being
pushed into a manually constructed Report. Transport E uses
Option<Result<Payload,i64>>, application A uses Result<Option<Payload>,bool>,
and Payload owns a Vec containing binary bytes plus a wide nested stamp.
Every error has separate cleanup authority and an independent lifetime ledger.

1. Factory.begin fails after allocating Protocol input backing and acquiring a
   real accepted socket. Partial source/native owners are released. Its owned E
   is taken from the live Server before the queued healthy owner is admitted;
   that E remains readable after the eventual report is transferred/destroyed.
2. Driver.step fails after real Protocol head backing exists, while a healthy
   sibling remains active. Its owned E stays in the Server until actual
   Server.destroy disposes it. Repeated destruction cannot release it again.
3. Handler Err supplies a separately owned A after an atomic response preflight
   failure. Driver.abort supplies a new owned secondary E after physically
   closing its socket. Both survive report transfer/take and storage disposal;
   final outcome disposal must release secondary E before A, exactly once.

Each healthy owner must continue to a real Protocol Complete event, with
copied response preparation, full acknowledged response length, shutdown/EOF
metadata and actual descriptor retirement. Transport acknowledgements and HTTP
input are scripted test-driver actions; no HTTP response bytes are sent over
the sockets. These cases establish error storage/transfer/disposal and sibling
progress, not HTTP wire, genuine host-error injection or TLS acceptance.
The abort error is a scripted diagnostic following a successful kernel close,
not a claim that a failed close released a descriptor.

The native process waits for acknowledgement after all owners are disposed.
The independent harness reuses the already accepted publication fixture's
source mmap/munmap and socket/close ledger, unchanged: six accepted peers must
observe actual EOF, all mappings and descriptors must balance before exit, and
`/proc` must show only descriptors 0, 1 and 2 at the checkpoint. The source-only
ELF introduces no C observer or native-library heap into this ledger.

This three-profile receipt is separate from the seven previously accepted
publication/preparation controls in `../server_poll/README.md`. It establishes
the finite owned-error paths above, including a taken E/A remaining readable
after report storage release and exact one-time disposal. It adds no native
HTTP wire, TLS, genuine host-error injection, general quota-boundary or
allocation-failure acceptance.
