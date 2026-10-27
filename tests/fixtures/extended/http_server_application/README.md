# Plain application regressions after scheduler migration

`../http_server_oracle.py` targets the actual `http_serve.lani` program, through
its numeric loopback socket and independent h11 clients. The application now
uses the common `server_poll` scheduler. The matrix, quota, limits, boundaries
and fault groups have the accepted current native receipts below. Historical sequential
matrix receipts and the separate direct Exchange/facade/concurrency receipts
remain separate evidence. Source and oracles are frozen.

Use the current root-built executable:
`target/stdlib-work/http-serve-concurrent-current`. Its compile receipt is
`target/stdlib-work/http-serve-concurrent-current-compile.log`. The older
`http-serve-concurrent` executable remains tied to its earlier receipts.

## Accepted current application receipts

Root ran these groups against the fresh current executable and inspected their
reached-injection, exact allocation-prefix/IP/size and ownership assertions:

| Mode | Accepted scope | Receipt in `target/stdlib-work/` |
| --- | --- | --- |
| `matrix` | 30 IPv4/IPv6, fixed/chunked/binary/fragmented/Expect/routing cases. | `http-serve-current-matrix.log` |
| `quota` | 1 case: the accepted owner exhausts `io=12` with one flag check and eleven reached EINTR receives. | `http-serve-current-quota-first.log` |
| `limits` | 16 cases, including malformed/capped input, empty input, explicit budget/deadline failures and 1 MiB echo. | `http-serve-current-limits-first.log` |
| `boundaries` | 25 cases, including exact drain, no-100 preflight, line/head precedence, reached late-success progress, two accepted owners and invalid CLI vectors. | `http-serve-current-boundaries-first.log` |
| `faults` | 41 cases: 23 dynamically reached source allocation positions plus 18 baseline/I/O/retry/quota/close/stdio cases. | `http-serve-current-faults-first.log` |

These groups total 113 process case invocations. The standalone quota also
occurs inside the fault group, so that total includes overlapping coverage.
All receipts are Linux x86-64 host execution. The refreshed 30-case matrix
receipt belongs to the current executable; historical sequential matrix and
earlier migrated-build causal receipts retain their own scope.

## Audited contracts and migrations

The HTTP status/body vectors, 1 MiB echo, 50 ms deadlines with a reached 150 ms
syscall delay, line/head/body limits, no-100 preflight, and exact drain caps
0/17 with uploads 0/17/18 remain unchanged. CLI tests still require exact exit
2. The two-request boundary case opens two distinct connections; it does not
claim causal concurrency or persistent HTTP support.

The old quota test summed listener flag/accept and all physical polls into the
connection's `io=12`. The current contract excludes listener operations and
charges conservative owner wait participation. The test keeps the limit 12:
all receive attempts return injected EINTR, leaving immediate interest, so
the accepted owner's one nonblocking flag check plus eleven native receive
attempts must exhaust exactly 12. Listener operations are counted separately,
and no physical poll on that accepted fd may substitute for a receive attempt.
The report must preserve zero received/sent bytes, code 3 and `io=12`.

Reports now use the unchanged strict field parser from the concurrent service
oracle, loaded without executing that oracle. Accepted IDs must be dense and
ordered; code/failed, closed/cleanup and successful send/shutdown/EOF fields
are checked. A global failure may have no accepted report. A listener close
error may produce process exit 3 after an otherwise successful code-0 owner
report. Failed transport paths may reset their peer; successful HTTP and
empty-input cases still require their normal EOF and response checks.

The allocation campaign derives its position count from one successful 6 KiB
echo baseline, then requires the intended ENOMEM marker at each global mmap
ordinal. Instruction address, arguments and every prior successful allocation
must match that baseline through the fault. This covers the reached source
allocations of that one path, including scheduler storage and startup; it is
not exhaustive allocation coverage. A handled, fully sent allocation rejection
must independently parse as empty HTTP 500 while retaining process exit 4.

First-global accept/fcntl/clock EIO can occur in service admission/startup, so
these cases do not pretend all errors originate in a connection's active I/O.
Each injected EIO/EINTR/close failure must actually reach its requested syscall
ordinal. Close EIO injection skips the kernel call: this application campaign
checks logical retirement after process exit, which releases that retained fd.
It does not claim pre-exit physical release for a skipped close. The separate
direct abort fixture repairs and checks that descriptor before exit.

Startup and Continue reads now have bounded waits and reject premature EOF.
Failed checks retain a printed `http-server-app-*` directory. Traced groups
keep request, response, stdout/stderr, command, diagnostic and source traces
together until ownership/injection/prefix checks finish. An intervention that
kills a live child is diagnostic data and cannot make a case pass.

The standalone Connection/facade `native` mode, independent request encoder and
h11 response parser have unchanged ASTs. The reused raw mapping/fd helper only
normalizes optional instruction-address prefixes; its exact mapping lengths
and logical descriptor release semantics are unchanged.

## Narrow root invocations

Run each command separately, under two minutes. The modes remain parameterized
by the actual executable; these commands do not rebuild it.

```sh
timeout --kill-after=2s 100s python3 -B tests/fixtures/extended/http_server_oracle.py quota target/stdlib-work/http-serve-concurrent-current
timeout --kill-after=2s 100s python3 -B tests/fixtures/extended/http_server_oracle.py limits target/stdlib-work/http-serve-concurrent-current
timeout --kill-after=2s 100s python3 -B tests/fixtures/extended/http_server_oracle.py boundaries target/stdlib-work/http-serve-concurrent-current
timeout --kill-after=2s 100s python3 -B tests/fixtures/extended/http_server_oracle.py faults target/stdlib-work/http-serve-concurrent-current
```

| Mode | Finite scope |
| --- | --- |
| `quota` | One accepted owner, `io=12`, eleven reached EINTR receives. |
| `limits` | 16 cases: handled malformed/bounded requests, explicit failures, empty input and 1 MiB echo. |
| `boundaries` | 25 cases, retaining exact drain, late-success progress, line/target precedence, two distinct owners and invalid CLI vectors. |
| `faults` | Baseline allocations A plus 18 cases; the accepted current run measured A=23 and 41 cases. Output includes `source-allocation-positions=A`. |
| `line-limits` | The same eight line/head precedence cases, separately selectable. |
| `matrix` | 30 IPv4/IPv6, fixed/chunked/binary/fragmented/Expect/routing cases, accepted on the current executable. |

The Rust driver's former `faults cases=35` literal assumed an older allocation
count. Its assertion now parses a positive `source-allocation-positions=A` and
requires `cases=A+18`; it does not drop newly reached allocations to preserve
the old count.
New concurrency/service-timeout CLI bounds are outside these old vectors and
remain a separate coverage gap; this migration adds no new native case.

## CPU checks

```sh
timeout --kill-after=2s 10s python3 -B tests/fixtures/extended/http_server_oracle.py controls
```

Sixteen CPU controls pass, covering strict report fields/IDs/progress,
independent binary response parsing, IP-prefixed source traces, per-owner quota
identity and exact injected errno. The 33 existing direct-server CPU guards
also pass against the reused helpers. Python syntax and scoped whitespace
checks pass. These checks start no native child and do not establish application
acceptance.
