# HTTP batch wait-retirement regression

This focused test uses the actual generic batch scheduler and actual HTTP
Exchanges on loopback. Its test-only driver deliberately returns one terminal,
nonshared error from `before_wait` after job 1 has fully uploaded its request.
The wrapper aborts its actual Exchange first, then retains its final statistics
in a synthetic `Io(Host(9001))` failure at `Stage::Close`. This is a driver
contract error, not an injected native syscall error.

Two slots start jobs 0 and 1. The wrapper waits until job 0's latest interest
proves it has sent its full request and is read-pending without immediate work.
Job 0's peer holds its response until queued job 2 completes and the product
closes job 2's connection. Job 2's peer waits for job 1's real connection EOF.
The required input-ordered outcomes are Complete, Failed, Complete.

The oracle reuses the existing `http_batch` h11 request reader, independent
response reader and strict raw syscall ownership ledger. It checks every full
request, peer EOF and causal response dependency, exactly two concurrent
sockets, final statistics and cleanup before the process-exit checkpoint ACK.
Trace markers additionally reject any positive-timeout poll between retirement
and job 2's socket admission, so spurious readiness cannot hide a premature
blocking poll. Zero-timeout polls are allowed.

Run the one Rust integration test filter
`before_wait_retirement_refills_a_queued_job_before_blocking_on_a_held_sibling`
in `extended_http_batch_execution` through the root's serialized native gate.
The first serialized runtime attempt on 2026-10-26 compiled the fixture but
failed in 10.29 seconds before the report could be read. The oracle raised
`AssertionError: ('premature protocol EOF', None, b'')` while reading the
80-byte report header. No successful runtime acceptance is claimed; the cause
remains unclassified and needs investigation after this checkpoint.
