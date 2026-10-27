# Fetch a URL

Status: source admission and three focused direct functional groups pass on
the finite native profile below. Source-owner/allocation and broader fault
acceptance remain separate and pending. The full standard and extended library
goal remains open.

[`sample_programs/library/fetch.lani`](../sample_programs/library/fetch.lani)
performs one HTTP or verified HTTPS request from a URL and writes the decoded
response body to stdout. It composes the owned
[`URL plan`](../extended/ext/http_url.lani), shared
[`TCP selector`](../extended/ext/url_connect.lani),
[`plain facade`](../extended/ext/url_client.lani) and
[`TLS facade`](../extended/ext/url_tls.lani). All HTTP serialization, framing
and decoding remain in the canonical client. OpenSSL supplies TLS, certificate
verification and cryptography.

The existing `http_fetch.lani` and `https_fetch.lani` programs remain explicit
numeric-endpoint/authority/identity transport probes. Their CLI contracts are
different; they are not aliases or fallback parsers for this program.

## Command line

The exact help text is:

```text
Usage: fetch URL [OPTIONS]
Options: --method METHOD --header NAME:VALUE --body FILE --ca-file FILE
         --client-cert CHAIN --client-key KEY --timeout MS --connect-timeout MS
         --max-output N --max-request N --max-response N --max-body N
         --max-work N --max-io N --max-tls N --max-socket-calls N
         --max-attempts N --max-results N --max-stdout-calls N --max-body-calls N
         --help, -h
```

The canonical CLI parser allows options before or after the single URL, handles
`--`, and accepts attached long values. Scalar options use their last value;
repeated headers preserve their order. There is no shell-word parsing or
response-file expansion. The owned argv snapshot caps 64 arguments and 32768
bytes, excluding terminating NULs. Borrowed argument values stay live through
the request. `--help` requires a complete, valid option parse and at most one
operand, but does not require a URL or open body/trust files. Unknown options,
missing values and extra operands fail even when help was requested.

The default method is GET. `--body` sends the file's bytes with the selected
method; it does not select POST. `FILE` equal to `-` names an ordinary file
called `-`; stdin is not consumed. Header values may be empty, but a header
requires a nonempty name and colon. Canonical preparation checks method/header
syntax and rejects application overrides of Host, framing and other reserved
headers. No request can override the URL-derived authority, target or identity.

Example commands:

```sh
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  --native-link --native-library ssl --native-library crypto \
  --stdlib-root stdlib --source-root extended \
  sample_programs/library/fetch.lani -o /tmp/fetch

timeout --kill-after=2s 20s /tmp/fetch 'http://127.0.0.1:8080/document?raw=1'
timeout --kill-after=2s 20s /tmp/fetch 'https://localhost:8443/document' \
  --ca-file /tmp/local-ca.pem > /tmp/document
timeout --kill-after=2s 20s /tmp/fetch 'https://localhost:8443/upload' \
  --ca-file /tmp/local-ca.pem --method POST --body /tmp/payload.bin \
  --header 'Content-Type: application/octet-stream'
```

This combined executable intentionally links SSL/crypto even when a particular
invocation uses HTTP. The plain `url_client` module itself remains free of that
source/link dependency.

## URL, trust and connection policy

The [URL-client contract](library-url-client-plan.md) defines the exact admitted
URL profile: absolute HTTP(S), checked nonzero port, strict IP syntax or shared
ASCII DNS admission, no userinfo/encoded hostname/zone identifier, and explicit
legacy-numeric rejection. The app uses default URL caps: 16384 raw URL bytes,
8192 generated target bytes and 253 DNS-host bytes. Empty paths become `/`;
encoded path/query bytes and explicit authority spelling are preserved. A
fragment is validated but omitted from the request.

HTTPS uses default OpenSSL trust paths unless `--ca-file` supplies a CA file.
`--client-cert` and `--client-key` must appear together and select the native
credential constructor once, with an empty passphrase. This app provides no
interactive passphrase handling or verification-disable flag. HTTP rejects
explicit CA, client-credential and `--max-tls` options before any body-file,
context, resolver or socket operation. The pair check also precedes those
operations. URL and argument snapshot allocations may already exist.

DNS URLs resolve once through synchronous system NSS. Returned address order
and duplicates remain intact; one nonblocking TCP attempt runs at a time.
Numeric URLs bypass lookup. Endpoint failures eligible under the shared
selector may advance within the attempt/call/deadline limits. The first proven
TCP connection ends fallback; the canonical driver adopts that same owner.
TLS verification/handshake or HTTP failure cannot contact a spare address.
DNS Host/SNI/certificate identity stays the original URL name when the chosen
endpoint is an IP address; numeric URLs use IP SAN verification without SNI.
No proxy, redirect, connection reuse, content-encoding decompression or retry
after TCP selection is implicit.

## Limits and timing

| Option | Default | Admitted values / scope |
| --- | --- | --- |
| `--timeout` | 5000 ms | 0..60000; shared absolute deadline |
| `--connect-timeout` | 5000 ms | 1..60000; each attempt also stops at the shared deadline |
| `--max-request` | 2097152 | 0..16777216; canonical encoded request |
| `--max-response` | 2097152 | 0..16777216; canonical received response storage |
| `--max-body` | 1048576 | 0..16777216; request file and canonical decoded body bound |
| `--max-output` | 1048576 | 0..16777216; complete decoded body before first stdout write |
| `--max-work` | 67108864 | unsigned u64; canonical HTTP work |
| `--max-io` | 65536 | positive u64; canonical HTTP driver I/O quota |
| `--max-tls` | 32768 | positive u64; TLS driver attempts; explicit option requires HTTPS |
| `--max-socket-calls` | 512 | unsigned u64; shared TCP selector's exact socket-call budget |
| `--max-attempts` | 16 | 1..4096; ordered candidates attempted |
| `--max-results` | 32 | 1..4096; resolver-result admission |
| `--max-stdout-calls` | 65536 | unsigned u64; actual body/help write attempts, including EINTR |
| `--max-body-calls` | 65536 | unsigned u64; actual body open/stat/read/close attempts, including failed/EINTR calls |

Values use checked unsigned decimal. Invalid domains report configuration
failure; a valid budget that runs out reports an operational limit failure.
Zero work/output/byte/call budgets are meaningful where admitted. An empty
response succeeds with output and stdout-call budgets both zero. Help obeys
the stdout-call budget but is not constrained by the body output byte limit.

The request profile also fixes head/line caps at 16384 bytes, 64 total headers,
16 trailers, and the canonical defaults for other wire/informational limits.
`Trailing::Reject` rejects surplus response bytes already received beyond the
framed message; it does not wait for later bytes to discover hypothetical
trailing data. There is no aggregate process/native heap cap.

The deadline starts before URL planning, body staging and TLS context creation.
Body operations check monotonic time before and after host calls. Canonical
drivers retain the same deadline through preparation, connection, transfer,
decoding and shutdown. A zero timeout permits no successful fetch. Body files,
NSS and OpenSSL trust/credential loading can still block inside a host call;
checking time afterward cannot cancel that call or bound its internal work.
The deadline is not a hard whole-command wall-time guarantee. Stdout and
diagnostics have finite write-call budgets and no clock deadline.

## File and response ownership

Body paths are raw native bytes, at most 4095 bytes, without NUL. Open uses
read-only, CLOEXEC, NONBLOCK and NOCTTY through FileOps. Symlinks may be followed,
but descriptor metadata must supply STATX_TYPE and identify a regular file.
No metadata size hint establishes EOF. Reads request at most 1024 bytes; at the
byte cap one extra byte distinguishes exact EOF from overflow. The body cap is
the smaller of `--max-body` and `--max-request`; framing can make the eventual
encoded request exceed its separate cap.

Body loading reserves close credit, requires at least four calls before open,
and closes the actual File once on every post-open path. Deadline/call failure
does not skip cleanup. The program retains a primary error if close also
fails, emits a secondary cleanup diagnostic, and never retries a retired
descriptor. Source Vec owners are released after transfer returns.

Output borrows the decoded body of the actual plain/TLS Response owner. The
program checks the whole body against `--max-output` before writing, keeps the
Response live through all partial writes/EINTR, and destroys it once afterward
on success or failure. It never destroys a borrowed HTTP descriptor copy.
Headers and argv stay owned until the entire operation and diagnostics finish;
URL/body/Context owners have explicit cleanup on every path.

## Exit and diagnostic contract

| Exit | Meaning |
| --- | --- |
| 0 | Valid exchange and complete stdout publication; any valid HTTP status is included |
| 2 | Invalid CLI, URL, method/header request or configuration |
| 3 | Operational body-file, DNS, TCP, TLS, response, timeout or resource-limit failure |
| 4 | Source allocation failure; native NSS allocation errors remain native resolution failures |
| 5 | Stdout failure/call limit or unsuccessful SIGPIPE-policy setup |

Stdout contains only decoded body bytes. No body is published on pre-output
failure or output-byte rejection. A write failure may leave the prefix already
accepted by stdout; there is no rollback. HTTP 4xx/5xx do not themselves change
exit status. SIGPIPE is ignored before argv acquisition; if policy setup fails,
exit 5 has no diagnostic because signal behavior is unconfirmed.

Other failures attempt one typed reason line on stderr, prefixed `fetch: `:
`invalid arguments`, `invalid URL`, `invalid request`, `invalid configuration`,
`limit exceeded`, `timeout`, `allocation failed`, `monotonic clock failed`,
`name resolution failed`, `connection failed`, `TLS operation failed`,
`certificate verification failed`, `invalid or incomplete HTTP response`,
`body file I/O failed`, or `output I/O or call limit failed`. Each ends with LF.
An observed secondary cleanup error adds `fetch: cleanup failed` plus LF.
Each line permits eight write attempts, including EINTR. Failure to deliver
stderr preserves the original nonzero exit class.

## Functional execution and remaining acceptance

Root compiled source
`6597a31f78f0814d958663db4a4f6501d385340ec3291854b82364634b9169cb`
with explicit ssl/crypto libraries. Compilation exits zero with an empty
`target/stdlib-work/fetch-url-app-qualified-option-retry.log`. The accepted
native executable SHA256 is
`0f6cb7dcc4b8536a4eaf0bb413602894f1a3fb9b531191ed2b9b606288b32092`;
its TLS facade is `06a6ebfa...`.

All three direct Python-driven groups pass on their first functional attempt
with frozen oracle `3a67791e...`. These are separate process receipts, not
passing runtime Rust libtests or merely successful type checking.

| Log under `target/stdlib-work/` | Accepted finite scope |
| --- | --- |
| `fetch-url-plain-first.log` | 24 cases: binary GET/POST file uploads, ordered/empty headers, literal `-` file, URL-derived exact Host/target/query/fragment behavior, status/empty/HEAD/chunked/close responses, exact/one-below limits, confirmed partial stdout, the original deadline and real closed-reader EPIPE |
| `fetch-url-preflight-first.log` | 33 cases: exact help/diagnostics/status, CLI/URL/request/configuration errors, TLS-only flags rejected on HTTP before body/trust opens, byte/call admission, and full traces with no network syscall |
| `fetch-url-tls-first.log` | Four cases: explicit CA with DNS/SNI and IP SAN/no-SNI, wrong CA rejection, and private-certificate rejection through controlled default trust paths |

The independent peers reuse existing HTTP listener lifecycle/wire helpers,
h11 request parsing and OpenSSL TLS/certificate fixtures. Every success checks
exact response bytes and empty stderr. Failures check exact status/reason;
pre-output failures publish no body. The one-call stdout case checks the real
1024-byte confirmed prefix. The closed-reader trace reaches actual EPIPE and
SIGPIPE-ignore policy. A partial response begins after 220ms and would finish
only after another 300ms; the one 400ms original deadline rejects it rather
than renewing on progress. This is a deadline check, not a throughput claim.

The [fixture guide](../tests/fixtures/extended/fetch_url/README.md) records full
oracle/driver hashes, exact commands and retained evidence directories. Seven
CPU oracle controls are distinct from these native cases. The registered Rust
driver is authored; these direct receipts do not establish its runtime tests.

Initial source `7f3b4ed8...` encountered short constructor-target ambiguity
before native execution. Explicit `core::option::Some`/`None` qualification and
the corresponding module import produce the accepted source. This changes no
CLI, algorithm, limits, help, error behavior or assertions; reversing only that
qualification recovers the original source. No compiler fix was required, and
no general generic-language failure follows from this admission attempt.

Remaining app gates include ordered fallback/no-replay, client credentials,
reached source allocation failures, body-file native failures and broader
output/cleanup faults. Functional traces establish only no-network/no-selected-
file preflights and EPIPE; they do not classify source allocations or prove
owner/fd cleanup. Live ACK or pre-exit resource evidence requires its own
verified source/native authority and reached-effect checks. Connected-library
and pure URL receipts stay separate from this application.

The finite accepted target is Linux x86_64/glibc/OpenSSL, using GPU-compiler
output executed on native CPU. This is not GPU-device execution or another
host-target claim. Root serializes compiler/native gates, with every command
under two minutes. The selected URL workflow and full standard/extended library
goal remain open until their remaining acceptance requirements are met.
