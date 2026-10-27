# Owned HTTP URL planning

`ext::http_url` turns one absolute HTTP or HTTPS URL into owned authority,
request-target and host-identity bytes. It uses the canonical
[`ext::uri`](extended-uri.md) parser and strict
[`core::net`](stdlib-net.md) IP parsers, then applies the client policy below.
Its host effects are limited to allocator backing; it performs no DNS lookup,
socket operation, TLS work or file operation.

`ext::host_name` supplies the shared, allocation-free DNS byte checks used by
this URL policy and the OpenSSL identity wrapper. It performs no host calls or
name resolution.

The pure APIs have executable evidence for GPU-compiler output executed on a
Linux x86_64 CPU. Their direct public contracts, 70-record semantic catalog on
two backing layouts, and 16-case ownership/failure campaign pass. These receipts
do not establish GPU-device execution or the connected URL-client workflow;
resolution, socket adoption, HTTP/TLS exchange and application acceptance remain
separate in the [URL-client plan](library-url-client-plan.md).

## Public URL API

```text
Scheme { Http, Https }
HostKind { Dns, Ipv4, Ipv6 }
Limits { url_bytes: i32, target_bytes: i32 }

default_limits() -> Limits
parse(input: View<u8>, limits: Limits) -> Result<Url, Error>

Url.borrow() -> &Url
Url.is_open() -> bool
Url.scheme() -> Option<Scheme>
Url.host_kind() -> Option<HostKind>
Url.host() -> Option<View<u8>>
Url.ip() -> Option<core::net::IpAddr>
Url.port() -> Option<u16>
Url.authority() -> Option<View<u8>>
Url.target() -> Option<View<u8>>
Url.destroy() -> bool
```

Defaults are 16,384 URL bytes and 8,192 target bytes. Each limit must be in
1..1,048,576 inclusive. They count encoded bytes, including the complete URL's
fragment for `url_bytes` and the generated leading slash/query marker for
`target_bytes`. A value exactly at a limit is admitted when all other checks
pass. Both limits and the complete input syntax/profile are checked before any
allocation.

Parsing checks negative logical start/length and an overflowing logical end.
As with `core::slice::View`, the caller must supply actual live backing elements
for the declared range; the module cannot prove the physical slice length.
Nonzero starts and actual signed strides are supported. Offsets in errors are
relative to the selected logical view, regardless of its start or stride.

## Accepted URL profile

The scheme is required and must be `http` or `https`, compared without ASCII
case. A nonempty authority and host are required. Userinfo is rejected even
when empty. Relative URL resolution remains a separate explicit operation in
[`ext::uri_resolve`](extended-uri-resolve.md).

Hosts use these rules:

- Strict existing IPv4 and bracketed IPv6 become numeric identities. IPv6 host
  getters exclude brackets, while authority getters retain them.
- DNS identities allow 1..253 bytes, nonempty labels of at most 63 bytes, ASCII
  letters/digits/hyphens, no leading or trailing label hyphen, no trailing dot,
  and at least one letter. Single-label names are allowed. Already encoded
  ASCII IDNA A-label spelling is accepted under these byte rules; this module
  does not perform IDNA conversion or validate the encoded Unicode name.
- Remaining classic numeric candidates are rejected before DNS classification:
  one through four dot-separated decimal or `0x`/`0X` hexadecimal parts. Examples
  include `127.1`, `0177.0.0.1`, `2130706433`, `0x7f000001` and `127.0x0.0.1`.
  The URL policy prevents libc from later interpreting such a DNS identity as
  a legacy numeric address. This is not an address-access policy.
- IPvFuture, IPv6 zone identifiers, percent-encoded hosts, raw non-ASCII bytes
  and backslashes are rejected. Some fail in the underlying URI grammar and
  therefore retain a typed URI diagnostic.

An absent port selects 80 for HTTP or 443 for HTTPS. A present port must contain
decimal digits and have a checked value in 1..65,535. Empty, zero and overflowing
ports fail. Explicit leading zeros and explicit default-port spelling remain
in the authority; the port getter returns the checked numeric value.

Scheme case does not change its enum value. Authority/host case, bracket/IP
spelling, percent-escape case, repeated slashes and literal dot segments remain
unchanged. No percent decoding, path normalization, DNS lookup, reverse lookup
or resolver-canonical-name substitution occurs.

## Authority, target and identity examples

| Input | Host / kind | Port | Authority | Target |
| --- | --- | --- | --- | --- |
| `http://Example.com` | `Example.com` / DNS | 80 | `Example.com` | `/` |
| `HTTPS://a?q=x#not-sent` | `a` / DNS | 443 | `a` | `/?q=x` |
| `http://a:00080/` | `a` / DNS | 80 | `a:00080` | `/` |
| `https://[::1]:00443` | `::1` / IPv6 | 443 | `[::1]:00443` | `/` |
| `http://a/a%2Fb/../c//?q=%25#fragment` | `a` / DNS | 80 | `a` | `/a%2Fb/../c//?q=%25` |
| `http://a/path?` | `a` / DNS | 80 | `a` | `/path?` |

The target consists of path and optional query. An empty path becomes `/`.
A present empty query still contributes `?`. A fragment must have valid URI
syntax, but it contributes no request-target bytes. The original URL host,
excluding brackets/port, supplies the reference identity. A DNS URL has no
`ip()` value; numeric URLs return their parsed address independently of the
preserved textual spelling.

## Ownership and failure

Successful parsing copies the complete URL and resulting target into owned
storage. Caller input can then be overwritten or released. Getters borrow
only that owned storage and expose no NUL terminator. Treat returned views as
read-only and keep the URL alive while using them; the language does not enforce
those rules. Borrowed views become invalid when the owner is destroyed.

Maintain one cleanup authority for each `Url`. A shallow record copy does not
create an independently owned clone. `borrow()` passes the existing owner by
reference. `destroy()` releases an active owner, returns true once, then returns
false on repetition. It makes `is_open()` false and every Option getter None,
including getters that previously returned numeric or enum metadata.

Construction failures release partial storage. The current implementation has
one vector for the complete URL and one for the target; the ownership test
derives and denies every source allocation actually reached by each baseline.
The API bounds its stored strings by their caps and actual vector capacities.
These limits are not a process-wide allocation cap or a promise about allocator
page rounding. The pure helper has no host-resource owner or automatic network
cleanup to perform.

## URL errors and precedence

```text
Error { kind: ErrorKind, offset: i32, syntax: Option<ext::uri::Error> }
ErrorKind {
    Bounds, InvalidLimits, Uri, Scheme, Authority, Userinfo, Host, Port,
    TargetLimit, AllocationFailed
}
```

`syntax` is Some only for `ErrorKind::Uri`, preserving the original typed URI
error. Other kinds have None. Offset -1 means no particular byte.

| Kind | Offset / meaning |
| --- | --- |
| `Bounds` | -1; invalid logical input range |
| `InvalidLimits` | -1; either cap outside the supported positive range |
| `Uri` | Original URI error offset; -1 for URI length/bounds errors |
| `Scheme` | 0; missing or unsupported scheme |
| `Authority` | Byte after the scheme's colon if authority is missing; host start if empty |
| `Userinfo` | The `@` byte, including empty userinfo |
| `Host` | Host start for unsupported/numeric-ambiguous host; offending DNS byte or end-state boundary; host start + 253 for an overlong DNS host |
| `Port` | Empty port's start/end, zero port's first digit, or first digit exceeding 65,535 |
| `TargetLimit` | Raw path start, including the empty-path boundary |
| `AllocationFailed` | -1; owned storage could not be reserved |

The order is logical bounds, limits, complete URI syntax, scheme, authority,
userinfo, host, port and target size, followed by allocation. URI syntax itself
performs a full ASCII/percent pass before structural checks. A malformed
fragment can therefore win over an earlier unsupported scheme or userinfo.
Nondecimal port bytes are URI errors; the later Port kind handles the numeric
client policy. No failure publishes a partial URL owner.

## Shared DNS helper

```text
ext::host_name::Error { Bounds, Empty, Limit, Nul(i32), Invalid(i32) }
check_dns(bytes: View<u8>, maximum_bytes: i32) -> Result<i32, Error>
```

Success is `Ok(0)`. The helper checks logical bounds first, then rejects a
nonpositive cap, empty input and a total length exceeding the selected cap.
The caller chooses that total cap; 253 is URL/default-TLS policy rather than a
hidden helper constant. It then applies the DNS label/ASCII/letter rules above.
It preserves input case and allocates nothing.

NUL and invalid-byte offsets point at the offending logical input byte. A
64th label byte points at that byte. Trailing dot/hyphen and the absence of any
letter are final-state failures at `bytes.length`; a bad label before a dot
points at the dot. Bounds, Empty and Limit have no indexed payload. The helper
does not itself reject every legacy numeric candidate; the URL layer performs
that separate classification first.

The OpenSSL wrapper maps these shared results to its existing public identity
errors. Its certificate verification, crypto, configured-cap behavior and native
TLS execution have their own guides and regression gates; these pure receipts
do not substitute for them.

## Executable evidence

The [fixture README](../tests/fixtures/extended/http_url/README.md) contains full
hashes, bounded commands and Rust registration filters. Current direct receipts
are:

| Gate | Receipt | Result |
| --- | --- | --- |
| Public contracts | `http-url-contracts-compile-first.log`, `http-url-contracts-native-first.{trace,log}` | Compile/native exit 0; empty output; trace only launch, eight allocations, eight matching releases and raw exit |
| Independent semantic catalog | `http-url-model-compile-first.log`, `http-url-model-native-first.log` | Compile/native exit 0; 70 records × two actual backing layouts in one process |
| Pre-exit ownership and reached OOM | `http-url-ownership-argument-retry.log`, `http-url-owners-first.log` | Compile/native exit 0; 16 group cases: two baselines, four reached allocation denials, ten allocation-free preflight rejections |

Executed `http_url.lani` is `b73ff204…`; current `24472542…` differs only in its
two leading comments, clarifying allocator host effects. Algorithm/API and the
executed-source receipt remain unchanged.

Logs are under `target/stdlib-work/`. The owner evidence directory is
`/tmp/lanius-http-url-owners-n__fsohc`. Each denied allocation matches its
baseline's exact source instruction address, syscall ordinal, arguments and
preceding allocation prefix. The existing full-width verifier separates current
`0x22` and older `0x62` runtime profiles and checks original requested release
sizes. Every failure and explicit destroy reaches a live pre-exit checkpoint
with no source or unexpected descriptor owner; process exit is not used as
evidence of cleanup. Full syscall traces reject unrelated host operations.

The first ownership compilation failed before native execution because the
fixture supplied `View<i64>` to `std::linux::call`; its argument is actually
`View<std::linux::Argument>`. Correcting that fixture call preserved every
runtime assertion and changed no library/compiler source. Contracts and model
passed on their first compilation/native runs. The Rust registrations have not
been run, and no repeated run is required merely to change receipt format.

CPU-only oracle controls passed separately: ten model checks and 27 owner
checks, including 17 reused ledger checks. Those counts are not Lanius runtime
cases. The catalog, owner campaign and pure traces make no maximum-default-size
performance claim, independent fixture-review claim, or connected HTTP/TLS
acceptance claim.
