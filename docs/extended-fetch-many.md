# Concurrent CSV downloads to an ordered ZIP

`sample_programs/library/fetch_many.lani` reads bounded CSV jobs from stdin,
performs cleartext HTTP GET requests through `ext::http_batch`, and stages one
Stored ZIP containing the response bodies. Parsing, scheduling, HTTP framing,
ZIP encoding and stream I/O run in Lanius. Numeric routing endpoints and HTTP
Host authorities are separate inputs.

Build from the repository root:

```sh
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  --stdlib-root stdlib --source-root extended \
  sample_programs/library/fetch_many.lani -o /tmp/fetch-many
```

For servers already listening on the supplied numeric endpoints:

```sh
printf 'archive-name,numeric-endpoint,http-authority,origin-target\none.txt,127.0.0.1:8080,example.test,/one\ntwo.txt,127.0.0.1:8081,other.test,/two\n' \
  | timeout 15s /tmp/fetch-many --concurrency 2 > bodies.zip
```

These commands describe the application contract. Focused Linux x86_64 native
acceptance is recorded below.

## Input and HTTP policy

The decoded header is exactly:

```csv
archive-name,numeric-endpoint,http-authority,origin-target
```

It is followed by 1..64 records of exactly four fields. The canonical CSV
decoder handles quoting, doubled quotes, quoted commas and quoted line endings.
There is no whitespace trimming or additional backslash decoding. Input must
be valid UTF-8 and satisfy the CSV module's control-character policy. Each
decoded record is bounded to 6,208 field-content bytes, each field to 4,096
bytes, and the columns have these additional limits:

| Column | Maximum bytes | Meaning |
| --- | ---: | --- |
| `archive-name` | 1,024 | Exact UTF-8 ZIP entry name. |
| `numeric-endpoint` | 64 | Numeric IPv4:port or bracketed IPv6:port socket address. |
| `http-authority` | 1,024 | HTTP Host field, checked by the canonical request encoder. |
| `origin-target` | 4,096 | GET origin-form target beginning with `/`. |

Numeric IPv6 scopes use the existing socket-address parser; interface-name
resolution is not added. There is no DNS lookup, TLS, redirect following,
request replay, custom-header input or request body. Use the HTTPS clients for
TLS; this app does not send TLS to an HTTPS endpoint.

All rows are decoded, bounded, name-validated and endpoint-parsed before the
batch starts. The batch then canonically prepares **all** requests before
opening its first socket. An invalid late authority or target therefore cannot
leave an earlier row already connected. A later transport or protocol failure
is a per-job outcome; other jobs may finish, but the app rejects the whole
archive if any outcome is not a completed Response.

By default every final HTTP status must be 200..299. `--allow-http-errors`
admits other valid final statuses and their bodies; it does not admit transport
errors, malformed responses, unsupported upgrades or resource failures. Status
policy is checked in CSV order after transport completion. Response bodies have
HTTP transfer framing removed. Content encodings such as gzip are not decoded.

## Archive and publication

Entries use Stored compression and the UTF-8 flag. Names, body bytes and entry
order follow the input rows, regardless of response completion order. Empty and
duplicate names, and literal `.` or `..` components, are permitted by the ZIP
writer. They remain ordered archive records. Consumers examining duplicates
must select entries by ordinal rather than a name-keyed dictionary.

The shared `ext::zip::validate_name` rejects leading slash, a colon in byte
position 1, backslash, NUL and invalid UTF-8 before sockets. No extraction,
filesystem traversal or path normalization occurs. A trailing `/` is a
directory entry and must have an empty response body; final ZIP encoding
enforces that condition after the body is known.

The ZIP archive comment is always CSV containing zero-based row, final status
and decoded body length. For example:

```csv
row,status,bytes
0,200,3
1,404,0
```

The comment ends with a newline and does not add a manifest entry or consume an
entry name. Its fixed 4,096-byte staging limit covers all 64 numeric records.

The full ZIP is encoded before stdout publication. Admission, transport,
status-policy, deadline, allocation and ZIP failures publish no archive bytes.
All request/CSV owners and completed Responses are released before writing
stdout. A failure while publishing can leave the confirmed byte prefix already
accepted by stdout; the app reports its length and never replays it. Success
has empty stderr. There is no flush, file replacement or filesystem atomicity
claim for stdout.

## CLI and resource scopes

```text
fetch-many [--concurrency N] [--timeout-ms N] [--max-input N]
           [--max-body N] [--max-total-body N] [--max-wire N]
           [--max-total-wire N] [--max-output N] [--max-io N]
           [--max-work N] [--max-total-work N] [--max-operations N]
           [--allow-http-errors]
```

Options accept separate or `=` values. Numeric values are decimal digits only,
without signs or whitespace. Unknown options, repeats and operands are errors.
`--help` or `-h` must appear alone. Argument capture is bounded to 64 arguments
and 8,192 bytes.

| Option | Default | Maximum | Scope |
| --- | ---: | ---: | --- |
| `--concurrency` | 4 | 16 | Upper bound on active exchanges; minimum 1. |
| `--timeout-ms` | 5,000 | 60,000 | One absolute batch/ZIP observation deadline. |
| `--max-input` | 65,536 | 262,144 | CSV stdin bytes. |
| `--max-body` | 1,048,576 | 8,388,608 | Per-response decoded body and ZIP entry bytes. |
| `--max-total-body` | 8,388,608 | 33,554,432 | Retained completed decoded body lengths; also ZIP total body bytes. |
| `--max-wire` | 2,097,152 | 16,777,216 | Per-exchange response accumulation bound. |
| `--max-total-wire` | 16,777,216 | 67,108,864 | Retained completed logical response wire lengths, including informational prefixes. |
| `--max-output` | 16,777,216 | 41,943,040 | Entire encoded ZIP, including metadata and comment. |
| `--max-io` | 100,000 | 1,000,000 | Per-exchange I/O allowance, including poll participation; minimum 1. |
| `--max-work` | 33,554,432 | 268,435,456 | Per-exchange protocol allowance. |
| `--max-total-work` | 268,435,456 | 1,073,741,824 | Aggregate conservative protocol allowance. |
| `--max-operations` | 1,048,576 | 10,000,000 | Aggregate scheduler operations. |

Except for concurrency and I/O allowance, zero is admitted. Zero byte or work
caps can reject even a small otherwise valid transfer. A zero timeout provides
no network grace. Limits fail explicitly; they do not truncate a successful
archive or silently omit a job.

The batch reserves each active exchange's remaining protocol allowance. A tight
aggregate work cap can admit fewer active exchanges than the concurrency cap
and can conservatively refuse work before its actual instruction cost is known.
The per-exchange allowance does not change when concurrency changes. These are
abstract protocol and scheduler counters, not CPU-instruction measurements.

The aggregate body/wire caps count **retained completed logical lengths**. They
do not count every byte received over all sockets, active exchanges, discarded
over-limit candidates, allocator spare capacity or peak RSS. Each active
exchange separately obeys its response/body bounds. A completed candidate that
would exceed a retained cap is discarded, active siblings are cancelled, and
earlier completed Responses remain owned by the returned failure report until
the app releases them. No partial archive is published.

Pending encoded request plus copied-method lengths have a fixed 4,194,496-byte
batch cap. That logical counter excludes one preparation candidate, spare
capacity and temporary owners. Each request has a 65,536-byte encoding cap.
These counters bound their stated storage categories; they are not a native
resident-memory theorem.

Per exchange, response heads are limited to 16 KiB, lines to 8 KiB, headers to
64, trailers to 4 KiB/32 fields, chunks to 4,096, and informational responses to
four within 16 KiB cumulatively. ZIP encoding has an independent fixed 64 Mi
work allowance and at most 64 entries. Canonical CSV, HTTP and ZIP validation
remain authoritative within these app limits.

## Deadline and I/O boundaries

The absolute deadline starts after stdin reading, CSV admission and the job
descriptor staging. It includes canonical request preparation, network
scheduling, and clock observations before and after synchronous ZIP encoding.
Retries and interrupted calls do not reset it. ZIP encoding is not interrupted
mid-call; its byte/work bounds and the following clock observation determine
whether publication is allowed. This is an observation deadline, not a hard
whole-process wall-time guarantee.

Blocking stdin acquisition and final stdout/stderr publication are outside the
network deadline. Stdin permits at most 16,384 host attempts, stdout 65,536 and
diagnostics 1,024. EINTR consumes an attempt and retries; WouldBlock fails.
Reading exactly the byte cap still requires a positive-capacity EOF probe, and
an extra byte is rejected. Short positive writes advance the confirmed prefix;
zero, negative or oversized counts are invalid. SIGPIPE is ignored for checked
publication errors. Host calls, scheduling delays and process termination can
still exceed or interrupt these bounds.

## Errors and ownership

| Exit | Meaning |
| --- | --- |
| 0 | Complete ZIP published, or standalone help published. |
| 2 | Arguments, CSV/static admission, HTTP status policy or ZIP validation/quota. |
| 3 | Transport/protocol, deadline, clock or batch budget failure. |
| 4 | Reported allocation failure, including nested request preparation. |
| 5 | Signal policy, stdin, stdout or diagnostic I/O failure. |

Failure diagnostics begin `fetch-many:` and contain numeric `stage`, `row`,
`status`, `cause`, `errno`, `cleanup`, `io`, `work`, `written` and `exit` fields.
Row is zero-based or -1 when no input row is selected; status 0 means absent.
Native errno fields are 0 when no host errno is available. `written` records
the confirmed stdout prefix for publication failure. An unsuccessful diagnostic
write returns 5 and is not replayed.

Stages are arguments 1, stdin 2, CSV admission 3, batch 4, HTTP status policy 5,
ZIP/its clock observations 6 and publication 7. Causes are CSV 1, allocation 2,
column bound 3, name 4, endpoint 5, internal length mismatch 6, HTTP status 7,
ZIP 8, static request preparation 9, per-job failure 10, deadline 11, clock 12,
poll 13, scheduler operations 14, protocol work 15, retained wire 16, retained
body 17, pending requests 18, invalid batch/outcome 19, stdin 20, arguments 21
and publication 22. The batch's I/O and charged protocol-work counters are
copied into failure diagnostics; they are not a success telemetry interface.
I/O accounting includes conservative poll-participation reservations, so a
later global failure can leave charged participation without a physical poll.

The CSV table backs name, target and authority views until batch return and ZIP
encoding. Completed Response owners back projected body views only during
encoding. The app never destroys a borrowed Response copy: it destroys the
Report once those views have ended, including on every rejected outcome,
projection allocation failure, deadline failure and ZIP error. Global failure
reports release retained successful responses as well as their descriptors.
This uses the libraries' explicit owner protocols; it adds no automatic Drop
or stale-alias safety claim.

## Focused acceptance

[`tests/extended_fetch_many_execution.rs`](../tests/extended_fetch_many_execution.rs)
defines five focused native groups. All five passed on Linux x86_64 through
the GPU compiler, in separate invocations:

| Receipt under `target/stdlib-work/` | Accepted groups and cases | Duration |
| --- | --- | ---: |
| `fetch-many-failures-limits-io-first.log` | Limits: 66; real I/O: 19; appended production stream helpers: 38 internal scenarios. The earlier 30-case failures group also passed here. | 18.81 s |
| `fetch-many-matrix-failures-resources-final.log` | Matrix: 16; expanded failures: 31; resources: 61, including all 59 reached allocation-failure positions. | 15.63 s |

These receipts establish the five groups separately; there was no single
all-green invocation of the complete driver. The matrix checks independent CSV
and ZIP interpretation, causal concurrent request overlap, input-order archive
output despite later-row-first completion, status comments, quoting and body
framing. The failures and limits groups check admission before sockets, status
policy, protocol/transport rejection and explicit byte/work/I/O bounds. Real
and scripted I/O checks preserve confirmed output prefixes and finite retry
budgets.

The initial matrix invocation failed after 10.08 s in
`fetch-many-matrix-first.log`: its positive HTTP 204 fixture incorrectly included
`Content-Length: 0`, which the canonical HTTP engine rejects. The corrected
positive has a head-only 204 response; the exact former invalid response is
retained as a negative in the 31-case failures group. The 206 positive also has
its single-range Content-Range header. This was a fixture correction; no
production app change was needed for the final acceptance.

The allocation campaign injects one ENOMEM at each of the 59 mmap positions
reached by its two-job baseline. It verifies the activated ordinal, instruction
address and requested length, allocation exit 4, empty stdout, and exact mapping
and socket cleanup ledgers. This is finite single-fault coverage of that
baseline, not every allocation path for every input. Each oracle invocation
also runs 15 CPU controls that reject malformed or mismatched injection
markers; those controls are separate from native process-case counts.

One traced scale case fetched 64 jobs with 65,536 decoded body bytes and
produced a 72,861-byte ZIP. It observed four simultaneous sockets, 1,133
allocation requests and a peak of 349,680 live requested mapping bytes. Its
observed elapsed time was 0.245 s under tracing. The requested-byte ledger does
not measure page rounding, peak RSS or the tracer's memory. This is one bounded
correctness/resource observation, with no comparative throughput or larger-load
performance claim.

Test-only peers provide numeric loopback endpoints; the application itself does
not start a server or invoke a helper process. The driver requires `strace`
with syscall injection and Linux descriptor behavior, including `/dev/full`.
Other runtime platforms are outside this evidence. The logical quota and
deadline limitations above continue to apply.

Root-serialized reproduction:

```sh
timeout --kill-after=2s 100s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 \
  CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --locked --test extended_fetch_many_execution -- --nocapture --test-threads=1
```
