# Concatenated byte-reader application fixture

`concat_bytes --limit N FIRST SECOND` opens two files, chains their readers,
limits the concatenation, buffers it and stages the result before stdout.
The independent output model is `(first + second)[:N]`; input files must retain
all their bytes. No Python library implementation is used by the application.

N admits 0..1048576 as 1..64 ASCII decimal digits, including leading zeros.
`-n`, `--limit=N`, attached short arguments, intermixed operands and `--` use
the canonical CLI parser. Paths are nonempty raw byte strings of at most
4095 bytes; `-` is a literal filename and UTF-8 is not required. Duplicate
options, malformed limits, extra/missing operands and snapshot limits reject
before file opens. Help waives required operands/limit while validating those
supplied; it performs no open or read. Captured argv is bounded to 16 arguments
and 8192 bytes. The fixed help has 907 bytes and the error diagnostic 31 bytes.

Early EOF succeeds. N=0 still opens both files and allocates the 4096-byte
buffer but performs no file reads or stdout writes. The buffered composition
spends at most 16384 collection calls and stages at most N bytes; data output
permits 4096 attempts. Interrupted operations spend attempts. These are work
and byte bounds, not elapsed-time guarantees.

## Independent corpus

| Group | Native process cases | Scope |
| --- | ---: | --- |
| model | 29 | Empty/short/binary inputs, all byte values, split UTF-8 bytes without decoding, quotas within/across files, 16 seeded pairs, Unicode/non-UTF-8 paths, two independent opens of one file, symlinks and literal `-` |
| limits | 12 | N=0/1/1023/1024/1025/4095/4096/4097; byte from an empty-first handoff; exact 1 MiB across files, first-only truncation and early EOF |
| cli | 45 | Missing/extra operands, duplicate/unknown options, invalid numeric spelling/range/token length, path lengths, argument snapshot bounds, validated help and short/long/intermixed forms |
| io | 29 | One successful baseline, five reached allocation failures, both opens, both source reads and first EOF, read/write retries, two close errors, failure precedence, actual EPIPE, confirmed stdout prefix, attempt ceilings, signal failure and real missing/directory paths |

The fixed random seed is `0xC0CA7B17`. Every normal process uses two real
files and compares exact stdout to independent concatenation/slicing; all
created regular input files are compared after execution to prove observed
preservation. Large cases use deterministic byte patterns with different
salts for the two files. Exact comparisons distinguish reversed inputs,
over-read publication, truncation and corrupted bytes.

## Request and ownership evidence

Full traces observe openat, close, read, write, mmap, munmap and signal setup.
Every successful mmap must have a matching explicit munmap at the same address
and requested extent; address reuse after release is allowed. Unexpected
allocation services reject. Opens must be read-only and may not create,
truncate or append. No stdin reads or borrowed descriptor closes are allowed.

Every data read must address one of the opened files with a positive count
bounded by both 4096 and the remaining global quota. The second file cannot
be read before an observed first-file EOF, and the first cannot be revisited.
Only confirmed positive read counts spend the quota. Successful output must
contain exactly the confirmed read bytes. Trace checks establish that quota
zero performs no data reads and quotas inside the first file never read the
second. This application places Take beneath the buffer; it does not infer
that every arbitrary placement of a buffered reader has the same host-read
bound.

Each opened descriptor receives exactly one close attempt. Both files and the
input buffer retire before publication. The baseline also binds argv release
after the second open, then the 4096-byte input buffer, initial 1024-byte staged
reservation and late reservation to the full 12000-byte quota. Before stdout,
only the final staged-output owner may remain; diagnostics require every
allocation and file owner to be retired.

The five selected ENOMEM sites are the two argv allocations, the input buffer,
initial staging and late staging. They are discovered from the single counted
successful baseline, using phase order and extents rather than guessed mmap
ordinals. A fault must reach exactly the baseline's mmap argument prefix, be
marked as injected ENOMEM, make no later allocation, publish no bytes and
release every successful allocation. The baseline uses fixed path operands
for all fault cases, so argv allocation extents remain comparable. These
selected faults do not claim every possible allocator/provider failure.

Injected read and write errors occur at real syscall boundaries; positive
transfer counts are never substituted. A genuine first 1024-byte stdout write
followed by EIO must retain exactly that prefix, return status 5 and release
staged storage before the diagnostic. A real closed stdout pipe exercises
EPIPE. Read EIO and successful-collection close errors suppress publication.
The allocation-plus-close case preserves allocation status 4 over secondary
cleanup failure.

**Injected close errors are scoped to attempted cleanup.** The library
invalidates a File owner before one close attempt and does not retry. Strace
error substitution skips the kernel close, so those cases establish status,
no repeated descriptor use and no publication; they do not establish successful
kernel descriptor release. Ordinary paths require successful close results.
The child process ending handles any descriptor left by the skipped syscall.

Compact strace summaries separately check 16384 read EINTR attempts, or 4096
write EINTR attempts followed by one successful diagnostic. They establish
attempt counts, not full owner-ledger evidence. Other cases retain full traces.

## Running and current acceptance

```sh
python3 -B tests/fixtures/stdlib_execution/concat_bytes/oracle.py controls
python3 -B tests/fixtures/stdlib_execution/concat_bytes/oracle.py model PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/concat_bytes/oracle.py limits PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/concat_bytes/oracle.py cli PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/concat_bytes/oracle.py io PATH_TO_ELF
```

The Rust driver requires an actual little-endian ELF64 x86-64 executable and
the shared jump gate. The standalone oracle independently rejects non-ELF
inputs. Each native child has a 20-second deadline and each registered group
85 seconds. Commands, traces, stdout, stderr, statuses and input files remain
in the reported evidence directory.

The combined application receipt `target/stdlib-work/io-adapters-app-first.log`
passed **all four Rust tests and 115 native process cases** in 10.13 seconds,
with a separate 1.75-second Rust build. There were zero failed or filtered
tests. This is one combined four-test receipt, not four separately timed runs.
The GPU compiler produced the accepted x86-64 ELF and execution was on the CPU.

| Accepted group | Cases | Evidence directory |
| --- | ---: | --- |
| CLI | 45 | `/tmp/concat-bytes-cli-cfk544kv` |
| I/O | 29 | `/tmp/concat-bytes-io-tvu6al17` |
| Model | 29 | `/tmp/concat-bytes-model-7n8_yds9` |
| Limits | 12 | `/tmp/concat-bytes-limits-wo9sbb4_` |

Accepted identities (SHA-256):

- Application: `26933ffcd7c4cdd1bc0d120d6fa1e32ab4f0b70d47df045dbacd9a920831bba3`.
- Oracle: `d0313ba42cb38d487129b79a8b3752aae4efc6f19f47c2cd1d765f7dbadc1c03`.
- `core::io`: `6d3a6046d72ee3e36249744660a48f6fd4800f9c89e7056ed77fd598a0f3b643`.

The inspected baseline confirmed exactly 12000 input and stdout bytes. Its
eight mappings had extents 160, 97, 4096, 1024, 2048, 4096, 8192 and 12000
bytes; all had matching explicit releases. The two opened descriptors closed
successfully in second-then-first order. The selected reached ENOMEM sites
were ordinals 1, 2, 3, 4 and 8, as discovered from that baseline. Each failure
matched its mmap argument prefix, returned status 4 without stdout and released
all acquired allocations. The output-prefix case retained exactly 1024 genuine
bytes, then observed second-write EIO and a 31-byte diagnostic after cleanup.
These details retain the skipped-close and compact-summary limitations above.

Host-only controls pass for literal concatenation, corruption distinctions,
all three generated corpus counts and owner-ledger rejection of missing
releases or borrowed descriptor closes. They do not add cases to the 115
native-process total. Standalone build/examples are a separate application-guide
scope. GPU device execution, other targets, formal verification, automatic
ownership and exhaustive provider/host failures remain unclaimed. The driver
hash is omitted because root formats Rust drivers after runtime acceptance.
