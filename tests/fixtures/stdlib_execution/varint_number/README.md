# Checked scalar varint application fixture

The independent oracle uses arbitrary-precision integer division for unsigned
base-128 encoding and a weighted digit sum for decoding. Admission requires one
complete wire value, u64 range and equality to its minimal encoding; it does
not mirror the production reader's byte-limit/error-precedence branches.
Signed values use mathematical ZigZag (`2*n` or `-2*n-1`), including i64::MIN.
Literal vectors check 0/127/128/150 and positive/negative ZigZag examples.
Expected bytes and values are independently constructed, not just round trips.

The wire and signed mapping follow the official
[base-128](https://protobuf.dev/programming-guides/encoding/#base-128-varints)
and [sintN ZigZag](https://protobuf.dev/programming-guides/encoding/#signed-integers)
descriptions. The library's shortest-encoding and the application's full-consume
requirements are an explicit strict scalar profile. This fixture makes no
claim that all Protobuf parsers reject nonminimal encodings, and signed modes
are neither signed LEB128 nor Protobuf intN negative encoding.

CLI is `varint_number MODE VALUE`, or sole `--help`/`-h`. The two encode modes
emit raw bytes; unsigned decimal has digits only, while signed decimal permits
one optional sign. Both allow leading zeros and at most 20 bytes. The decode
modes accept 2..20 upper/lowercase hexadecimal characters in complete pairs
and print one canonical decimal number plus LF. Prefixes, separators and
trailing wire bytes are rejected. Captured argv is at most two arguments and
64 total bytes. No stdin is read.

| Group | Cases | Scope |
| --- | ---: | --- |
| model | 76 | All four modes, every unsigned encoded-length transition, full-width unsigned/signed extrema, signed ZigZag boundaries, uppercase/lowercase hex and seeded integers |
| wire | 30 | Invalid hex length/digits/spacing/prefix, truncation, short and maximum-width nonminimal forms, tenth-byte payload/continuation overflow and trailing bytes in both decode modes |
| cli | 34 | Arity/mode/help, decimal signs/space/range/length/non-ASCII, overlong hex, leading zeros, negative zero and explicit plus |
| io | 10 | Baseline, two reached argv ENOMEM sites, actual closed data/help stdout, output EIO/EINTR, signal failure, 64-attempt cap and wire-failure cleanup |

Caller scratch holds all wire and formatted output; only the two argv owners
allocate. Full traces require every successful mapping explicitly released at
the same address/requested length before any stdout or stderr write. They
reject stdin reads, borrowed descriptor closes and other allocation services.
Selected mmap failures must be reached at matching baseline ordinal/arguments,
return 4 and publish nothing. Wire failure likewise releases both owners before
its diagnostic. These are finite selected observations, without automatic
lifetime, leak-freedom or exhaustive failure claims.

Actual EPIPE and injected EIO return 5; write EINTR retries to the exact raw
wire. Signal policy failure is silent. A compact summary requires 64 write
errors plus one successful diagnostic and status 5. That summary observes
attempt limits, not the full release ledger. No successful transfer count is
fabricated, and no extra write segmentation is added to obtain prefix evidence.
Argument-host status 3, positive short writes and partial-output behavior are
not covered by this corpus.

The driver compiles once per libtest process, requires an actual little-endian
ELF64 x86-64 executable and applies the shared strict jump gate. The standalone
oracle also rejects non-ELF targets. Native children have 15-second deadlines
and registered groups 85-second deadlines. Commands, exact stdout/stderr/status
and selected syscall evidence are retained.

```sh
python3 -B tests/fixtures/stdlib_execution/varint_number/oracle.py controls
python3 -B tests/fixtures/stdlib_execution/varint_number/oracle.py model PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/varint_number/oracle.py wire PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/varint_number/oracle.py cli PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/varint_number/oracle.py io PATH_TO_ELF
```

## Acceptance

All four registered tests passed in 6.62 seconds: **150 native Linux x86_64
cases**, with no failures or filtered tests. The separate Rust build took
1.67 seconds. The GPU compiler produced the strict-admitted ELF64 program;
execution was on the CPU. Receipt:
`target/stdlib-work/native-varint-number-first.log`.

| Group | Cases | Evidence |
| --- | ---: | --- |
| model | 76 | `/tmp/varint-number-model-p_ioatgr` |
| wire | 30 | `/tmp/varint-number-wire-xpzx6cfj` |
| cli | 34 | `/tmp/varint-number-cli-oqwvx0qs` |
| io | 10 | `/tmp/varint-number-io-8oxxnny8` |

Accepted identities (SHA-256):

- Application: `6dea3d57ce10a7e8cacae21494177c05c7fb6807c0854f99a8ad0e81dde02609`.
- Oracle: `459aa33f6e27ffd17bab535894ee9758fb1d0cee40028d0bda5fbb00f1c4d834`.
- Varint library: `a0ef8c9ff2c5fc83fb8449c6baeaff4f24d9c3a0f32b962b68dfc11efbcc147b`.

The inspected baseline explicitly releases both argv mappings before writing
the ten raw bytes `ff ff ff ff ff ff ff ff ff 01` for u64::MAX. No payload
allocation occurs. Both selected ENOMEM sites were reached at mmap ordinals
1 and 2, returning 4 with empty stdout and explicit matching releases for
every mapping successfully obtained in those traces. The nonminimal-wire
failure also releases both owners before its status-2 diagnostic. No traced
case reads stdin or closes a borrowed descriptor.

Actual closed data/help stdout produces EPIPE and status 5. Injected EIO
returns 5 with no output; EINTR retries to the exact ten-byte wire. Signal
setup failure returns 5 silently. Full traces observe selected owner cleanup.
The compact attempt receipt separately records 65 writes: 64 injected EINTR
errors and one successful diagnostic, with status 5. It establishes the output
attempt bound without supplying a complete release ledger.

Eight CPU control families passed before admission, including literal
wire/decimal vectors, full-width ZigZag, corpus counts, malformed-wire
references and deliberately missing owner release. Argument-host status 3,
positive short writes, output prefixes, GPU device execution, formal
verification, internal-error injection, automatic lifetime guarantees and
exhaustive faults remain unclaimed. Driver hashes are omitted; the application,
library and oracle identities above describe this runtime receipt.
