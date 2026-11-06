# OpenSSL WebSocket handshake acceptance

`ext::openssl_websocket::accept_into(key, destination)` computes the
`Sec-WebSocket-Accept` header value through OpenSSL 3. OpenSSL performs the
SHA-1 operation; Lanius validates and stages bytes, encodes the result and
reports errors. SHA-1 appears only in this RFC 6455 handshake operation.

The checked native profile executes this helper on Linux x86_64/glibc with
OpenSSL 3. Direct executable checks passed 310 input/layout cases and 24
injected-case runs. These checks establish no GPU runtime support or formal
proof.

## Contract

Both arguments are `core::slice::View<u8>`. The result is
`Result<i32, Error>`: success returns `28` and writes exactly the first 28
logical destination bytes, without a NUL terminator. Extra destination bytes
stay unchanged. Every returned error leaves all caller output unchanged.

The key must contain exactly 24 canonical, padded standard Base64 bytes that
decode to 16 bytes. HTTP parsing must remove surrounding field whitespace
before this call. Internal whitespace, URL-safe Base64, omitted padding and
nonzero unused padding bits are rejected. The original encoded key, rather
than its decoded bytes, enters the digest.

Checks run in this order:

1. Both views require nonnegative starts and lengths and an `i32`-representable
   start plus length; otherwise return `Bounds`.
2. Destination capacity must be at least 28; otherwise return `Capacity`.
3. Key length and canonical Base64 validation must pass; otherwise return `Key`.
4. OpenSSL must return success; otherwise return `OpenSsl(code)`.
5. Its reported digest size must be 20; otherwise return `UnexpectedSize(actual)`.

Views require valid backing and lifetimes. Logical checks cannot establish
whether memory is physically backed; invalid backing can trap during indexing.
Signed byte strides and overlapping input/output are supported: the function
snapshots the key into packed stack storage before writing caller output.

## Native boundary and allocation

The function appends the 36-byte RFC GUID to the 24-byte snapshot and calls
`EVP_Q_digest` with the explicitly terminated algorithm name `SHA1`. The
library context and property query are null, so the default OpenSSL provider
and property policy apply. A provider policy that disables SHA-1 can fail the
operation.

The digest has a separate 64-byte stack buffer, matching `EVP_MAX_MD_SIZE`
in the OpenSSL 3 profile. A separate aligned eight-byte cell receives C
`size_t`; the function requires 20 before Base64 encoding into 28 scratch
bytes. The final copy commits caller output. No Lanius heap allocation occurs.
OpenSSL may allocate internally; the function retains no native resource.

The function clears the calling thread's OpenSSL error queue immediately
before the digest call. A failed call captures the earliest queued code and
clears the rest. That code may be zero if no diagnostic was queued. Preflight
errors make no OpenSSL calls and leave its error queue alone. Callers must not
keep outstanding raw OpenSSL diagnostics across a call that reaches the digest.

The verified native profile is [Linux x86_64/glibc with the checked C ABI and
CRT startup](library-native-c.md): pointers, C `size_t` and `unsigned long`
are 64 bits; C `int` is 32 bits. Build with
`--native-link --native-library crypto`; `libssl` is not required. The raw
declarations expose an unchecked FFI boundary for direct callers.

## Executable checks

The native producer
[`accept_probe.lani`](../tests/fixtures/extended/websocket_upgrade/accept_probe.lani)
compiled and executed against real OpenSSL. Its
[oracle](../tests/fixtures/extended/websocket_upgrade/oracle.py) checked 310
cases using independent CPython SHA-1 and Base64 calculations. Cases include
the RFC sample, deterministic nonces covering every byte value, native
negative-stride and packed byte storage, nonzero offsets, overlapping input
and output, extra output capacity, malformed keys, short capacity and invalid
logical bounds. Complete source and destination snapshots check output guards
and preservation on errors.

A test-only native interposer ran 24 additional cases across provider failure,
reported digest size 19 and reported size `0x100000014`. The last case checks
that the seventh C argument carries a valid pointer to a full-width
`[u64;1]` output cell: truncating its value to 32 bits would incorrectly turn
it into the accepted size 20. These runs also check preflight rejection and
unchanged output after native errors. The interposer supplies no cryptography.

Retained receipts under `target/stdlib-work/`:

| Receipt | Result |
| --- | --- |
| `websocket-upgrade-accept-compile-first.log` | Native producer compiled; exit 0, empty log. |
| `websocket-upgrade-fault-build-first.log` | Test interposer built; exit 0, empty log. |
| `websocket-upgrade-accept-native-first.log` | Exit 0; 310 cases, two layouts, overlap; 24 injected cases with atomic output. |
| `websocket-upgrade-driver-build-first.log` | Both upgrade integration drivers built in 2.09 s; no Rust test-run claim. |

The executed helper SHA-256 was
`2c0baac560e6ec54b7379730cde75b289e20fe0f67cfd48d03b7d8a377738ecd`;
producer SHA-256 was
`3781b81a033a4ba0c390bd69505703f9a62c11177422b8613afee7eeae9a1579`.
The native ELF SHA-256 was
`d321f8982056572733564cdc8d9d723eb2f8ef50077986a99fb303cf2024559d`.
The [upgrade program](extended-websocket-upgrade-program.md) provides a real
consumer of the helper. These finite checks do not establish every OpenSSL
provider policy or resource-failure condition.

## Current caller migration

The URL-based [client](extended-websocket-client.md) and event-loop
[service](extended-websocket-service.md) now use this checked helper for
Accept. Both expose `Accept(openssl_websocket::Error)` for digest failures.
The client releases staged buffers and destroys its connection before any
HTTP request write. The service retains the HTTP slot, writes no 101 and
publishes no session; its echo sample can answer 500 on that connection.

The plain service now links `libcrypto`. The client already links `libssl`
and `libcrypto` through its HTTP-agent transport. The portable
`ext::websocket` request/response and frame code imports no native crypto;
it takes externally computed Accept values. The handwritten `ext::sha1`
module and `websocket::accept_into` entry point have been removed without
compatibility aliases.

The helper receipts above and the client/service guides' historical oracle
groups retain their original source scope. The following separate reruns
exercise the current migration on Linux x86_64/glibc with OpenSSL 3.
Receipt files are under `target/stdlib-work/` and share the prefix
`websocket-native-crypto-`.

| Receipt suffix | Current result |
| --- | --- |
| `upgrade.log` | 2 Rust tests passed in 11.29 s: 310 real-OpenSSL input/layout/overlap cases, 24 injected provider/size cases with atomic output, and portable response validation/encoding contracts. |
| `wire.log` | 2 Rust tests passed in 14.91 s: request/frame/fragment/control/close/limit contracts and allocation-failure staging/state checks. |
| `client-ws.log` | 1 Rust test passed in 17.17 s: the existing 50-case plain-client group. |
| `client-remaining.log` | 3 Rust tests passed in 18.75 s: the existing 52-case TLS and 24-case deflate groups, plus three injected `ws_cat` failures reporting `error crypto` with no HTTP request bytes sent. |
| `client-errors-final.log` | 1 Rust test passed in 21.91 s: three exact provider/size/full-width-size errors, zero HTTP request bytes followed by EOF, same-process real-provider recovery, and balanced source owners both around the failed call before retry and across the complete trace. |
| `service-errors.log` | 1 Rust test passed in 8.57 s: four Hub processes, including a real-provider control and six exact typed failures across provider rejection, size 19 and full-width size `0x100000014`; repeated rejection preserves the same HTTP connection and the single session slot, followed by a real-provider upgrade and frame exchange. |
| `service-apps.log` | 2 Rust tests passed in 9.87 s: the existing 89-case echo oracle and three sample processes with six injected digest failures, exact HTTP 500 responses and reuse of each HTTP connection. |

The connected fault tests reuse the existing test-only interposer, which
implements no cryptography. The typed client and service checks distinguish
provider error `OpenSsl(0x40000123)` from `UnexpectedSize(19)` and
`UnexpectedSize(0x100000014)`.

The client ownership check covers source allocations; native OpenSSL and
CRT mappings are outside that claim. Its initial `client-errors.log` stopped
in an outdated host allocation-site recognizer. The final gate uses the
shared current-runtime verifier with its terminal-instruction boundary
corrected; 14 host controls and 10 verifier-authority tests pass. No
production or compiler repair was required. These finite groups do not
establish broader provider policies or allocation-failure coverage beyond
their stated cases.

## Protocol scope

This function computes a handshake field value. HTTP request/response checks,
nonce generation, origin policy, subprotocol negotiation, sockets, TLS and
WebSocket framing belong to their respective modules and callers. This value
does not authenticate a peer or supply connection integrity or confidentiality.

The operation follows RFC 6455 [client validation](https://www.rfc-editor.org/rfc/rfc6455.html#section-4.1)
and [server acceptance](https://www.rfc-editor.org/rfc/rfc6455.html#section-4.2.2).
Its [SHA-1 discussion](https://www.rfc-editor.org/rfc/rfc6455.html#section-10.8)
explains the protocol's use. The OpenSSL [EVP digest interface](https://docs.openssl.org/3.0/man3/EVP_DigestInit/)
defines the one-shot call, maximum output and return status.
