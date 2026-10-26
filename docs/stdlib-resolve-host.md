# Ordered host and service resolution

[`sample_programs/library/resolve_host.lani`](../sample_programs/library/resolve_host.lani)
is a native CLI for inspecting the socket endpoints returned by the system
resolver. It uses [`std::resolve`](stdlib-resolve.md) for at most one libc
`getaddrinfo` call and the existing `core::net::SocketAddr.format_into` for
numeric output. It does not open a connection or add URL or TLS policy.

All five focused application groups pass GPU compilation followed by native
Linux x86_64/glibc execution through the native C link profile with libc
startup. They cover 136 application/consumer process cases through separate
receipts. No extra resolver library is required.

```text
resolve-host HOST SERVICE [OPTIONS]
resolve-host --passive SERVICE [OPTIONS]

Options: --family any|ipv4|ipv6 --transport tcp|udp
         --numeric-host --numeric-service
         --max-results N --max-output N --max-write-calls N
```

For example:

```sh
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  --native-link --stdlib-root stdlib \
  sample_programs/library/resolve_host.lani -o /tmp/resolve-host

/tmp/resolve-host localhost http --family any --transport tcp
/tmp/resolve-host ::1 443 --numeric-host --numeric-service --family ipv6
/tmp/resolve-host --passive 8080 --family ipv4
```

## Lookup policy and output

The defaults are family `any`, transport `tcp`, named host lookup permitted,
address-configuration filtering disabled and IPv4-mapping flags disabled.
`ipv4` or `ipv6` restricts the requested family. `tcp` and `udp` select both
the socket kind and corresponding native protocol; no unspecified protocol or
raw-socket result is requested. The CLI does not expose `AI_ADDRCONFIG`,
canonical names, IDNA conversion or IPv4-mapping options.

An all-decimal service operand is always parsed strictly into a port in
0..65,535, including when `--numeric-service` is absent. Leading zeroes are
permitted. Overflow and signs are rejected rather than sent to a native
service-name lookup. A nondecimal operand selects a native named service;
`--numeric-service` rejects it. Named services can differ between TCP and UDP.
`--numeric-host` selects the native numeric-host policy rather than implementing
a second address parser. Consequently native numeric-host spellings and scope
lookup follow libc's rules.

`--passive` supplies a null native host with `AI_PASSIVE`, requesting wildcard
bind addresses. It accepts exactly one service operand and cannot be combined
with `--numeric-host` or a host operand. An empty host and the text `*` are
errors; neither is an alias for passive mode. This application does not expose
the library's separate null-host loopback or unspecified-service policies.
These host, service and flag behaviors follow the explicit-hints interface
documented by [getaddrinfo(3)](https://man7.org/linux/man-pages/man3/getaddrinfo.3.html).

Each returned endpoint is printed on its own LF-terminated line, such as
`127.0.0.1:80`, `[::1]:80` or `[fe80::1%42]:80`. IPv6 scope IDs are numeric.
Native order and duplicates are preserved. Output is not sorted or deduplicated,
and a returned address does not establish reachability or peer identity.
NSS configuration, local host/service databases, DNS and system address-order
policy determine the actual answer.

## Bounds and publication

| Bound | Default | Maximum |
| --- | --- | --- |
| Captured arguments | 32 | Fixed |
| Captured argument bytes, excluding NUL terminators | 8,192 | Fixed |
| Host spelling | 4,096 printable ASCII bytes | Fixed |
| Named service spelling | 64 printable ASCII bytes | Fixed |
| `--max-results N` | 64 | 1,024; minimum 1 |
| `--max-output N` | 65,536 bytes | 1 MiB |
| `--max-write-calls N` | 4,096 attempts | `i32::MAX` |

String inputs must be nonempty printable ASCII bytes without NUL. The typed
port's canonical decimal spelling is subject to the library service cap;
leading zeroes in the original CLI port spelling remain subject to the total
argument-byte cap. Limit values use unsigned decimal integers with no sign.
Zero output/write caps are valid. Options can appear among operands with
separate or `=` values; the last occurrence wins. `--` ends option parsing.
`--help` prints the usage with the configured write-call cap.

The library returns an owned address Vec only after validating and copying its
bounded native result list. The application formats every endpoint to compute
the complete output length before allocating its exact staging capacity. It
then formats and stages the lines, releases the address Vec, and begins stdout.
Argument, resolver, result-limit, formatting, allocation and output-byte-limit
failures publish no endpoint prefix. This is bounded result materialization,
not an unbounded stream of DNS records.

Every stdout write and final flush attempt consumes the same write-call cap,
including interrupted attempts. Short successful writes resume at the first
unwritten byte. Only `Interrupted` retries; zero progress, invalid successful
counts, `WouldBlock` and other host errors stop publication. An I/O or call-cap
failure can leave a confirmed byte prefix, including part of a line. Final
flush can fail after every staged byte has been accepted. Diagnostics report
the confirmed byte count and attempted-call count, without a rollback claim.
Stderr has its own eight-attempt cap and does not replace the original status
if diagnostics fail. The process explicitly ignores SIGPIPE.

## Blocking and ownership limits

One lookup performs at most one synchronous `getaddrinfo` call with no
application retry or timeout option; local validation or allocation can fail
before native entry. The host, service and result caps bound Lanius staging,
traversal and copied values. They do not preempt libc/NSS/DNS, bound native
allocation or CPU time, constrain the native list allocation before return,
or bound `freeaddrinfo` work. An external process supervisor can impose a
process timeout; the CLI does not claim native-call cancellation or a hard
lookup deadline. Blocking stdout/stderr writes likewise have no elapsed-time
guarantee.

The native list never escapes `lookup` and is released before it returns. The
application then owns one address Vec, one staged output buffer and the argument
snapshot. Every result path releases the active owners; by-value copies are
inactive aliases. The staged output remains live until publication completes
or fails. Stdout and stderr descriptor adapters borrow their handles and do
not close or change their flags.

## Status and focused gates

| Exit | Meaning |
| --- | --- |
| 0 | All staged endpoints published and flush complete, or help |
| 2 | Arguments, local resolver input/result bounds or staged output byte cap |
| 3 | Native lookup, invalid/unsupported native result or address formatting failure |
| 4 | Lanius allocation failure |
| 5 | Output/call failure or SIGPIPE-policy setup failure |

Native resolver diagnostics retain the EAI code, saved errno for `EAI_SYSTEM`
and local byte/result index. Native error strings are not parsed or used as
an application protocol. A native out-of-memory result remains a native lookup
error; the allocation exit identifies the Lanius layer's allocation failures.

[`tests/stdlib_resolve_host_execution.rs`](../tests/stdlib_resolve_host_execution.rs)
compiles and executes the actual application and its generic output helper
through the native profile. The gates compare ordered endpoint values
against an independent C `getaddrinfo` consumer, use deterministic native list
and error fixtures, check exact output-byte and result boundaries, exercise
real stdout faults plus scripted short transfers/flush failures, and fail each
observed local allocation while checking native-list and mapping release.
Test interposition and syscall tracing are test machinery rather than an
alternate production resolver.

| Group | Accepted process cases | Scope |
| --- | --- | --- |
| Matrix | 44 | Ordered native C reference comparisons, numeric IPv4/IPv6 and scopes, TCP/UDP, local host/service names, passive wildcard mode, duplicates, mixed families, explicit hints and option precedence |
| Limits and failures | 65 | Argument/input bounds, typed service ports, exact output/result boundaries, fully staged publication, native EAI/errno and malformed-result failures, native-list cleanup |
| Real output | 12 | Write/flush budget boundaries, interrupted/failed/zero-progress writes, `/dev/full`, broken pipes and a real seven-byte file-size-limited short write |
| Resources | 14 | Two unchanged-argv count controls, seven observed allocation failures and five additional cleanup paths |
| Scripted output helper | 1 | 24 internal scenarios for copied prefixes, short writes, interruptions, invalid counts, zero/finite call caps, empty output and final flush |

The matrix passed in 5.99 seconds:
`target/stdlib-work/resolve-host-matrix-first.log`. Limits, real output and the
scripted consumer passed within the 7.00-second mixed invocation recorded in
`target/stdlib-work/resolve-host-other-groups-first.log`; its resource group
failed a test-harness allocation-count assumption and is not accepted evidence
for resources. A second resource attempt failed a single-allocator-site
assumption after 5.84 seconds in
`target/stdlib-work/resolve-host-resource-owner-roles.log`.

The corrected resource group passed in 5.43 seconds:
`target/stdlib-work/resolve-host-resources-final-ledger.log`. Its count-one and
count-64 controls establish seven exact allocation roles: argument entries
120 bytes, argument storage 27, host staging 8, port staging 5, hints/result
frame 56, address Vec 40/2,560 and staged output 20/2,096. The Vec request scales
with result count; output reserve equals the complete formatted length. All
seven reached allocation sites fail once in turn without stdout publication,
native-list leakage or unreleased source mappings.

The ledger classifies source allocator requests by executable ELF instruction
range and `MAP_32BIT`, checks each role's instruction site across the same
artifact's baselines and fault runs, and rejects unknown or repeated generated
low-address frees. Eight CPU controls check the actual ledger: valid source
and high CRT/native cleanup, plus six invalid release mutations. Loader/libc
and high CRT bootstrap mappings remain outside that source-owner ledger.
These sizes describe the tested native layout and inputs, not a native-memory
quota. The eight controls and 24 helper scenarios are not additional native
application process cases.

These are separate selected invocations, not a whole-suite receipt. The linked
application and helper also pass generated-function ELF boundary validation.
The positive named-service matrix checks the local NSS provider order and
actual `/etc/services` records for HTTP/TCP and domain/TCP+UDP before lookup;
numeric and local-name cases do not depend on a public DNS answer. Other named
lookups, including the unknown-service negative, follow the installed NSS
policy and can consult later providers. Application use can invoke DNS or
other configured network services.

Coverage remains finite for the selected libc/NSS configuration, not every host
database, DNS schedule, platform or native resource failure. Reported elapsed
times describe focused test invocations, not resolver throughput. No other
host or GPU-kernel execution claim is made.
