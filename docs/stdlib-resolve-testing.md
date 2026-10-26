# Resolver native verification

The production [system resolver](stdlib-resolve.md) is implemented in Lanius and
calls libc `getaddrinfo` directly. The C files described here are test
infrastructure: an independent caller of the installed libc and a native
boundary observer. They do not supply a production resolver or DNS client.

The executable profile is Linux x86_64 with glibc. The driver is
`tests/stdlib_resolve_execution.rs`; fixtures are under
`tests/fixtures/stdlib_foundation/resolve/`. Root serializes actual GPU
compilation and native acceptance runs.

## Installed ABI and independent oracle

`abi.h` checks the installed headers with C11 static assertions:

| Type | Size / alignment | Member offsets |
| --- | --- | --- |
| `addrinfo` | 48 / 8 | flags 0, family 4, socket type 8, protocol 12, address length 16, address pointer 24, canonical pointer 32, next pointer 40 |
| `sockaddr_in` | 16 | family 0, port 2, address 4 |
| `sockaddr_in6` | 28 | family 0, port 2, flow info 4, address 8, scope 24 |

It also checks scalar widths, little endian order, family/protocol constants,
supported `AI_*` values and `EAI_SYSTEM`. These are assertions for this native
profile, not a portable C structure representation.

`oracle.c` uses real header-declared structures and calls the installed libc.
Its invocation is:

```text
oracle HOST|- SERVICE|- FAMILY KIND FLAGS
```

`-` selects a null argument; family is 0/2/10 and kind is 1/2. The result
preserves list order and duplicates. Each address is encoded as version,
decimal port, decimal scope and raw address octets in hexadecimal. An error
reports the raw EAI code and errno only for EAI_SYSTEM. The source fixture
encodes owned `core::net::SocketAddr` values independently, after the native
list has already been freed.

The contract follows the [getaddrinfo/freeaddrinfo API description in RFC 3493](https://www.rfc-editor.org/rfc/rfc3493.html#section-6.1)
and the [Linux man-pages description](https://man7.org/linux/man-pages/man3/getaddrinfo.3.html).
Tests use explicit zeroed hints, avoiding libc's special defaults for a null
hints pointer.

## Native observer and synthetic lists

`observer.c` interposes only the native boundary. Mode zero delegates to real
libc using `dlsym(RTLD_NEXT, ...)`. It checks alignment, the packed 48-byte hints
plus 8-byte result slot, zeroed unused fields and padding, an initially null
result pointer, a cleared errno, and terminated host/service bytes. The packet
driver compares exact hint fields, argument lengths, nullness and byte hashes.

Successful native results are tracked by their original head. A free must
release that head exactly once. Synthetic data is poisoned and released at
free, so the subsequent output tests owned address copies. Malformed lists
remain physically backed. The observer releases synthetic storage directly,
including cycles, without asking libc to walk an intentionally corrupt list.
It ignores unspecified output `ai_flags` and never requires a canonical name.

The raw fixture uses `test_resolve_begin(mode, parameter)` and reads fifteen
scalar statistics with `test_resolve_stat`. Application fixtures can reuse the
object without changing production imports:

| Environment variable | Meaning |
| --- | --- |
| `LANIUS_RESOLVE_MODE` | Zero for libc; one for four ordered mixed-family records; three for EAI_SYSTEM/EACCES; sixteen for a configured list length. Other modes exercise malformed metadata and native errors. |
| `LANIUS_RESOLVE_COUNT` | Synthetic list length for modes sixteen/seventeen, or malformed record ordinal for other fault modes. |
| `LANIUS_RESOLVE_TRACE` | Optional event file. A `G` line records hints, null arguments, lengths and mode; `F` records the external head release. |

Mode twenty-one returns EAI_SERVICE. Mode twenty-two returns EAI_FAIL while
scribbling a physically backed, non-owned pointer into the output slot. The
latter proves that a nonzero status transfers no list ownership.

Mode one returns IPv4 `198.51.100.227`, scoped IPv6
`2001:db8:1234:ffff:0:abcd:dead:beef`, the duplicate IPv4 record, then scoped
IPv6 `::ffff:192.0.2.123`. The IPv6 scopes exercise 2309737967 and 4294967295.
An explicit requested family is respected; socket type and protocol follow
the requested TCP/UDP kind. Named services use synthetic port 43210, typed
ports preserve their decimal value and unspecified services use zero.

## Determinism and resource scope

The real matrix uses numeric hosts, typed ports, explicit null hosts, mapping
flags and scoped numeric addresses. Named cases use a files-first locally
backed `localhost` and locally proven service/protocol records. Providers before
`files` must also be local, with default success return; later providers such as
SSS cannot be reached for those known records. The driver checks those NSS
preconditions before named lookups and excludes `http` over UDP, which is not
locally present in the tested profile. It does not require localhost to contain
both address families or hardcode libc's ordering. Unknown external names are
not used as negative controls; native failure cases are injected.

The source cap bounds the number of decoded/copied results, not native libc
allocation or blocking time. Test processes have an external timeout. These
tests do not establish a production lookup deadline.

Native-linked executables are checked with the dedicated linked-ELF validator.
Allocation injection classifies source-owned `MAP_32BIT` mappings at verified
syscall instruction boundaries. `allocation_sites.py` checks exact allocator
runtime bytes inside executable ELF LOADs, including the appended thunks outside
sized source-function symbols, and checks syscall boundaries inside named
Lanius/main functions. It verifies the mmap register setup (address zero,
protection three, flags 0x62, fd minus one, offset zero, syscall nine) and the
adjacent munmap syscall eleven. The ledger accepts the actual post-syscall IPs
reported by `strace -i` and checks each address and requested length. Loader/libc
mappings and the separate runtime bootstrap mapping are outside that ledger.
The observer independently verifies native list release. Each injected source
allocation failure is one-shot and followed by a successful retry over unchanged
input.

## Acceptance

All **four raw driver groups** passed through the separate invocations below.

The real **80-case matrix passed** actual GPU compilation, native linking, linked
ELF validation and source execution in **6.12 seconds**:

`target/stdlib-work/resolve-native-matrix-local-services.log`

The measured inner native batch was 5.874654945 seconds including its first
compile/link; that figure is not a resolver throughput measurement. Every
result or raw EAI error was compared with the independent CPU libc oracle.
The observer also checked exact hint and packed-argument metadata and native
list cleanup. The earlier 0.00-second attempt stopped at the test's overly
strict NSS precondition, before source compilation. The corrected precondition
proves local success for each actual named service/protocol pair and excludes
the absent `http`/UDP pair.

Two more groups passed in a **9.68-second expanded invocation**:

`target/stdlib-work/resolve-expanded-groups-first.log`

They cover **177 local rejection cases** across three storage layouts,
**59 traced strided rejection controls** with zero source allocation, **15
accepted exact/maximum-limit and ignored-view cases**, and **97 synthetic
native-list/error cases**. The latter includes all twenty-two synthetic modes,
ordered duplicate and scoped values, native errno/error separation, malformed
nodes, the exact 4096-result cap, over-cap lists and physically backed cycles.

The allocation-only retry passed in **6.04 seconds**:

`target/stdlib-work/resolve-allocator-sites-oom-retry.log`

Its bounded named-host/named-service fixture reaches **four source allocation
positions**, requesting **97, 17, 56 and 160 bytes**: terminated host, terminated
service, packed hints/output slot, and four owned address values. The baseline
plus four one-shot injected runs check exact live-address/request-length
balance, the failure phase, unchanged inputs and a complete successful retry.
Result-vector allocation failure releases the native list exactly once; failures
before the native call acquire no list. Synthetic list poisoning and value checks
also confirm independent output after native cleanup.

The earlier expanded invocation stopped this group before fault injection:
its first classifier assumed all generated runtime code lay inside sized source
functions. The corrected classifier recognizes the appended allocator thunks
and verifies their opcodes. CPU replay of the retained minimal ELF/trace also
balances all ten source mappings. This was a test-classifier correction;
production code was unchanged.

Installed-header and CPU oracle/observer controls pass on glibc 2.39. Executable
acceptance covers Linux x86_64/glibc only. These finite tests establish neither
other target support nor behavior under arbitrary external DNS configuration
or a production lookup deadline.
