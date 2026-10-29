# Framed Unix request application fixture

The test-only Python peer is a separate process using the host AF_UNIX API.
A readiness pipe acknowledges bind/listen before the application starts; no
startup sleeps are used. The peer independently retains the complete request
through write-half EOF and compares it to a four-byte big-endian length plus
the original input. Expected response bytes are supplied independently of
the production codec. No production module is imported by the oracle.

| Group | Cases | Scope |
| --- | ---: | --- |
| model | 24 | Binary bytes, both namespaces, empty frames, 1024-byte transfer boundaries, exact 1 MiB input/response, 107-byte names, raw non-UTF8 names, literal `@`, empty abstract name and BE32 length boundaries |
| rejection | 17 | Input overflow before socket creation, missing endpoints, truncated response headers/body, oversized/high-bit lengths, trailing bytes/second frame, no response and absent EOF under the real five-second deadline |
| cli | 19 | Exact grammar/help bytes, sole help bypass, argument/namespace/name bounds, no stdin or network calls on rejection |
| io | 24 | Traced baseline, six reached input/response/help-owner allocation failures, retryable read/send/receive EINTR, actual stdin/stdout errors, connect/send/receive/shutdown/close/clock/output/signal faults, 8192-attempt stdin/stdout caps and genuine output prefix |

Every traced successful mmap requires a matching explicit munmap of the same
address and requested length. Every acquired application socket requires one
close attempt, including failures. Connect is attempted once and never replayed
after EINTR. Injected close errors suppress the actual kernel call: the trace
checks invalidation/one attempt, while process exit performs final host cleanup.
It does not claim that the failed close released the descriptor itself.

The peer proves full request framing and write-half EOF on admitted exchanges.
Pathname peers remain present until the fixture explicitly unlinks them. The
two deadline cases hold the connection open without a sleep; one sends no
response and the other withholds EOF after a complete response. A separate
parent-controlled pipe releases the peer only after the application returns;
the request write-half EOF cannot release the peer early. Error cases require
empty stdout before publication. Selected allocation errors require status 4
and no output; trace observations are finite
and do not constitute a resource checker, lifetime proof or exhaustive campaign.

The output-prefix control uses an actual regular stdout file with
`RLIMIT_FSIZE=10` and ignored SIGXFSZ, requiring exactly the first ten expected
binary response bytes and status 5. No successful transfer count is injected.
This case is untraced so its limit cannot truncate strace evidence; separately
traced output faults check explicit owner/descriptor cleanup.

Persistent EINTR uses compact strace summaries for 8192 read errors or 8192
output errors plus the successful stderr diagnostic. These summaries do not
observe mapping releases. The 8192 public network-transfer limit differs from
the count of inner host attempts; this fixture does not claim to force that
limit. Native application children have 15-second deadlines, peers eight-second
socket deadlines, and registered groups 85-second deadlines.

```sh
python3 -B tests/fixtures/stdlib_execution/unix_request/oracle.py controls
python3 -B tests/fixtures/stdlib_execution/unix_request/oracle.py model PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/unix_request/oracle.py rejection PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/unix_request/oracle.py cli PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/unix_request/oracle.py io PATH_TO_ELF
```

Evidence retains app/peer commands, original input, request/response wires,
peer events, output, status, elapsed time and selected syscall traces. CPU
controls cover independent framing and deliberate missing-cleanup violations.

## Acceptance

All four registered groups passed: 84 distinct Linux x86_64 application cases.
The Rust driver compiled through the GPU compiler, admitted the artifact through
the shared strict ELF checker, then ran CPU code. These are separate receipts
for the same frozen application, oracle and release-pipe peer; the boundary
run filters out the model test.

| Receipt in `target/stdlib-work/` | Registered tests | Cases | Runtime | Evidence |
| --- | ---: | ---: | ---: | --- |
| `unix-stream-app-model-first.log` | 1 passed | model 24 | 8.49 s | `/tmp/unix-request-model-mok6db87` |
| `unix-stream-app-boundaries-first.log` | 3 passed | cli 19, io 24, rejection 17 | 21.50 s | `/tmp/unix-request-cli-e65nkgzw`, `/tmp/unix-request-io-9qel0g7v`, `/tmp/unix-request-rejection-i4b8rt2m` |

Accepted identities (SHA-256):

- Application: `10e6ae4be570ff9a34844503a9fe81c651c6e83dfa952ff6c651f9ddc9fb119a`.
- Oracle: `27910405700a69f7cc8bfde285e4abef527f46cf0856faba9a0e78154fd04d58`.
- Peer: `bd22278a5168c97c65abcdf7de10d161547cee76673b9b078298eb1289bc1879`.

The inspected baseline reads 4100 input bytes and actual EOF before creating
one nonblocking CLOEXEC socket. It sends the exact frame, shuts down Write,
receives a 5000-byte response plus actual EOF, closes once, then publishes
the payload. All observed mappings are explicitly released. Input ENOMEM
faults reached mmap ordinals 3 and 6 before socket creation; response faults
reached ordinals 7 and 10 and each attempted one socket close. Help-owner faults
reached ordinals 1 and 2. All six return 4 with empty stdout and matching
releases for every successfully observed mapping.

The no-response and missing-EOF cases took 5.016249 s and 5.017952 s respectively.
Both traces show poll timeout, successful socket close and empty stdout; both
peer logs show request EOF, held-open state, parent release after app return
and peer close. Connect EINTR performs one connect and one close attempt,
without send/receive replay. The injected close error is the one-attempt
observation described above, without an acknowledged kernel release.

Compact summaries confirm 8192 read errors or 8192 write errors plus one
diagnostic write. The untraced file-size-limit control returns 5 and retains
exactly ten actual response bytes (`13 5c a5 ee 37 80 c9 12 5b a4` in hex).
Traced output-error paths separately check owner and socket cleanup.

GPU device execution, other operating systems, formal verification,
exhaustive fault coverage and forced public network-cap exhaustion remain
unclaimed. Driver hashes are omitted because later whitespace formatting does
not change the accepted application, oracle or peer.
