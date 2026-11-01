# Owned input statistics application fixture

CLI is `input_stats bytes|text [PATH|-]`, or sole `--help`/`-h`. Omitted
PATH and exact `-` select borrowed stdin; every other operand is a literal
raw Unix byte path, including flag-looking names. Paths are 1..4095 bytes,
and captured argv is at most two arguments and 4100 total bytes. An opened
file is read-only with close-on-exec; normal final symlinks are followed.

Byte mode reports `bytes=N\nnul=M\n`. Text mode requires strict UTF-8 and
reports `bytes=N\nscalars=S\nlf=L\n`. Values are canonical decimal; `lf`
counts byte 0x0A, so CRLF contributes one and CR remains unchanged. No final
newline is inferred from the input. The independent Python model uses byte
length/NUL counts and strict UTF-8 decoding followed by Unicode scalar and LF
counts. Expected records are built directly, with literal binary and mixed
Unicode controls rather than a production round trip.

Both modes use public `alloc::io` whole-input collection with a 1 MiB/8192-call
profile. Successful collection requires actual EOF, including a one-byte probe
at the exact cap. Limits and malformed UTF-8 return 2, input/open/close host
failures 3, allocation failure 4, signal/output failure 5, and unexpected
internal failures 6. Whole collection, validation, owner retirement and the
owned-file close attempt precede stdout. The complete small report uses caller
storage; output has 64 attempts and diagnostics eight, including interruptions.

| Group | Cases | Scope |
| --- | ---: | --- |
| model | 38 | Binary stdin/all byte values/NUL, strict Unicode scalars including noncharacters, CR/LF, 1023/1024/1025 and growth boundaries, split UTF-8 of widths 2/3/4, actual files/raw non-UTF8 and 4095-byte paths, literal flags/minus, symlinks and exact 1 MiB |
| rejection | 24 | Stray continuations, overlong/invalid leads, surrogate/out-of-range scalars, truncation and bad continuation bytes including split sequences, final malformed cap byte, and oversized stdin/files in both modes |
| cli | 22 | Arity/mode/case/whitespace/non-ASCII, path length, sole help and no input/open before preflight completes |
| io | 27 | Four selected reached ENOMEM sites, directory stdin/file, missing/open errors, input/output EINTR and EIO, EOF/error precedence, close errors/primary preservation, real prefix, signal failure and attempt bounds |

The exact-cap binary trace must end with a real one-byte request returning
zero; the over-cap trace must consume one extra byte and reject. Malformed
text is collected through EOF before its UTF-8 diagnostic, while an injected
failure on that EOF call returns input status 3 first. Valid sequences split
at each interior position of widths 2, 3 and 4 are read from regular files
across the 1024-byte request boundary.

Full selected traces match successful mappings with explicit releases at the
same address and requested length, permitting address reuse after release.
They require read-only open, one close attempt for each successful open, no
seek or other allocation services, and no owned mapping/file remaining before
stdout or a diagnostic. A failed close is an observed explicit attempt; the
process cleans up any still-open kernel descriptor on exit. No broad descriptor
lifetime or leak-freedom claim follows.

The baseline checks argv retirement after open and before collection, geometric
input growth before reads, and no allocation after EOF for text adoption or
formatting. Four selected mmap failures cover both argv owners, initial input
storage and a later growth request. Each must occur at matching baseline
arguments and ordinal, preserve previously confirmed read progress, release
obtained owners and publish nothing. These are selected sites, not every
allocation or every possible failure.

Actual directory input and closed output exercise EISDIR and EPIPE. Injected
EINTR must retry reads/writes to exact results; open and close are not retried.
Close failure after otherwise successful input returns 3; invalid text and
allocation failures retain primary 2/4 even with a close error. A regular
stdout file under `RLIMIT_FSIZE=10`, with SIGXFSZ ignored, tests a genuine
ten-byte output prefix and status 5. A bounded host Python probe separately
confirmed EFBIG after reaching that file-size limit. This prefix case is untraced; the
separate traced output failures establish the selected cleanup observations.
No successful transfer count or artificial app segmentation is introduced.
Compact summaries separately check 8192 read interruptions returning 2, and
64 output interruptions plus one diagnostic returning 5; those summaries do
not provide a complete release ledger.

The driver compiles once per libtest process and requires an actual little-
endian ELF64 x86-64 executable, including the shared strict jump gate. The
standalone oracle also rejects non-ELF input. Each native child has a 15-second
deadline; each registered group has 85 seconds. Exact command/input/output/
status and selected syscall evidence are retained.

```sh
python3 -B tests/fixtures/stdlib_execution/input_stats/oracle.py controls
python3 -B tests/fixtures/stdlib_execution/input_stats/oracle.py model PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/input_stats/oracle.py rejection PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/input_stats/oracle.py cli PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/input_stats/oracle.py io PATH_TO_ELF
```

## Acceptance

All four registered tests passed on the first attempt in 8.88 seconds:
**111 native Linux x86_64 cases**, no failures or filtered tests. The separate
Rust build took 1.83 seconds. The GPU compiler produced the strict-admitted
ELF64 program; execution was on the CPU. Receipt:
`target/stdlib-work/owned-input-stats-first.log`.

| Group | Cases | Evidence |
| --- | ---: | --- |
| model | 38 | `/tmp/input-stats-model-3c5c90n3` |
| rejection | 24 | `/tmp/input-stats-rejection-9im4n4sw` |
| cli | 22 | `/tmp/input-stats-cli-h0uyl4p1` |
| io | 27 | `/tmp/input-stats-io-hvojnfgw` |

Accepted identities (SHA-256):

- Application: `ab12d3635045c7f8003c8fb4e228ebd28888aaddf2e06088dc66251ad864aa18`.
- Oracle: `6ca840c0761c10bdc1ff1683247e8cee72ce6a7e1c571026938dc836f740b17c`.
- `alloc::io`: `2ed4586e3f33702e10c935d0e68b618fdc65ca6260d1b764cc893e7af9ee7c86`.
- `alloc::string`: `2196e427ba4091eafc7de4c13ae66c640027fa1f3ad1b5c63b2c53b2348d6282`.

The inspected file/text baseline releases its 80-byte and 46-byte argv
mappings after open, then grows input through 1024/2048/4096/8192 bytes.
After 5001 bytes and EOF, it releases the final input owner, closes the file
and writes exactly `bytes=5001\nscalars=4001\nlf=1000\n`. There is no allocation
after EOF. The selected ENOMEM cases reach mmap ordinals 1, 2, 3 and 6 with
matching baseline arguments. The late failure follows exactly 4096 confirmed
input bytes; its failed 8192-byte reservation delegates no additional read.
Each selected trace releases all successfully obtained owners, closes any
opened file once and publishes no data.

The maximum-input trace ends in `read(0, ..., 1) = 0`; the oversized input
trace ends in a real one-byte result before status 2. Invalid text observes
EOF before status 2; an EIO injected into that same would-be EOF returns 3
instead. Invalid text plus close EIO preserves 2, and growth ENOMEM plus close
EIO preserves 4. Injected close EIO/EINTR is a skipped syscall returning the
selected error: the trace establishes one explicit close attempt, with the
still-open kernel descriptor subsequently reclaimed on process exit.

The untraced regular-output limit case produces exactly the real ten-byte
prefix `bytes=5001` and status 5; it does not supply an errno or owner-release
trace. The separate host probe observed EFBIG after the same prefix bound.
Other full traces cover actual EISDIR/EPIPE, retrying read/write EINTR,
read/output EIO, silent signal failure and explicit cleanup before diagnostics.
Compact summaries separately show 8192 interrupted reads, or 64 interrupted
writes plus one diagnostic; their scope is attempt counts, not a full release
ledger.

CPU controls passed before admission for literal binary/Unicode results,
exact help/diagnostic lengths, malformed references, corpus counts and
deliberately missing owner/close retirement. Driver hashes are omitted because
root formats Rust drivers after runtime acceptance; production and oracle
identities above are unchanged.

Argument-host failure, internal-error injection, arbitrary provider behavior,
exhaustive allocation/host faults, automatic lifetime enforcement, formal
verification and GPU device execution remain unclaimed.
