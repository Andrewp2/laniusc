# Buffered binary record selection application fixture

The independent oracle splits raw bytes at one delimiter byte, includes each
delimiter in its record, preserves a final nonempty unterminated record, and
selects zero-based records `0, EVERY, 2*EVERY, ...`. It performs no text decoding
and imports no production parser, buffering or delimiter implementation.
Consecutive delimiters are individual one-byte records; a final delimiter adds
no phantom record. Rejoining all independent records preserves the input.

The CLI is exactly `select_records DELIMITER EVERY` or sole `--help`/`-h`.
Both numeric tokens use unsigned ASCII decimal with leading zeros allowed:
delimiter 0..255 and EVERY 1..65536. Each token is at most 64 bytes, with at
most two arguments and 128 captured bytes. No option parser or text format is
implied. Native output is the selected original bytes, including delimiters.

| Group | Cases | Scope |
| --- | ---: | --- |
| model | 33 | Empty/consecutive/final records, binary/NUL/non-UTF8 delimiters, zero-based cadence, selected/skipped records across 1024-byte transfers and 4096-byte reader chunks, exact record/count/input caps and seeded streams |
| limits | 8 | Selected/skipped oversized terminated and unterminated records, excess record count/input bytes, later failure after a valid selected prefix; stdout remains empty |
| cli | 33 | Arity, decimal/sign/space/non-ASCII/range/overflow/length checks, sole help bypass, leading zeros and exact 128-byte argument boundary |
| io | 17 | Traced baseline, five reached argv/reader/staging allocation faults, actual input and closed stdout errors, read/write EINTR, later and required-EOF read errors, real 1024-byte output prefix, signal failure and input/output attempt caps |

Limits apply to all records, including skipped ones: 1 MiB logical input and
output, 65536 records, and 65536 bytes per record including its delimiter.
The exact unterminated record boundary requires actual EOF before acceptance.
The source is streamed through a 4096-byte buffered reader; all selected output
is staged until whole-input validation completes. A 1 MiB sparse-selection case
selects only the first 16-byte record and requires at most four observed mmap
calls, checking that skipped data did not obtain source-sized retained storage.
The all-selected 1 MiB case separately exercises the complete output bound.

Every successful mmap in a full trace requires an explicit successful munmap
of the same address and requested length. The baseline checks actual input
EOF and reader release before stdout, with no allocation after EOF. Selected
ENOMEM faults must reach the requested ordinal with matching baseline arguments,
return 4 and publish nothing. The campaign is finite; these observations do
not establish automatic lifetime enforcement, leak freedom or exhaustive faults.

An output EIO follows an actual successful 1024-byte write and must retain
exactly that independent selected prefix. Read errors, including failure of
the required EOF probe after complete data, must publish nothing. No successful
transfer count is fabricated. Compact interruption summaries require 8192
input read errors, or 8192 output errors plus one successful stderr diagnostic;
the summaries do not observe allocation cleanup. Helper call quotas and raw
input/output attempt quotas are distinct from host wall-clock deadlines.

The driver compiles once per libtest process, explicitly requires a
little-endian ELF64 x86-64 executable and applies the shared strict jump gate.
The standalone oracle also rejects non-ELF targets. Native children have
15-second deadlines and registered groups 85-second deadlines. Input, commands,
output, status and selected syscall traces are retained.

```sh
python3 -B tests/fixtures/stdlib_execution/select_records/oracle.py controls
python3 -B tests/fixtures/stdlib_execution/select_records/oracle.py model PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/select_records/oracle.py limits PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/select_records/oracle.py cli PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/select_records/oracle.py io PATH_TO_ELF
```

## Acceptance

All four registered tests passed on the first attempt in 8.51 seconds:
**91 distinct native Linux x86_64 cases**, with no failures or filtered tests.
Receipt: `target/stdlib-work/delimited-io-select-records-first.log`.

| Group | Cases | Evidence |
| --- | ---: | --- |
| model | 33 | `/tmp/select-records-model-vos26kjf` |
| limits | 8 | `/tmp/select-records-limits-_34skmon` |
| cli | 33 | `/tmp/select-records-cli-nyt88bci` |
| io | 17 | `/tmp/select-records-io-l3z5medd` |

Accepted identities (SHA-256):

- Application: `9856d42ffc8a6c78738cf0b71d1f5b423f46559a155e317a10be42fd6343d346`.
- Oracle: `a483a17687314607ae4f8475e18783cf597ed2f1dc2b6d3687c878d77d306910`.

The inspected baseline reads 5125 bytes and actual EOF, releases its 4096-byte
reader mapping, then publishes exactly 3075 independently selected bytes.
It performs no allocation after EOF. The five selected allocation-denial
sites are mmap ordinals 1 and 2 (argv), 3 (reader), 4 and 6 (first/last staging
growth). These faults were all reached, returned 4 with empty stdout and
matched explicit releases for every successfully observed mapping. This is
a selected campaign, not every allocation site.

The real output-prefix trace records an acknowledged 1024-byte write,
second-write EIO and the diagnostic; stdout is exactly the expected selected
prefix and status is 5. The required-EOF fault occurs after all 5125 input
bytes were read and still publishes nothing. The 1 MiB sparse-selection trace
has four mmap calls and emits only its first 16-byte record.

Compact summaries record 8192 read errors or 8192 write errors plus one
successful diagnostic write (8193 total), with statuses 2 and 5 respectively.
They establish attempted-I/O bounds; the separate full traces establish the
selected release observations. The summaries do not provide release ledgers.

Eight CPU control families passed before native admission, including explicit
record/selection vectors, generated corpus counts, all-byte delimiter rejoining
and a deliberately missing observed release. GPU device execution, formal
verification, forced internal-error paths, automatic lifetime guarantees and
exhaustive fault coverage remain unclaimed. Driver hashes are omitted because
later whitespace formatting does not change the accepted application or oracle.
