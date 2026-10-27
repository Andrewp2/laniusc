# URL fetch application verification

Status: all three direct functional groups pass on the source/ELF identities
below. Resource-owner/allocation-failure acceptance is separate and pending;
these are not Rust-libtest runtime receipts. The full library goal remains open.

## Scope and independent peers

`oracle.py` invokes the actual `sample_programs/library/fetch.lani` executable.
It imports the existing fetch-many listener/thread lifecycle and fixed/chunked
response constructors, and the existing OpenSSL MemoryBIO peer and certificate
generator. A small Plain subclass changes only per-connection request handling
so POST and binary uploads are admitted. h11 independently parses each request;
there is no copied Lanius request parser or second transport implementation.
Certificates, signatures, TLS records and verification remain in OpenSSL.

The functional groups are finite and separate:

| Group | Accepted process cases | Checked behavior |
| --- | ---: | --- |
| `plain` | 24 | Exact Host/target/query/fragment handling and explicit port spelling; binary GET/POST file data and ordered/empty custom headers; default GET for a body file, literal `-` filename rather than stdin; empty/status/HEAD/chunked/close responses; exact/one-below caps; partial stdout progress; original deadline; actual closed-reader EPIPE |
| `preflight` | 33 | Exact help and status/reason diagnostics; CLI/URL/request/configuration failures; TLS-only flag rejection on HTTP before body/trust opens; byte/call admission; full traces contain no network syscall |
| `tls` | 4 | Explicit CA success for DNS/SNI and IP SAN/no-SNI, wrong CA rejection, and default trust-path rejection of the private certificate under controlled OpenSSL trust environment |

Every successful exchange checks the complete stdout body and empty stderr.
Failures check the exact exit class and typed reason line; pre-output failures
publish no bytes. The one-call stdout limit deliberately expects its real
1024-byte confirmed prefix. Closed-reader EPIPE uses a real pipe with no reader
and a full syscall trace, requiring the actual failing fd-1 write and confirmed
SIGPIPE-ignore policy. It is not a synthetic successful/failed write count.

The deadline peer sends a successful partial response after 220ms, then cannot
complete until another 300ms elapses. The app receives one 400ms original budget;
renewing it after progress would incorrectly allow success. The test requires
the first peer progress and timeout without body publication. Time is used for
this explicit deadline contract, not a throughput threshold.

Full traces in this increment establish only preflight network absence,
selected body/trust-file absence, and real EPIPE. They do **not** establish
source allocation/fd ownership cleanup, allocation-failure coverage or live
ACK checkpoints. Native loader/NSS/OpenSSL work is not classified with a legacy
MAP_32BIT-only heuristic. Resource acceptance needs the shared verified native
source-allocation helper and its own reached/effect checks.

## Commands and evidence

Root alone compiles/runs Lanius and native peers. Each Rust oracle invocation
has a 70-second parent bound; each app child has a six-second bound. Every root
command remains below two minutes. Direct retained-ELF invocation is:

```sh
python3 -B tests/fixtures/extended/fetch_url/oracle.py plain FETCH_ELF
python3 -B tests/fixtures/extended/fetch_url/oracle.py preflight FETCH_ELF
python3 -B tests/fixtures/extended/fetch_url/oracle.py tls FETCH_ELF
```

Registered filters in `tests/extended_fetch_url_execution.rs`:

```text
url_fetch_plain_binary_body_headers_caps_deadline_and_closed_reader_execute
url_fetch_cli_url_request_and_configuration_fail_before_network
url_fetch_verified_dns_ip_san_and_explicit_default_ca_paths_execute
```

The driver compiles only the real URL app with explicit native ssl/crypto
libraries, validates its native-linked ELF through the existing verifier and
checks those dynamic dependencies. Compilation, driver build and native oracle
receipts must be recorded separately. No new passing Rust-libtest receipt is
inferred from direct Python execution.

Each invocation retains a fresh `/tmp/fetch-url-GROUP-*` evidence directory
with exact commands, stdout/stderr and applicable full traces. Success summary
contains its finite case count and directory. Failure retains the same files;
assertion failures and peer assertion errors cannot count as accepted cases.

CPU-only oracle checks, executed by the fixture author:

```sh
python3 -B tests/fixtures/extended/fetch_url/oracle.py controls
```

The seven CPU assertions/mutations check the help byte count, network trace
selector and independent request authority/target/body/ordered-header checks.
They do not start the app, servers, OpenSSL, a compiler or a GPU. The app's
contract is in [the application guide](../../../../docs/extended-fetch-url.md).

## Accepted direct functional receipts

Root compiled current application source
`6597a31f78f0814d958663db4a4f6501d385340ec3291854b82364634b9169cb`
with explicit ssl/crypto libraries: exit zero and an empty
`target/stdlib-work/fetch-url-app-qualified-option-retry.log`. The accepted
native ELF SHA256 is
`0f6cb7dcc4b8536a4eaf0bb413602894f1a3fb9b531191ed2b9b606288b32092`.
The linked TLS facade source is
`06a6ebfafcbc96e9ca947180704ca9788bcff30ff4ad880e81d8f8210662f751`.

| Direct invocation receipt under `target/stdlib-work/` | Result | Retained evidence |
| --- | --- | --- |
| `fetch-url-plain-first.log` | 24 cases pass on the first functional attempt | `/tmp/fetch-url-plain-t8wuihn6` |
| `fetch-url-preflight-first.log` | 33 cases pass on the first functional attempt | `/tmp/fetch-url-preflight-1ham0y8m` |
| `fetch-url-tls-first.log` | Four cases pass on the first functional attempt | `/tmp/fetch-url-tls-b833uwg2` |

Frozen oracle SHA256:
`3a67791eb16dcf00fb97822fee7e6827b4a62943a30813c1977a60c85672b041`.
The oracle and all assertions stayed unchanged through these three gates.
Registered Rust driver SHA256:
`438e4f91eb52b97d2103f28191712ddfd81835d665a9e93c498d12cbf2f39910`;
no runtime Rust-test pass follows from the direct Python receipts.

Initial source `7f3b4ed8...` failed constructor-target admission before native
functional execution. Fully qualifying `core::option::Some`/`None` and using
the module import produced the accepted `6597a31f...` source. Reversing only
that qualification recovers the initial source; CLI, algorithms, diagnostics,
limits and assertions are unchanged. No compiler change was made, and this
source-level import/constructor ambiguity is not evidence that general generic
execution fails.

The finite accepted target is native Linux x86_64/glibc/OpenSSL, with Lanius
GPU-compiler output executed on CPU. No user-program GPU or other host/shell
support follows. Ordered multi-address fallback/no-replay, client credentials,
source OOM, body-file native faults and exhaustive output/cleanup failure
coverage need separate acceptance. No source-owner or fd-cleanup proof is
inferred from functional success or from the narrow full traces above.
