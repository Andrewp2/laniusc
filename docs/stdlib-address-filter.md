# Address filter

`sample_programs/library/address_filter.lani` is an executable numeric address
canonicalizer and CIDR filter. It combines `core::net` with native byte
streams and raw counted arguments, using fixed-size stack buffers and no
heap allocation. It performs no DNS/interface lookup or socket operations.

```sh
target/stdlib-build/debug/laniusc --stdlib-root stdlib \
  sample_programs/library/address_filter.lani -o /tmp/address-filter

printf '192.0.2.1\n198.51.100.7\n' |
  /tmp/address-filter --network 192.0.2.0/24
# 192.0.2.1

printf '2001:0DB8:0:0:0:0:0:1\n::FFFF:C000:201\n' |
  /tmp/address-filter
# 2001:db8::1
# ::ffff:192.0.2.1

printf '[FE80:0:0:0:0:0:0:1%%00042]:00080\n' |
  /tmp/address-filter --socket
# [fe80::1%42]:80

printf '2001:db8:1::1234/64\n' |
  /tmp/address-filter --prefix --truncate --network 2001:db8::/32
# 2001:db8:1::/64
```

The target is x86_64 Linux. Compilation uses the GPU compiler to produce a
native CPU executable; these examples do not establish GPU-kernel support.

## Command line

```text
address-filter [--socket|--prefix|--scoped] [--truncate] [--network CIDR] [--invert]
address-filter --help
```

Default mode accepts bare IPv4 or IPv6. `--socket` accepts numeric
`IPv4:port` or `[IPv6%scope]:port`; `--scoped` accepts IPv6 with an optional
numeric zone. `--prefix` accepts CIDRs with host bits clear. `--truncate`
requires prefix mode and explicitly clears host bits before formatting and
selection. Mode options are mutually exclusive.

`--network` takes one strict CIDR. Address/socket/scoped modes select by
address membership, ignoring port/zone metadata. Prefix mode requires the
entire input network to be contained. Families remain distinct: a mapped
IPv6 address is not an IPv4 member. `--invert` requires a network and
reverses selection, including cross-family nonmembers. Duplicate options,
unknown arguments, nonnumeric hosts/zones and a network with host bits fail
before input is processed. Help is accepted as the sole argument.

## Input, output and failure

Input consists of newline-separated records. CR is removed only immediately
before LF; no other whitespace is trimmed. A final nonempty record without
LF is accepted. Empty input succeeds with no output, but a blank record is
invalid. Every value fits the 64-byte record limit; the optional CRLF ending
does not consume that limit. NUL and non-ASCII bytes are invalid syntax.

Each selected record is emitted in canonical form with one LF. The rules
and byte/value contracts are documented in [stdlib-net.md](stdlib-net.md).
Every input record is parsed even when the filter would exclude it.

Exit statuses are 0 for success, 2 for invalid arguments/input, and 3 for a
returned I/O failure. Failures write a diagnostic to stderr. Earlier complete
records may already be on stdout when a later record or I/O operation fails.
Input and output stream interruptions are retried. Would-block, other
reported host errors and a zero-progress write return 3.

Memory use is constant in the number of records. Stream chunks, a bounded
record and formatted output are held on the stack. The program never
collects the input or invokes an allocator.

## Executable tests

`tests/stdlib_address_filter_execution.rs` verifies:

- Canonical output in all four modes, scoped sockets, mapped-family
  distinction, inverted selection and whole-prefix containment.
- A 20000-record input crossing 1024-byte read boundaries, CRLF, final
  records without LF, maximum-size sockets, invalid options, binary/blank
  records, limits and a late error after an emitted prefix.
- Actual injected read/write interruptions, read EIO/EAGAIN, write EIO and
  zero progress. Fault tests assert that strace's `INJECTED` marker occurs;
  syscall filtering cannot silently bypass the injected operation.

All application executions trace allocation syscalls with every `mmap`
forced to fail, and make no allocation calls. All three groups passed
together in 6.18 seconds. The library's independent Python address/CIDR corpus and
structured collection tests are in `tests/stdlib_net_execution.rs`.

A native throughput check on CPU 8 used alternating records
`2001:0DB8:0000:0:0:0:0:1` and `::FFFF:192.0.2.129`, LF endings,
file input and stdout directed to `/dev/null`. One warm run preceded five
alternating measured runs at each size. Process startup, arguments,
parsing, formatting and I/O are included:

| Records | Median | Observed range |
| --- | --- | --- |
| 20000 | 101.850 ms | 92.770–103.789 ms |
| 200000 | 1012.083 ms | 795.994–1138.742 ms |

These measurements describe this native build and host. They are not a
comparison with another compiler or a timing assertion in the test suite.

```sh
timeout --kill-after=2s 100s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 \
  CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --locked --test stdlib_address_filter_execution -- --nocapture
```
