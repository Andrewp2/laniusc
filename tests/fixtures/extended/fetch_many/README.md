# Concurrent downloader application checks

The driver is `tests/extended_fetch_many_execution.rs`. Production code is
`sample_programs/library/fetch_many.lani`; this directory contains test peers,
independent oracles and an appended consumer of the real stream helpers.
All five groups pass GPU compilation followed by native Linux x86_64 execution
through separate focused receipts, covering 194 application/consumer processes.

## Contract under test

Stdin has the exact decoded CSV header
`archive-name,numeric-endpoint,http-authority,origin-target`, followed by one
through 64 four-field rows. Python's `csv` module constructs and independently
checks valid fixture rows. The application issues one bodyless cleartext GET
per row to its numeric endpoint, with the supplied separate HTTP authority.
There is no resolver, TLS, redirect following or request replay in this profile.

The output is a complete Stored ZIP with UTF-8 names and body entries in CSV
order. The archive comment is exactly `row,status,bytes\n` followed by decimal
zero-based row/status/decoded-length records in that order. Python's `zipfile`
reads each `ZipInfo` from `infolist()` rather than selecting members by name,
so duplicate and empty names remain distinct. Quoted Unicode, commas, quotes,
CR/LF, duplicate names, empty names and dot segments are preserved where the
canonical ZIP policy accepts them. Names are never filesystem paths here.

The default application requires every final status to be 2xx.
`--allow-http-errors` archives other valid final statuses without following
redirects. Static CSV/name/endpoint and canonical request failures occur before
sockets. Any transport, policy, ZIP or prepublication allocation failure emits
no ZIP prefix. Final stdout failures can leave a confirmed byte prefix.

## Five groups

- **Matrix:** binary payloads, deterministic archives, CSV quoting, names,
  IPv4/IPv6, fragmented/fixed/chunked/close-delimited/informational HTTP,
  statuses and causal concurrency at 1/2/4/16 slots. Sixteen slots are supplied
  enough aggregate reserved work; concurrency is an upper bound when credit
  is smaller.
- **Failures:** malformed or late-invalid input, no-socket canonical admission,
  non-2xx policy, directory bodies, malformed HTTP, refusal and stalled peers.
- **Limits:** public CLI caps, exact input/result/archive bounds, aggregate
  retained wire/body limits, operations/work/time limits and the application's
  fixed header/head/line/trailer/chunk/interim profile.
- **I/O:** real input/output/network syscall faults with exact injected markers,
  `/dev/full`, broken pipes and a real 19-byte short file write. A compiled
  appended fixture calls the production `read_input`/`publish` bodies in 38
  internal scenarios for short transfers, EOF probes, retry/call bounds,
  invalid counts and confirmed prefixes. Publication is write-only and does
  not implicitly flush an arbitrary generic sink.
- **Resources:** every allocation observed in a representative two-job run is
  failed once with ENOMEM at its exact mmap ordinal, instruction and size.
  The shared raw batch ledger checks every source mapping and socket release.
  A 64-job, 64 KiB decoded-body observation records archive size, syscall socket
  peak, allocation count, requested-memory peak and elapsed time.

## Causal concurrency and ordering

`peers.py` uses h11 to parse complete requests and verify GET, Host,
Content-Length zero and Connection close. A barrier holds **every** response
until the configured number of different request heads arrives. A sequential
client cannot complete this exchange. Tests compare no elapsed-time speedup.
The syscall ledger separately checks peak socket ownership against the cap.

A second gate holds row zero while row one sends its complete response,
shuts down its sending side and observes the product's EOF/close. Only then
does it release row zero. The ZIP names, bodies and status comment must still
follow CSV order. This detects ordering by completion without scheduling luck.

The positive 204 fixture has no Content-Length, Transfer-Encoding or body.
Its former invalid `Content-Length: 0` wire is retained as a paired negative
that requires protocol failure, empty stdout and complete cleanup. The positive
206 fixture includes a matching single-part Content-Range and unchanged binary
body. These cases check returned status/body framing and metadata; they do not
claim range-request generation or partial-representation reassembly support.

## Fault and resource scope

The Python peers use sockets and test-only HTTP fixtures. CSV/ZIP validation
uses standard Python libraries. `http_batch/resources.py` is imported read-only
as a shared strict syscall-only ELF mapping/fd ledger; no alternate production
downloader is implemented in Python or Rust.

Faults must carry exactly one strace `INJECTED` marker, bound to the requested
syscall, its global per-syscall ordinal and exact errno or returned count, with
no unrelated markers. Stdin/stdout/diagnostic write faults also check the
intended descriptor. Fifteen CPU controls exercise the real trace parser and
matcher with valid requests and rejecting mutations. Tracers use
`--kill-on-exit` so killing an owned tracer on timeout also kills its tracee.
A file-size limit makes the kernel accept a real stdout prefix before EFBIG;
successful short writes are never faked with an injected return count.
Close-error injection is excluded because strace suppresses the real close;
it cannot establish actual descriptor cleanup on that path.

The scale observation includes startup, CSV, loopback exchange, ZIP encoding,
stdout transport and syscall tracing. It is not a throughput comparison or an
RSS quota. Batch retained-wire/body caps describe completed logical owners;
per-exchange work, aggregate conservative reserved work, exchange I/O including
poll participation and scheduler operations remain separate public budgets.
Cleanup is checked after both success and failure; peers and temporary storage
belong to the test runner.

## Accepted receipts

| Group | Accepted process cases | Receipt |
| --- | --- | --- |
| Matrix | 16 | `target/stdlib-work/fetch-many-matrix-failures-resources-final.log` |
| Failures | 31, including the paired invalid 204 | Same final receipt |
| Resources | 61: one baseline, 59 one-shot OOM injections and one scale observation | Same final receipt |
| Limits | 66 | `target/stdlib-work/fetch-many-failures-limits-io-first.log` |
| I/O and appended helper | 19 application processes plus one consumer with 38 internal scenarios | Same earlier receipt |

The final matrix/failures/resources invocation passed in 15.63 seconds. The
limits and I/O/consumer results belong to the separate 18.81-second invocation;
its earlier 30-case failure group is superseded by the final 31-case receipt.
These selected invocations establish all five groups, not a whole-suite run.
The original 10.08-second matrix attempt in
`target/stdlib-work/fetch-many-matrix-first.log` rejected the invalid positive
204 fixture; the corrected positive and paired negative are covered above.
Both application and appended consumer passed explicit executable ELF
classification and the unchanged common x86 jump validator.

The 64-job traced observation accepted 65,536 decoded body bytes and emitted
72,861 ZIP bytes. It recorded four peak owned sockets, 1,133 allocation
requests, 349,680 peak simultaneously requested source bytes and 0.245 seconds
for the traced child invocation. The two-job baseline reached 59 allocations;
each was failed in turn at the exact mmap ordinal, instruction and size, with
no stdout archive and a balanced mapping/socket ledger. These are finite input
and schedule observations, not a universal allocation-failure proof, native
memory/RSS bound or throughput benchmark. The 15 CPU matcher controls and 38
internal helper scenarios are separate from the 194 process count. No other
host or GPU-kernel execution claim is made.
