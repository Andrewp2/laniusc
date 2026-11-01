# Summarize complete byte or text input

`sample_programs/library/input_stats.lani` collects a bounded input through the
public owned readers and writes a small ASCII summary. Its CLI is exactly
`input_stats bytes|text [PATH|-]`, or sole `--help` / `-h`.

## Build and use

With the compiler binary built, run from the repository root. The standalone
build and all three examples below passed. The named-file example uses
`notes.txt` containing the same UTF-8 bytes as the preceding stdin example.

```sh
mkdir -p target/stdlib-work
timeout --kill-after=2s 100s flock -w 95 target/stdlib-work/library-gpu.lock \
  target/stdlib-build/debug/laniusc --stdlib-root stdlib --emit x86_64 \
  sample_programs/library/input_stats.lani -o target/stdlib-work/input_stats
printf 'A\000B\n' | target/stdlib-work/input_stats bytes
printf 'A\303\251\n' | target/stdlib-work/input_stats text -
target/stdlib-work/input_stats text notes.txt
```

The first example prints exactly:

```text
bytes=4
nul=1
```

The second example supplies `A`, `é` and LF as UTF-8 and prints exactly:

```text
bytes=4
scalars=3
lf=1
```

Every record ends with LF. Counts use canonical unsigned decimal without
padding or a leading plus. There is no header, path echo or extra blank line.

## Modes and CLI policy

Byte mode reports the number of collected bytes and bytes equal to zero. It
accepts arbitrary binary input without UTF-8 validation.

Text mode requires complete strict UTF-8. It reports byte length, Unicode
scalar count and the number of LF bytes (`0x0A`). NUL is an ordinary scalar;
combining characters remain separate scalars and are not grapheme counts.
No newline normalization occurs: CR is unchanged, CRLF contributes one LF,
and a final unterminated record does not add an LF. Empty input succeeds with
all reported counts zero.

Omitted PATH or exact `-` selects borrowed stdin. Every other second operand
is a literal path, including names that begin with `-`; help is recognized
only as the sole argument. Use `./-` to open a file named `-`. Paths admit
1..4095 raw bytes without NUL and need not be UTF-8. The program preserves their
spelling and uses the current directory for relative lookup. Capture admits
two arguments and at most 4100 bytes, excluding terminating NULs. Mode names
are exact and case-sensitive; missing modes, empty paths and extra operands
are errors before opening or reading input.

Named files use `std::file_ops::open(path, options())`: existing read-only
access with CLOEXEC, no creation, truncation or append. The existing policy
follows symlinks. Open is attempted once. Successful open supplies one owned
File; stdin remains borrowed and is never closed.

## Public collection and ownership

`alloc::io::read_to_end<R>` supplies byte mode, while
`alloc::io::read_to_string<R>` supplies text mode. Both receive
`ReadLimits { max_bytes:1048576, max_calls:8192 }` over a borrowed File or stdin
Descriptor. The application adds no private read loop or UTF-8 parser.

Collection requires actual EOF on a nonempty read request. At the exact byte
cap the public helper issues its one-byte probe: EOF succeeds, a confirmed
extra byte returns ByteLimit, and an error remains an input error. Every
delegated Read invocation spends one call, including Interrupted, EOF and the
probe. The helper reserves storage before ordinary reads, grows geometrically
within the cap and retains admitted bytes on failure. Even empty input with a
positive byte limit can require a reservation before observing EOF.

Text collection observes EOF before validating UTF-8 and adopts the collected
Vec backing without a second text allocation or byte copy. Thus input I/O,
byte/call limits and storage failures take precedence over invalid UTF-8. A
multibyte scalar split across reads is ordinary input; malformed bytes are
never replaced or counted as successful text.

Arguments remain live only through path validation/open. Their owner is
destroyed after the open attempt and before collection. Stdin and help paths
destroy argument storage before reading or writing. No argument View is used
after that cleanup.

Successful collection produces one Vec or String owner. The application
counts its contents, explicitly destroys it and returns plain scalar Counts.
On failure it classifies the public cause and explicitly destroys the
ReadFailure, including its retained prefix. The consumed over-cap probe byte
is discarded when this terminal CLI operation fails; the program does not
resume the stream.

For a named file, close is attempted exactly once after collection cleanup,
on both success and failure. Close is not retried on Interrupted. A close error
after successful collection returns 3 without output. An earlier collection
error preserves its primary status even when close also fails. The generic
diagnostic does not separately encode a secondary close failure.

Only after input cleanup and any file close does the program format all
records into a caller-backed 64-byte array. Byte output is at most 26 bytes;
text output at most 41. Formatting uses `core::decimal::format_u64` and creates
no output allocation. The full report is staged before stdout.

## Bounds, output and errors

| Resource | Bound |
| --- | ---: |
| Captured arguments / total bytes | 2 / 4100 |
| Named path bytes | 1..4095 |
| Collected input bytes | 1,048,576 |
| Public Read calls, including Interrupted and EOF | 8192 |
| Owned-file open / close attempts | At most one each |
| Caller output storage / maximum result bytes | 64 / 41 |
| Data or help stdout attempts, including Interrupted | 64 total |
| Diagnostic stderr attempts | At most 8 |

The counting scans are bounded by input length; reported counts fit the input
cap. The current Descriptor/File path performs at most 1024 host bytes per
read delegation. Open/close attempts are separate from the collection quota.
Attempt bounds do not impose wall-clock deadlines on host operations.

Output advances only by confirmed positive counts. Interrupted retries consume
attempts; zero, invalid counts, other errors or exhaustion stop. Output failure
can leave a confirmed report prefix without replay or rollback. Borrowed stdin,
stdout and stderr are never closed by their Descriptor adapters. Invalid CLI,
input failures, malformed text, limits, allocation failures, close failures
and formatting failures publish no report data.

| Exit | Meaning |
| ---: | --- |
| 0 | Complete report, or help written |
| 2 | Invalid CLI, invalid UTF-8, byte limit or read-call exhaustion |
| 3 | Input I/O, file open/close or argument-capture host failure |
| 4 | Argument or input allocation failure |
| 5 | Data/help stdout or SIGPIPE-policy failure |
| 6 | Unexpected input-provider, storage, formatting or internal contract failure |

SIGPIPE is ignored before argument capture. Setup failure returns 5 silently.
Other errors attempt the exact 30-byte line
`input_stats: operation failed\n`, after cleanup, using at most eight stderr
attempts. Diagnostic failure preserves the primary status. Successful runs
have no stderr output. Help is exactly 554 bytes.

## Target and acceptance

All four registered groups passed on the first runtime attempt, totaling 111
distinct native cases. The receipt is
`target/stdlib-work/owned-input-stats-first.log`: four tests passed, none
filtered, in 8.88s after a 1.83s driver build.

| Accepted group | Cases | Evidence directory |
| --- | ---: | --- |
| Model | 38 | `/tmp/input-stats-model-3c5c90n3` |
| Rejection | 24 | `/tmp/input-stats-rejection-9im4n4sw` |
| CLI | 22 | `/tmp/input-stats-cli-h0uyl4p1` |
| I/O | 27 | `/tmp/input-stats-io-hvojnfgw` |

The driver compiled through the GPU compiler, required an actual little-endian
ELF64 x86-64 executable and applied the shared strict jump gate before native
Linux x86_64 CPU execution. The documented standalone build also exited 0 on
the same application source; its receipt is
`target/stdlib-work/owned-input-stats-build-command.log`. All three documented
examples returned 0 with exact expected stdout and empty stderr: byte stdin
with A-NUL-B-LF, text stdin with UTF-8 A-é-LF, and a private temporary
`notes.txt` containing those UTF-8 bytes. These overlap the existing 111-case
corpus and add no distinct case count. GPU-device execution and other backends
remain unverified.

Executed application source SHA-256:
`ab12d3635045c7f8003c8fb4e228ebd28888aaddf2e06088dc66251ad864aa18`.
Oracle SHA-256:
`6ca840c0761c10bdc1ff1683247e8cee72ce6a7e1c571026938dc836f740b17c`.
Owned-input module SHA-256:
`2ed4586e3f33702e10c935d0e68b618fdc65ca6260d1b764cc893e7af9ee7c86`.
String module SHA-256:
`2196e427ba4091eafc7de4c13ae66c640027fa1f3ad1b5c63b2c53b2348d6282`.

The independent Python oracle constructs records from raw byte length/NUL
counts and strict Unicode decoding with scalar/LF counts. Literal controls
anchor binary and mixed Unicode expectations. Models exercise all byte values,
BOM/noncharacters, CR/LF, growth boundaries and 2/3/4-byte UTF-8 sequences split
across regular-file reads. They include exact 1 MiB input, files, symlinks,
raw non-UTF8 paths, a 4095-byte path and literal flag/minus filenames. Rejections
cover malformed and split UTF-8, a malformed final cap byte and excess input
in both modes. CLI cases check arity, spelling, capture/path bounds, sole help
and preflight before input/open.

The selected text-file baseline releases both argument mappings (80 and 46
requested bytes) after read-only CLOEXEC open and before collection. Input
grows through 1024, 2048, 4096 and 8192 requested bytes. After 5001 input bytes
and actual EOF, it releases input, successfully closes the file and writes the
exact 32-byte report `bytes=5001\nscalars=4001\nlf=1000\n`. No allocation occurs
after EOF for text adoption or formatting.

Four selected ENOMEM sites are reached at mmap ordinals 1, 2, 3 and 6, covering
both argv owners, initial input and a later growth request. Ordinal 6 fails
after exactly 4096 confirmed bytes without another read. Every case returns 4,
publishes nothing and explicitly releases successful mappings before reporting.
Full selected traces match releases by address and requested length, allow
actual address reuse only after release, and check owned-file close attempts.
These four sites do not cover every allocation or failure schedule.

Actual directory stdin/file and missing files exercise input/open failures;
closed data/help stdout exercises EPIPE. Injected read/write EINTR retries
preserve exact counts. Later read EIO and an error on the required EOF read
publish nothing; EOF I/O failure takes precedence over earlier malformed UTF-8.
Exact-cap traces observe the one-byte EOF request returning zero, while
over-cap traces consume one extra byte and reject.

Close EIO/EINTR injection observes one close attempt without retry and returns
3 after otherwise successful input. Combined invalid UTF-8/close EIO preserves
2; growth ENOMEM/close EIO preserves 4. Injection skips the kernel close syscall,
so these cases establish attempted cleanup and primary-status policy, not a
successful kernel close. Any remaining descriptor is reclaimed on process exit.

The regular-file stdout limit case produces the genuine ten-byte prefix
`bytes=5001` and status 5 under `RLIMIT_FSIZE=10` with SIGXFSZ ignored. This case
is untraced: a separate host probe establishes the short-write/EFBIG mechanism,
and separate traced output failures establish selected cleanup behavior. No
successful transfer count or artificial application segmentation is introduced.
Signal setup failure returns 5 silently. Compact summaries observe 8192 read
interruptions returning 2 and 64 output interruptions plus one diagnostic
returning 5; those summaries establish attempt counts, not full release ledgers.

Argument-capture host failure, internal-error injection and arbitrary provider
behavior were not reached. These finite cases do not establish automatic
lifetime enforcement, general alias safety, leak freedom or formal correctness.
The fixture guide is `tests/fixtures/stdlib_execution/input_stats/README.md`;
the registered driver is `tests/stdlib_input_stats_execution.rs`. With a warm
build and configured GPU, reproduce the registered acceptance using:

```sh
timeout --kill-after=2s 100s flock -w 95 target/stdlib-work/library-gpu.lock \
  env CARGO_TARGET_DIR=target/stdlib-build LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=70000 \
  cargo test --test stdlib_input_stats_execution -- --nocapture --test-threads=1
```

Production is entirely Lanius and adds no compiler, ABI or host service,
Rust/Python library implementation, JSON transport or Wasm dependency. See the
[owned-input plan](library-owned-input-plan.md) for the separate helper and
zero-copy transfer contracts.
