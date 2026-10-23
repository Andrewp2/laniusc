# Numeric network values

`core::net` implements portable IPv4/IPv6 addresses, numeric scoped and socket
addresses, and CIDR prefixes in Lanius. Parsing and formatting execute on
x86_64 Linux without allocation. Every address is an owned scalar value:
IPv4 retains 32 bits and IPv6 retains all 128 bits. Values retain no input
buffer, string, pointer or mutable byte backing.

This module does not resolve hostnames, interface names or services, open
sockets, or define a native `sockaddr` layout. `std::net` host-service
availability remains a separate contract.

## Types and construction

| Type | Representation |
| --- | --- |
| `Ipv4Addr` | `bits: u32`, with the first wire octet in the most significant bits. |
| `Ipv6Addr` | `high: u64, low: u64`, in network significance order. |
| `IpAddr` | `V4(Ipv4Addr)` or `V6(Ipv6Addr)`. |
| `ScopedIpv6Addr` | `address: Ipv6Addr, scope: u32`. |
| `SocketAddrV4` | `address: Ipv4Addr, port: u16`. |
| `SocketAddrV6` | `address: Ipv6Addr, port: u16, scope: u32`. |
| `SocketAddr` | `V4(SocketAddrV4)` or `V6(SocketAddrV6)`. |
| `Ipv4Net`, `Ipv6Net` | Canonical `address` and `prefix: u8`. |
| `IpNet` | `V4(Ipv4Net)` or `V6(Ipv6Net)`. |

`ipv4(a,b,c,d)` takes four `u8` octets. `ipv6(a,b,c,d,e,f,g,h)` takes eight
`u16` segments. Scalar record construction also preserves every input bit;
there is no integer narrowing, primitive-only representation fallback or
implicit mapping between address families.

`ipv4_from_octets(view)` and `ipv6_from_octets(view)` require exactly 4 or 16
elements and return `Result<Address,Error>`. `write_octets(output)` writes
wire bytes to a caller view and returns the count. IPv4 provides `to_bits()`;
both address types provide `octet(index) -> Option<u8>`, and IPv6 provides
`segment(index) -> Option<u16>`. Invalid element indices return `None`.

IPv4 `to_ipv6_mapped()` explicitly constructs `::ffff:a.b.c.d`.
IPv6 `to_ipv4_mapped()` returns `Some` only for that exact mapped prefix.
Mapped IPv6 values remain IPv6 for equality, ordering and containment.

## Parsing

Every parser takes a counted `core::slice::View<u8>` and returns
`core::result::Result<Value,Error>`:

| Function | Accepted input |
| --- | --- |
| `parse_ipv4` | Exactly four decimal octets, each 0–255. |
| `parse_ipv6` | Eight hexadecimal segments, optionally compressed once with `::`; a final dotted IPv4 tail occupies two segments. |
| `parse_ip` | Bare IPv4 or bare IPv6. |
| `parse_scoped_ipv6` | Bare IPv6, optionally followed by `%` and a decimal `u32` zone. |
| `parse_socket` | `IPv4:port` or `[IPv6%scope]:port`; scope is optional. |
| `parse_prefix` | `IPv4/prefix` or `IPv6/prefix`, with host bits already clear. |
| `parse_prefix_truncate` | The same CIDR grammar, explicitly clearing host bits. |

IPv4 follows RFC 3986's decimal-octet grammar: an octet is one digit, or a
nonzero-leading number of at most three digits. Leading zeros, hexadecimal,
octal, shortened addresses, signs and integer-address forms fail. The same
grammar applies to an IPv6 dotted tail. IPv6 accepts uppercase/lowercase hex
and compression of one or more zero segments. Multiple `::`, zero-length
ordinary segments and excess/missing segments fail.

No parser trims whitespace, accepts a NUL terminator, resolves a hostname or
reads beyond the selected range. Bare address parsers reject brackets,
ports, CIDR suffixes and zones. Numeric zone, port and prefix fields accept
leading decimal zeros and normalize them when formatted. Ports require at
least one digit and fit `u16`. Zones fit `u32`; named zones require host
resolution and fail here. Zone zero is the default and is omitted in output.
Numeric zones are carried as metadata; the module does not establish that a
zone exists or is meaningful for an address on this host.

Socket syntax is a numeric display syntax, with raw `%` zone delimiters.
It does not interpret URI percent escapes or IPvFuture. URI authority
handling should use the URI library's separate rules.

Text lengths are bounded: IPv4 is 7–15 bytes, IPv6 is 2–45 bytes, scoped
IPv6 is at most 56 bytes, a socket is at most 64 bytes, and a CIDR is at
most 49 bytes. Leading decimal zeros in zone/port/prefix fields are accepted
only within those total text limits; padding is not unbounded.

## Formatting and failure behavior

Every value type has `format_into(output) -> Result<i32,Error>`. It writes
ASCII bytes without a NUL terminator and returns the written count.
IPv4 output is decimal. IPv6 follows RFC 5952: lowercase, no segment-leading
zeros, the longest run of at least two zero segments compressed, with the
leftmost run winning ties. Mapped IPv6 uses `::ffff:a.b.c.d`; other IPv6
addresses use hexadecimal segments. Socket IPv6 is bracketed, numeric fields
use minimal decimal digits, and CIDRs include their prefix length.

An 80-byte output view fits every supported formatted value. Formatting
stages bytes on a fixed-size stack buffer and checks bounds/capacity before
copying. Every formatting or wire-output failure leaves the entire caller
view unchanged. Success leaves elements beyond the written count unchanged.
Native strided views and nonzero offsets work in both directions.

`Bounds` means negative start/count or overflow of a logical end. Physical
backing and view lifetime remain caller obligations; the compiler does not
enforce them. Value parsing copies the address, so its source can be reused
after the call. Formatting depends only on the owned value.

Errors are `Bounds`, `InvalidLength`, `InvalidIpv4`, `InvalidIpv6`,
`InvalidScope`, `InvalidPort`, `InvalidSocket`, `InvalidPrefix`,
`HostBitsSet` and `OutputTooSmall`. `InvalidLength` distinguishes incorrect
wire-octet counts. Grammar/range failures return errors, with no host fallback.

## CIDR operations

`ipv4_net(address,prefix: i32)` and `ipv6_net(address,prefix: i32)` reject
out-of-range prefixes and nonzero host bits. Their `_truncate` counterparts
explicitly normalize an address. Prefix lengths span 0–32 and 0–128,
including endpoints without oversized shifts.

Both concrete network types provide `network()`, `last()`, `netmask()`,
`hostmask()`, `prefix_len()`, `contains(address)`, `contains_network(other)`
and `overlaps(other)`. `IpNet` provides the same operations with `IpAddr` and
`IpNet` results/arguments. `network()` and `last()` are inclusive numeric
endpoints. They do not enumerate usable hosts or reserve broadcast/router
addresses. Cross-family containment and overlap are false, including mapped
IPv6 versus IPv4. Containing one endpoint is insufficient to contain a wider
network: `contains_network` also checks prefix length.

Network records must come from validated constructors/parsers and retain
their invariant: prefix in range and address with host bits cleared.
Manually forging or mutating these public record fields invalidates that
contract. Query methods assume the invariant; they do not validate a forged
record on every call. Ordinary address bit records have no corresponding
invalid bit pattern.

## Comparison, hashing and predicates

All ten value types implement `core::cmp::Eq<T>`, `core::cmp::Ord<T>` and
`core::hash::Hash<T>`. Address order is unsigned numeric order over all bits;
IPv4 sorts before IPv6 in sum types. Scoped addresses compare address then
scope. Socket values compare address, port, then IPv6 scope. Prefixes compare
canonical network address then prefix length. Exported `compare_*` and
`hash_*` functions provide the same operations directly.

Hashes use noncryptographic FNV-1a with all address bytes in wire order and
the relevant family/prefix/port/scope fields. Equality implies equal hashes;
collisions remain possible. These are real structured generic keys:
`HashMap<IpAddr,i32>` and generic sorting execute in the tests.

IPv4 and IPv6 expose `is_unspecified`, `is_loopback`, `is_multicast`,
`is_link_local` and `is_private`; IPv4 also exposes `is_broadcast`.
These are fixed bit predicates, without a changing global-reachability
registry. IPv4 private means `10/8`, `172.16/12` or `192.168/16`;
IPv6 private means `fc00::/7`. Link-local means IPv4 `169.254/16` or
IPv6 `fe80::/10`. IPv4 loopback covers `127/8`; IPv6 loopback is `::1`.
They make no claim that an address is reachable or suitable for a policy.

## Executable evidence

`tests/stdlib_net_execution.rs` drives native Lanius programs:

- More than 10000 Python `ipaddress` reference cases check exact canonical
  text, all wire bytes, hashes, scope/port values and fixed predicates.
  Every CIDR width is exercised with independently generated addresses and
  Python network/last/netmask/hostmask values. Mixed IPv6 forms are also
  compared with `socket.inet_pton`.
- Rejection covers legacy IPv4 forms, binary suffixes, malformed compressed
  IPv6, named/overflowing zones, missing/overflowing ports, host bits and
  invalid prefixes. Strided/offset wire views and atomic capacity failure
  preserve output guards.
- Every prefix length checks parent/child containment, overlap and an
  address outside the prefix. Unsigned comparisons distinguish changes in
  either 64-bit IPv6 half.
- A generic map inserts/looks up 4096 mixed-family values, removes half and
  destroys its storage; generic address sorting also executes.

The pure-value programs trace allocation syscalls with every `mmap` forced
to fail and make no allocation calls. Only the collection-integration
program permits allocation. Python and Rust are test drivers/references,
without production networking implementations.

All five library execution groups passed together in 12.73 seconds. The
application's three groups passed in the same run in 6.18 seconds.

```sh
timeout --kill-after=2s 100s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 \
  CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --locked --test stdlib_net_execution -- --nocapture
```

The [address-filter application](stdlib-address-filter.md) combines parsing,
prefix selection, canonical output and host streams. GPU-kernel execution
is not established by these native tests. No compiler/runtime changes or new
host bindings were needed.

Sources: [RFC 4291](https://www.rfc-editor.org/rfc/rfc4291),
[RFC 5952](https://www.rfc-editor.org/rfc/rfc5952),
[RFC 3986](https://www.rfc-editor.org/rfc/rfc3986),
[RFC 4007](https://www.rfc-editor.org/rfc/rfc4007),
[RFC 1918](https://www.rfc-editor.org/rfc/rfc1918) and
[RFC 4193](https://www.rfc-editor.org/rfc/rfc4193).
