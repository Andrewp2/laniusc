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
80-byte report header. That attempt did not establish runtime acceptance. The
cause was subsequently classified as a fixture work-budget mismatch. Its one-million
work allowance was insufficient for the default HTTP limits: final canonical
validation reserves `4 * 65536 * 101 = 26476544` units before decoding. The
retained trace showed all three full requests and the required peer-EOF chain,
then wire cleanup without body decoding. Read-only inspection of the native
core dump located the failed aggregate outcome assertion.

The fixture now explicitly bounds HTTP heads to 4096 bytes, lines to 1024,
headers/trailers to 16 and trailers to 1024 bytes, matching the established
plain batch fixture. Its original work allowances, required Complete/Failed/
Complete outcomes, causal peer dependencies and ownership checks remain intact.
Unexpected aggregate counts additionally print failure-only work and I/O
diagnostics before the unchanged assertion.

The corrected fixture passed its serialized Linux x86_64 runtime gate on
2026-10-26 in 10.07 seconds: one test passed, zero failed, and the seven existing
plain batch groups were filtered out. The oracle reported
`http-batch-wait-retirement cases=1 synthetic-driver-error=9001 before-exit-cleanup=1`.
The receipt is
`target/stdlib-work/http-batch-wait-retirement-coherent-limits-retry.log`.
This verifies the one retirement/refill sequence and its HTTP, ordering, socket
cap and owner-cleanup checks. It makes no claim about native fault injection,
other scheduler sequences or the seven separately gated plain batch groups.

On failure, the oracle retains `syscalls.log`, `input.bin`, `native.stdout`,
`native.stderr` and `diagnostic.txt` in a printed temporary directory named
`http-batch-wait-retirement-failure-*`. Diagnostics include the original
assertion, strace return status before and after collection, any termination
needed to stop a live process, and peer events/errors. The diagnostic collector
also passed two CPU controls covering retained evidence and repeated-drain
avoidance; the poll guard passed five controls accepting no poll or a zero
timeout and rejecting positive or infinite waits. These controls test the
oracle rather than add native runtime cases.
