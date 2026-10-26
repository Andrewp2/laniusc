# System hostname and service resolution

`std::resolve` copies system `getaddrinfo` results into owned
`core::net::SocketAddr` values. It uses native libc for hostname/service lookup;
there is no resolver engine, subprocess or bridge in the production module.

The first supported target is native C-linked Linux x86_64 with glibc, little
endian and the System V scalar/pointer ABI. The installed audit host is glibc
2.39. Header layout assertions and all four focused execution groups pass
through separate receipts: the GPU compiler produces a native-linked
executable, which runs on the CPU. This does not establish user GPU execution
or support for another libc layout.

## API

The source is [`stdlib/std/resolve.lani`](../stdlib/std/resolve.lani).

```lanius
pub enum Host { Name(View<u8>), Numeric(View<u8>), Loopback, Wildcard }
pub enum Service { Name(View<u8>), Port(u16), Unspecified }
pub enum Family { Any, Ipv4, Ipv6 }
pub enum Mapping { Disabled, Fallback, All }
pub struct Options {
    family: Family,
    kind: std::socket::Kind,
    addr_config: bool,
    mapping: Mapping
}
pub struct Limits { host_bytes: i32, service_bytes: i32, max_results: i32 }
pub fn default_options() -> Options;
pub fn default_limits() -> Limits;
pub fn lookup(host: Host, service: Service, options: Options, limits: Limits)
    -> Result<alloc::vec::Vec<core::net::SocketAddr>, Error>;
```

`View` and `Result` above abbreviate `core::slice::View` and
`core::result::Result`. Defaults are `Family::Any`, `Kind::Tcp`,
`addr_config=false`, `Mapping::Disabled`, with limits of 4,096 host bytes, 64
service bytes and 256 results. The three limits must be positive, with hard
maxima of 65,536, 4,096 and 4,096 respectively. Byte limits exclude a trailing
NUL. The service limit also applies to the decimal spelling of `Port`, including
the one byte spelling of port zero.

The returned `alloc::vec::Vec` has its ordinary one-active-owner contract.
Copies alias its backing allocation. Borrow it for `get`, `as_view` or
iteration, then call `destroy` after the last borrowed view. `SocketAddr` values
contain no nested owner or C pointer; a copied address remains valid after the
result vector is destroyed. There is no resolver handle to close.

## Explicit input and native policy

All input validation finishes before any allocation or native lookup. Host and
named-service views must be nonempty printable ASCII bytes, 33 through 126.
NUL has its own error; spaces, controls, DEL and non-ASCII bytes are rejected.
No trimming, case folding, IDNA conversion or DNS-label validation occurs.
Callers supply ASCII A-labels when those are needed.

| Input | Native argument and policy |
| --- | --- |
| `Host::Name(bytes)` | Copied NUL-terminated bytes; system hostname/NSS policy. Numeric inputs may also be recognized by libc. |
| `Host::Numeric(bytes)` | Same copying with `AI_NUMERICHOST`; native numeric grammar, including glibc legacy IPv4 spellings and scoped IPv6. This is not a promise of `core::net` parser equivalence. |
| `Host::Loopback` | NULL host, without `AI_PASSIVE`. |
| `Host::Wildcard` | NULL host, with `AI_PASSIVE`. |
| `Service::Name(bytes)` | Copied NUL-terminated service name under the requested TCP/UDP protocol. |
| `Service::Port(port)` | Strict `u16` converted to decimal, with `AI_NUMERICSERV`. Ports zero and 65,535 are valid. |
| `Service::Unspecified` | NULL service; results must carry port zero on this glibc profile. A nonzero returned port is rejected. |

The two explicit NULL-host forms cannot be paired with `Unspecified`; use
`Port(0)` to request loopback or wildcard addresses with port zero. Named or
numeric hosts may use `Unspecified` for address-only lookup.

`Service::Name` rejects all-digit strings and strings beginning with `+` or
`-`; callers must parse numeric ports into `Port(u16)`. This prevents libc's
numeric parsing from wrapping an out-of-range port. Exact `*` is rejected in
both host text modes and named services: glibc otherwise rewrites these strings
to NULL before applying numeric flags. These rejections preserve the explicit
NULL variants. The relevant implementation is in
[glibc's `getaddrinfo` source](https://raw.githubusercontent.com/bminor/glibc/release/2.39/master/nss/getaddrinfo.c).

Every call supplies an explicitly initialized hints block. No NULL-hints
defaults are inherited. `Family::Any`, `Ipv4` and `Ipv6` select
`AF_UNSPEC=0`, `AF_INET=2` and `AF_INET6=10`. `Kind::Tcp` fixes both
`SOCK_STREAM=1` and `IPPROTO_TCP=6`; `Kind::Udp` fixes `SOCK_DGRAM=2` and
`IPPROTO_UDP=17`. There is no raw-socket or arbitrary protocol mode.

`addr_config=true` requests `AI_ADDRCONFIG=32`. It can omit an address family
according to current interface configuration; loopback alone need not count.
Non-disabled mapping requires `Family::Ipv6`: `Fallback` selects
`AI_V4MAPPED=8`, and `All` selects `AI_V4MAPPED|AI_ALL=24`. Other family/mapping
pairs fail locally. Canonical-name, IDN and arbitrary flag modes are absent.
The flag meanings follow the
[IPv6 socket interface specification](https://www.rfc-editor.org/rfc/rfc3493.html#section-6.1).

## Results and atomic failure

Results retain native list order and duplicates, including IPv4-mapped IPv6
addresses and IPv6 scope IDs. The module adds no sorting, deduplication,
connection attempt, address-family preference or Happy Eyeballs policy.
Ordering and membership can change with NSS, hosts/services files, resolver
configuration, interface state and libc policy. In particular, `localhost`
does not promise both families.

Every admitted native node produces exactly one address. An unknown family,
socket type or protocol, a family inconsistent with the request, a wrong
address length, a NULL address, or a sockaddr family mismatch fails the whole
call. IPv6 flow information must be zero because `core::net::SocketAddrV6`
does not represent it; nonzero flow information is rejected. Returned
`ai_flags` are not inspected, and `ai_canonname` is never dereferenced.

The first pass validates/counts at most `max_results` nodes. A further non-NULL
next pointer yields `ResultLimit`; no truncated vector is published. The
module then reserves one exact result vector and copies the validated native
addresses in a second pass. Errors release the complete native list and any
partially initialized vector. Successful return also releases the native list;
only independent value copies remain.

These checks assume a valid libc-owned, acyclic, physically backed list.
Logical metadata checks cannot make forged native pointers, concurrent native
mutation or a corrupted libc allocator safe.

## Native layout and ownership boundary

The actual foreign declarations are scalar/pointer-only:

```c
int getaddrinfo(const char *node, const char *service,
                const struct addrinfo *hints, struct addrinfo **result);
void freeaddrinfo(struct addrinfo *result);
int *__errno_location(void); /* glibc */
```

Their Lanius forms take four `ptr` parameters and return `i32`, take one `ptr`
and return void, and return `ptr`, respectively. No Lanius record, enum, array
or slice is passed as a C aggregate. The
[native C contract](library-native-c.md) does not inspect C headers or prove
these memory layouts.

The selected header contract is:

| C type | Size / alignment | Byte offsets |
| --- | --- | --- |
| `struct addrinfo` | 48 / 8 | signed 32-bit flags/family/type/protocol at 0/4/8/12; unsigned 32-bit `socklen_t` at 16; pointer addr/canon/next at 24/32/40 |
| `struct sockaddr_in` | 16 / 4 | host-order 16-bit family at 0; network-order port at 2; four address octets at 4 |
| `struct sockaddr_in6` | 28 / 4 | family at 0; network-order port at 2; flow information at 4; sixteen address octets at 8; host-order unsigned scope ID at 24 |

Native pointer size is eight bytes, C `int` and `socklen_t` are four, and this
profile is little endian. A 56-byte, eight-byte-aligned allocation holds zeroed
hints followed by an eight-byte result cell. Packed `i32` views initialize the
four input integers; all other hints bytes and output bytes stay zero. Pointer
fields are loaded individually through one-element raw pointer views, avoiding
the descending stride of multi-element Lanius pointer storage. Input byte
views are copied element by element into packed byte allocations, so stack,
packed, offset and vector layouts do not need a C-compatible stride.

Only status zero transfers a native list to the wrapper. On native failure,
the output cell is ignored and libc retains responsibility for its partial
allocations. On success, `freeaddrinfo` receives the original list head exactly
once on every exit; individual nodes, addresses and canonical names are never
freed separately. The native library's list lifetime rules are specified by
[POSIX `getaddrinfo`/`freeaddrinfo`](https://pubs.opengroup.org/onlinepubs/009619199/getad.htm).

## Errors and limits of blocking lookup

```lanius
pub enum Phase { Input, Host, Service, Lookup, Results }
pub enum Cause {
    Bounds, InvalidLimits, InvalidOptions, Empty, Nul, NonAscii,
    InvalidHost, InvalidService, MissingInput, AllocationFailed, Native,
    ResultLimit, UnsupportedResult, InvalidResult
}
pub struct Error {
    cause: Cause, phase: Phase, code: i32, system: i32, index: i32
}
```

`Bounds` covers invalid view arithmetic or a byte cap exceeded. `index` is
relative to the supplied host/service bytes or the native result ordinal;
`-1` means the error has no particular position. A result limit reports the
first omitted ordinal, equal to `max_results`. Local errors have zero `code`
and `system`. Native errors keep the exact nonzero EAI result in `code`.
Native `EAI_MEMORY` remains a native error, distinct from a wrapper staging or
vector `AllocationFailed`.

The wrapper obtains the thread's errno cell before the lookup, resets it to
zero, and reads it immediately after `getaddrinfo` returns, before cleanup or
any other libc call. Only `EAI_SYSTEM=-11` exposes that saved value in `system`;
success and all other EAI codes ignore incidental errno. No borrowed diagnostic
string or locale-dependent `gai_strerror` call is needed. Native EAI and errno
values remain those of this glibc profile.

Each call performs at most one `getaddrinfo`, with no automatic retry, poll or
deadline loop. System lookup is synchronous and can block while NSS/DNS or
service providers run. A nonblocking socket, an application call counter, or a
deadline checked before/after this operation cannot interrupt it. Numeric host
mode suppresses host name lookup; a named service can still consult service
providers. There is no DNS authentication or TLS identity verification here.

The module bounds its copied input bytes, result allocation and explicit
native-list visits. It does not bound libc/NSS internal memory, network work,
retries, threads, elapsed time or the full-list work of `freeaddrinfo`, including
cleanup after an over-limit native result. Native modules can use process
configuration and caches. Callers must not concurrently destroy or mutate
borrowed input backing. Foreign callbacks, Lanius foreign-thread entry,
asynchronous cancellation, other libc layouts, Wasm and user GPU execution are
outside this first profile.

## Execution evidence

The first admission control compiles with the current GPU compiler and
`--native-link`, then exits zero as a native executable. It covers numeric
IPv4 with port 8,080, explicit NULL-host loopback with port zero, wildcard with
port 80, both-NULL input rejection, and basic address count/port checks. Its
receipts are `target/stdlib-work/resolve-first-admission.log` and
`target/stdlib-work/resolve-first-admission-native.log`; successful operations
produce no output. The source is `target/stdlib-work/resolve-admission.lani`.

This small control establishes initial compilation/linking and those examples,
not the full ownership/error/limits contract.

The [focused execution campaign](stdlib-resolve-testing.md) now passes all four
groups through separate receipts:

- An **80-case** numeric, null-host and local named-service matrix matches an
  independent header-typed libc client, including order, flags and scoped
  addresses. It passed in **6.12 seconds**.
- Local admission and layout coverage passed in the expanded invocation:
  **177 rejections** across three layouts, **59** traced rejection controls
  with no source allocation, and **15** accepted limit/ignored-view cases.
- **97 synthetic native-list/error cases** passed in that invocation, including
  duplicates, full-width scopes, malformed metadata, errno separation,
  non-owned error output, exact/over-limit lists and physically backed cycles.
- The corrected allocation campaign passed in **6.04 seconds**. Each of the
  four reached source allocations (97, 17, 56 and 160 bytes in the fixture)
  fails once with exact mapping cleanup, the appropriate native-head release
  and a successful retry over unchanged input.

The expanded invocation took **9.68 seconds** and first stopped its allocation
group at an overly narrow test classifier, before injection. The retry checks
the actual appended allocator thunks as well as sized source functions; this
was a harness correction with production unchanged. The testing guide records
each receipt and its scope. The real named cases require locally proven NSS
records; they do not depend on external DNS. Native-shape faults use a
test-only observer, not a production resolver implementation.

The audit also compiles the installed `netdb.h`, `netinet/in.h` and glibc socket
headers with C11 static assertions for the sizes, alignments, offsets and
constants above. Native list and source-mapping ledgers are checked separately.
These finite tests establish the documented profile, not every NSS provider,
native failure or production lookup deadline. No compiler changes or
production C shim are required.
