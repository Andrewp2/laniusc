# Concurrent HTTP batch execution tests

The focused driver is
[extended_http_batch_execution.rs](../tests/extended_http_batch_execution.rs).
Its [packet fixture](../tests/fixtures/extended/http_batch/protocol.lani) calls
the public `ext::http_batch::run_until` API. Production request preparation,
scheduling, HTTP framing, decoding, deadlines and cleanup run in Lanius.
Python supplies loopback peers and independent protocol readers in
[oracle.py](../tests/fixtures/extended/http_batch/oracle.py).

This suite targets the existing Linux x86-64 syscall profile. It uses numeric
IPv4/IPv6 loopback addresses, with no DNS or remote service. Python, h11,
`strace`, `/proc`, and the existing compiler test prerequisites are required.
The test ELF has no libc startup or dynamic loader; its mappings and opened
descriptors can therefore be checked directly. This does not establish support
for another target or network environment.

## Focused groups

| Group | Finite scope | Current receipt |
| --- | --- | --- |
| Contracts | 16 process invocations: empty zero-budget input; strided/packed request bytes and stack/Vec job records; nonzero starts; report extraction; malformed late requests; invalid ranges and limits | Passed |
| Overlap and fairness | Five causal schedules: seven jobs at concurrency 1, 2, 3 and 4; a five-job schedule that holds the first response until every later job finishes | Passed on unchanged source-fix retry |
| Framing and mixed results | Ten invocations: fixed, chunked and close framing over IPv4/IPv6 with whole, one-byte and seven-byte peer writes; binary bodies, informational heads, trailers, HEAD, 404, truncation, conflicting framing, upgrade and connection refusal | Passed |
| Limits and cancellation | 18 invocations: zero budgets, exact/below conservative work admission, exact/below deterministic pre-network operation allowance, pending and retained-result caps, reservation-limited concurrency, a shared deadline with completed/active/queued jobs, and independent per-job I/O exhaustion | Passed on unchanged source-fix retry |
| Native faults | 14 invocations: baseline, eight native EIO controls, three single EINTR controls, and two repeated-interruption controls bounded by global operations or deadline | Passed |
| Allocation failures | All 36 reached mmap ordinals in one two-job informational/chunked binary baseline, one ENOMEM at a time; 38 invocations including baseline and recovery, with 10 injected positions after networking started | Passed |
| Consecutive failed-begin refill | One additional causal regression: a held first peer, successful sibling, two queued socket-creation failures, then a successful queued peer that must finish before the first is released | Passed |

Counts describe invocations or the stated baseline, not all possible network
partitions, scheduler interleavings, allocation paths or HTTP features.

## Causal concurrency evidence

For each selected wave, every peer must parse its complete request before any
peer may send a response. A serial exchange loop cannot pass a wave larger
than one: its first response is withheld, so it cannot start the next request.
The external child deadline terminates that failure. After the barrier opens,
peers release responses in reverse order, each waiting for the later peer to
observe client EOF. The returned outcomes must still associate each original
input with its exact independent expected wire bytes and body.

A separate schedule holds job 0's response while jobs 1 through 4 complete in
turn through the other slot. Their peers must observe connection closure before
job 0 is released. This checks progress past a stalled earlier input and refill
of a freed slot. It does not claim a latency bound or fairness against every
possible continuously ready peer. The syscall ledger independently checks that
the number of simultaneously owned sockets never exceeds the configured cap.
Elapsed-time speedups are not used as concurrency evidence.

The separate failed-begin regression keeps the first peer held while the
successful sibling completes, then injects EIO at socket attempts 3 and 4 for
two consecutive queued inputs. Input 4 must still start and complete before
input 0 receives its response. The expected ordered outcomes are Complete,
Complete, Failed, Failed, Complete. Both failures must retain Open/Io/EIO,
one charged socket attempt, no sent/received bytes and no cleanup error.
The trace binds all five socket attempts to one argument/IP shape, requires
exactly the two requested injection markers, and proves that the successful
sibling's actual close precedes the failed-begin prefix. No blocking poll is
allowed between the first failed begin and the next successful socket; a
zero-time probe remains permitted. Both first-wave requests must precede the
successful sibling's response. This adds one focused adjacent regression
without changing the original six accepted cases.

The CPU harness control also connects only the first peer of a two-request
wave and verifies that no response byte is available, then supplies the second
request and checks reverse response release. This checks the barrier itself;
it is separate from production execution acceptance.

## Independent protocol and ownership checks

h11 parses the emitted requests, including the method, target, Host,
Connection, Content-Length and exact binary body. Python `http.client` decodes
successful returned response wires. Exact source response bytes and expected
bodies are checked separately, so two readers agreeing on the wrong selected
message cannot silently pass. Peer write sizes are controlled inputs, not
assumptions about the kernel's receive partitioning.

The fixture overwrites caller request backing after `run_until` returns and
before it reads responses. Complete responses must retain their own method,
wire and body storage. It checks report bounds, takes one outcome, verifies the
Taken slot and repeated-take behavior, destroys the report twice, then reads
and destroys the extracted response. Other responses are released by report
destruction. Failure reports pass through the same sole-owner cleanup path.

Preparation rejection of the second request must produce no socket or connect
effect for any request. Global cancellation retains an earlier complete
response, terminalizes active jobs, and leaves queued jobs unstarted. A native
engine deadline failure can be a Failed timeout outcome; sibling cleanup uses
Aborted. Pending bytes must be zero after return. Report counters reconcile
with published outcomes and engine I/O counters; physical shared polls are
checked separately against the trace.

Retained wire/body caps concern completed owned logical storage, including
informational wire bytes where retained. They are not hard limits on received
bytes, temporary candidates, reserved capacity or peak process memory. The work
gate uses the full configured engine allowance for admission, rather than
treating the smaller actual protocol-work total as an admission threshold.

## Resource and fault evidence

[resources.py](../tests/fixtures/extended/http_batch/resources.py) records every
successful mapping by address and requested length, then requires one matching
successful release. Opened descriptors must each close once; unowned releases,
double releases, wrong lengths, failed releases and surviving owners fail the
check. It reports the maximum live socket count and each syscall ordinal/IP.

Resource/fault runs pause the child after report destruction at a final stdin
acknowledgement. The oracle inspects the actual tracee's `/proc/<pid>/fd` while
it is still alive and requires only inherited descriptors 0, 1 and 2. This
prevents process-exit reclamation from hiding a descriptor leak. Mapping balance
is checked from the complete trace. `strace --kill-on-exit` and bounded peer
threads keep a timed-out test from leaving a product child behind.

Fault assertions require the requested syscall, exact ordinal, INJECTED marker
and named errno. Repeated-injection cases require all affected ordinals.
The allocation sweep additionally compares the target IP/request length and
the entire preceding mmap shape against its baseline. A changed concurrent
coalescing/allocation prefix is a harness discrepancy to diagnose, not evidence
that an unvisited owner was tested. The sweep establishes cleanup for the
finite reached baseline, including pending requests, active engines, complete
responses and the transferred outcome. It does not enumerate all schedules.
The two allocation peers first require both full requests, then release their
rich responses in reverse order. Metadata and all request preparation precede
this barrier; connect/send/poll do not allocate. This preserves overlapping
connections while making response allocation order more reproducible. An
observed reset or broken pipe releases the next fault-wave peer; a timeout
does not substitute for connection termination.

This ledger deliberately rejects injected close errors. `strace` error
injection skips the kernel close, so that technique cannot establish actual
descriptor release on a close failure. The suite's strict cleanup claims apply
to its successful closes under ordinary, allocation, deadline and other leaf
fault scenarios.

## Acceptance

All **seven groups** have accepted native receipts through the root's
serialized compiler/execution queue. Code and fixtures are frozen.

The first contracts group passed all **16 invocations in 9.84 seconds**,
including actual GPU compilation, strict ELF/jump validation and native
execution:

`target/stdlib-work/http-batch-contracts-first.log`

The remaining-five-group invocation took **13.79 seconds** and had mixed
results. Its framing/mixed-result group passed **10 invocations**, native fault
group passed **14**, and allocation group passed all **36 reached ENOMEM
positions** through **38 invocations** including baseline and recovery.
**Ten** injected allocation positions occurred after networking began:

`target/stdlib-work/http-batch-remaining-groups-first.log`

The same invocation exposed a production scheduler refill defect in the
overlap/fairness and limits/cancellation groups. After one exchange completed,
the scheduler waited on a stalled sibling before admitting a queued job into
the freed slot. Both failing reports had only two jobs started and one complete;
the queued job required for causal progress never started before the shared
deadline. These reports identified a production defect. Their fixtures and
assertions were unchanged.

The reviewed source correction refills freed slots before waiting, including
advancing past failed begins in a bounded loop while preserving work-credit
checks. The unchanged two-group retry passed **five overlap/fairness schedules
and 18 limit/cancellation invocations in 9.62 seconds**:

`target/stdlib-work/http-batch-refill-two-groups-retry.log`

The additional consecutive-failed-begin regression passed **one invocation in
8.54 seconds**, with exit 0:

`target/stdlib-work/http-batch-consecutive-begin-failures.log`

It confirmed exactly socket attempts **3 and 4** carried EIO/INJECTED markers,
preserved ordered Complete/Complete/Failed/Failed/Complete outcomes, and allowed
queued input 4 to complete and release held input 0. No blocking poll occurred
between the failed-begin prefix and the next successful socket; zero-time
probes remain permitted. The exact socket call shape, sibling close ordering,
request barrier and before-exit descriptor/mapping cleanup checks passed.
These seven groups were accepted through separate invocations.

Separate CPU infrastructure controls passed for packet parsing, the causal
reverse-release and failed-refill barriers, annotated poll timeout parsing,
ranged fault injection, and strict ledger positive/negative cases. Existing
HTTP, exchange and poll tests have separate scope.
