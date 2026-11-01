# Checked Base64 byte application fixture

CLI is `base64_bytes encode|decode PROFILE`, or sole `--help`/`-h`. Profiles
are `standard`, `standard-unpadded`, `url` and `url-unpadded`. Input is binary
stdin through EOF, limited to 1 MiB. Successful conversion writes exactly its
bytes with no added newline. Invalid CLI, noncanonical wire input and input
limits return 2 with no data output. Input host errors return 3, allocation
failure 4, and signal/output failure 5. Status 6 is an internal contract error.

The independent oracle uses Python's standard Base64 byte operations, anchored
by the seven literal [RFC 4648 section 10 vectors](https://www.rfc-editor.org/rfc/rfc4648.html#section-10).
It separately checks the selected alphabet, length and placement of padding.
Re-encoding admitted decoded bytes must reproduce the original input, enforcing
canonical unused bits and padding. Unpadded profiles forbid every `=`. Expected
wire and plain bytes are independently constructed, rather than tested only by
round trips through the application.

| Group | Cases | Scope |
| --- | ---: | --- |
| model | 100 | All four profiles; RFC vectors, all 256 byte values, `ff` tails, 1023/1024/1025-byte boundaries, cross-read decoding, maximum raw input and maximum encoded input |
| rejection | 56 | Structural length, whitespace/control/non-ASCII bytes, opposite alphabet, internal/missing/unexpected padding, nonzero tail bits and 1 MiB + 1 input in both modes |
| cli | 20 | Exact arity, mode/profile spelling, argument byte caps, non-UTF8 names, sole help and validation before stdin |
| io | 18 | Baseline, four reached owner ENOMEM sites, actual input/output errors, EINTR, required EOF, genuine output prefix, signal failure, attempt limits and selected no-output allocation paths |

Valid nonempty input has two argv mappings, retired before the fixed initialized
1 MiB input reservation. The output reservation has the exact converted length.
The complete input and EOF precede output allocation; input is retired before
stdout, while output remains live through stdout and retires before an error
diagnostic. Empty input still obtains the fixed input mapping but no output
backing or stdout write. Invalid decoding fails before output allocation.

Full selected traces match every successful mapping with an explicit release
at its address and requested length. Each selected ENOMEM must be reached at
the baseline mmap ordinal and arguments. The ledger allows address reuse only
after release, rejects borrowed descriptor closes and other allocation services,
and requires cleanup before diagnostics. These are finite observations, without
automatic lifetime, leak-freedom or exhaustive allocation-failure claims.

Actual directory stdin and closed data/help stdout exercise host errors.
Injected read and write EINTR must preserve the exact result. A later read
error and an error on the required EOF call publish nothing. The output-prefix
control lets a real first 1024-byte write complete, then injects EIO into the
second write and requires precisely that prefix with status 5. It does not
fabricate a successful transfer count or force artificial app segmentation.
Compact summaries separately check 8192 interrupted reads returning 2, and
2048 interrupted data writes plus one successful diagnostic returning 5. Those
summaries establish attempt bounds without a complete release ledger.

The driver compiles once per libtest process, requires an actual little-endian
ELF64 x86-64 executable and applies the shared strict jump gate. The standalone
oracle also rejects non-ELF targets. Native children have 15-second deadlines,
registered groups 85-second deadlines. Commands, exact stdout/stderr/status
and selected syscall evidence are retained.

```sh
python3 -B tests/fixtures/stdlib_execution/base64_bytes/oracle.py controls
python3 -B tests/fixtures/stdlib_execution/base64_bytes/oracle.py model PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/base64_bytes/oracle.py rejection PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/base64_bytes/oracle.py cli PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/base64_bytes/oracle.py io PATH_TO_ELF
```

## Acceptance

All four registered tests passed on the first attempt in 8.85 seconds:
**194 native Linux x86_64 cases**, no failures or filtered tests. The separate
Rust build took 1.73 seconds. The GPU compiler produced the strict-admitted
ELF64 program; execution was on the CPU. Receipt:
`target/stdlib-work/checked-base64-bytes-first.log`.

| Group | Cases | Evidence |
| --- | ---: | --- |
| model | 100 | `/tmp/base64-bytes-model-k2vfzdz6` |
| rejection | 56 | `/tmp/base64-bytes-rejection-9jhnkbb5` |
| cli | 20 | `/tmp/base64-bytes-cli-ujcf57bj` |
| io | 18 | `/tmp/base64-bytes-io-6h0z30y1` |

Accepted identities (SHA-256):

- Application: `5f09b0e7c408fcd7854c4c76536b433383b2558e5215516bb09b5a11e3447799`.
- Oracle: `675fd54af4d0ca50aeda366c5304eaa8c9513860f3b96775b85048be869063c6`.
- Base64 library: `c5eb1fc4ee603adb8f681695a3dd22885008b76d37fb70d78ce013d95b1837e8`.

The inspected baseline releases its 80-byte and 9-byte argv mappings before
reserving 1048576 input bytes. It reads 4097 bytes and EOF, reserves exactly
5464 output bytes, releases input, writes the exact canonical URL encoding,
then releases output. The four selected ENOMEM cases were reached at mapping
ordinals 1 through 4, returning 4 with empty stdout and matching explicit
releases of every owner successfully obtained. Empty encoding and rejected
noncanonical `Zh==` each obtain only the two argv maps and fixed input map,
without output backing. Neither case writes data.

Directory stdin returns EISDIR and status 3. Actual closed data/help stdout
returns EPIPE and status 5. Injected read/write EINTR preserves all 5464 output
bytes. Later-read and required-EOF EIO return 3 without data; the EOF fault
follows all 4097 input bytes. The output fault retains a real successful
1024-byte prefix, then EIO on the next write returns 5 after releasing output
and before the diagnostic. Signal setup EIO returns 5 silently with no maps.
The full selected traces observe releases; the compact attempt summaries
separately report 8192 read errors, or 2048 write errors and one successful
diagnostic, establishing those bounds without a full release ledger.

CPU controls passed before admission, covering literal vectors, distinct
alphabets, corpus counts, strict rejected inputs, exact help/diagnostic lengths
and a deliberately missing owner release. Driver hashes are omitted because
root formats Rust drivers after runtime acceptance; production and oracle
identities above are unchanged.

Argument-host status 3, positive kernel short writes, internal-error injection,
GPU device execution, formal verification, automatic lifetime guarantees and
exhaustive faults are not covered by this fixture.
