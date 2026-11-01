# Checked layout record-storage application fixture

The application takes one decimal COUNT in 0..65536, constructs checked record
and array layouts, allocates one arena block, writes and reads every field,
checks zero padding, and reports the actual byte checksum. It never reads
stdin. Each record has tag/serial/value at offsets 0/4/8, alignment 8 and
stride 16. The serial is stored little-endian and the value big-endian.

The oracle computes each field's contribution directly from integer byte
significance and its physical position. Padding contributes zero. It does
not import or reproduce the layout, arena or endian implementation. Explicit
literal record-zero and record-one byte vectors check the oracle separately.
It also checks full-width serial/value bits for the final record at the
65536-record boundary.

The exact 24-byte report consists of three big-endian u64 values: count,
count times 16 storage bytes, and sum of `(byte_offset + 1) * byte_value`
over the complete storage. The checksum fits u64 at the admitted maximum.
Zero count produces 24 zero bytes and obtains no arena backing mapping.

| Group | Cases | Scope |
| --- | ---: | --- |
| model | 20 | Zero/singleton/small counts, 64-record and 256-record storage boundaries, 65535/65536 records, leading zeros and exact 64-byte COUNT arguments |
| cli | 28 | Missing/extra/mixed arguments, sole help, strict unsigned decimal, signs/space/non-ASCII, range/overflow and argument byte cap |
| io | 10 | Traced baseline, three reached argv/arena ENOMEM failures, actual closed data/help stdout, output EIO/EINTR, signal failure and 64-attempt output interruption cap |

Normal nonzero counts have two argv mappings and one arena chunk; zero count
has only the argv mappings. Every successful mapping in a full trace must
have a successful explicit release of the same address and requested length.
The baseline checks that the arena chunk is released before the first stdout
write; argv owners may remain until the call returns. Selected mmap failures
must occur at the requested ordinal with the baseline arguments, return 4
and leave stdout empty. These are finite observations, without exhaustive
fault, automatic lifetime or leak-freedom claims.

All children receive directory stdin to catch accidental reads. Full traces
reject any read call. Output errors return 5; SIGPIPE policy failure is silent.
One injected EINTR must retry and preserve the exact report. The interruption
cap uses a compact strace summary requiring 64 write errors plus one successful
stderr diagnostic write; that summary does not observe allocation cleanup.
No successful transfer count is fabricated.

The Rust driver compiles once per libtest process, requires an actual
little-endian ELF64 x86-64 executable, then applies the shared strict jump
admission gate. The standalone oracle also rejects a non-ELF target. Native
children have 15-second deadlines and registered groups 85-second deadlines.
Commands, output, status and selected syscall evidence are retained.

```sh
python3 -B tests/fixtures/stdlib_execution/layout_records/oracle.py controls
python3 -B tests/fixtures/stdlib_execution/layout_records/oracle.py model PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/layout_records/oracle.py cli PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/layout_records/oracle.py io PATH_TO_ELF
```

## Acceptance

All three registered tests passed in 7.32 seconds: **58 distinct native
Linux x86_64 cases**, with no failures or filtered tests. Receipt:
`target/stdlib-work/layout-records-first.log`.

| Group | Cases | Evidence |
| --- | ---: | --- |
| model | 20 | `/tmp/layout-records-model-6t0qni1e` |
| cli | 28 | `/tmp/layout-records-cli-brho61zj` |
| io | 10 | `/tmp/layout-records-io-d9y3fc6a` |

Accepted identities (SHA-256):

- Application: `194ca89cebd16151f0c3385169b5881b9ba09f60d8920e3164cf15b1d10ab6f2`.
- Oracle: `8a239e7827ead3d73d6b5fb0bb2e71e15c64b71f7a158e8a40df840fcbb3b171`.

The inspected 257-record baseline requests three mappings: two argv owners
and one arena chunk. It explicitly releases the arena mapping before the
actual 24-byte report write and releases both argv mappings afterward.
The zero-count trace has only the two argv mappings and publishes exactly
24 zero bytes. No traced case reads stdin.

All three selected mmap denials were reached at ordinals 1, 2 and 3, each
returning 4 with empty stdout and matching releases for every mapping that
was successfully obtained. The first output EINTR retries to the exact
independent report; EIO and actual closed-reader EPIPE return 5 with empty
stdout. Full traces check owner cleanup on those paths. The compact attempt
receipt records 65 writes: 64 injected EINTR errors and one successful
stderr diagnostic write, with status 5 and empty stdout. Signal setup
failure also returns 5, silently.

Eight CPU control families passed before native admission, including explicit
record bytes, full-width fields, report bounds, corpus counts and a
deliberately missing observed release. These receipts establish the selected
record storage and fault behavior on the tested target. GPU device execution,
formal verification, unreachable internal-error injection, exhaustive faults
and automatic lifetime or leak-freedom guarantees remain unclaimed. Driver
hashes are omitted because subsequent whitespace formatting does not change
the accepted application or oracle.
