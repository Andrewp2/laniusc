# Report binary or UTF-8 line sizes

`sample_programs/library/line_report.lani` summarizes LF-separated stdin records
as fully quoted CRLF CSV. It uses public owned delimiter and line input over
the canonical buffered reader. Binary mode counts bytes; text mode also
validates UTF-8 and counts Unicode scalars.

The implementation has passed 131 native cases. The standalone build and
both exact examples below have also passed separately from the registered
runtime tests.

## Build and use

With the compiler binary built, run from the repository root:

```sh
mkdir -p target/stdlib-work
timeout --kill-after=2s 100s flock -w 95 target/stdlib-work/library-gpu.lock \
  target/stdlib-build/debug/laniusc --stdlib-root stdlib --source-root extended \
  --emit x86_64 sample_programs/library/line_report.lani \
  -o target/stdlib-work/line_report
printf 'A\n\nB' | target/stdlib-work/line_report
```

Expected output, with CRLF after every row:

```csv
"record","bytes","scalars","ending"
"0","2","","lf"
"1","1","","lf"
"2","1","","eof"
```

Text mode preserves CR, LF and NUL while counting each as a scalar:

```sh
printf 'A\303\251\r\n\000Z' | target/stdlib-work/line_report --text
```

Expected output:

```csv
"record","bytes","scalars","ending"
"0","5","4","lf"
"1","2","2","eof"
```

## CLI and record semantics

`line_report [--text] [--max-bytes N] [--help]` accepts these options:

| Option | Meaning |
| --- | --- |
| `--text`, `-t` | Require strict UTF-8 and populate scalar counts |
| `--max-bytes N`, `-m N` | Maximum bytes in one record, including LF; default 65536 |
| `--help`, `-h` | Show help without reading stdin |

N is 0..1048576, written as 1..64 ASCII decimal digits. Leading zeros are
allowed. Signs, whitespace, prefixes, non-ASCII digits and overflow fail.
The existing `ext::cli` parser accepts attached values, exact long names,
short groups and a `--` terminator. Operands and duplicate options, including
aliases or repeated help, fail. Help may combine with otherwise valid options;
it does not waive validation. Argument capture admits 16 arguments and 1024
total bytes. Argument storage is destroyed before input or help publication.

Every record includes its first LF. A preceding CR remains part of the record;
there is no trimming, newline conversion or BOM removal. Binary mode accepts
every byte, including NUL and invalid UTF-8, and leaves the scalar column empty.
Text mode counts Unicode scalars rather than grapheme clusters; CR, LF and NUL
each count once. Noncharacters remain valid Unicode scalars.

Positions start at zero. A final nonempty unterminated record has ending `eof`.
LF-terminated records have ending `lf`, including a record containing only LF.
Empty EOF adds no record, so trailing LF creates no phantom row and empty
stdin prints only the header. The output header is always
`record,bytes,scalars,ending`. Canonical CSV writing quotes every field and
terminates every row with CRLF. Numbers use canonical unsigned decimal.

## Collection, limits and cleanup

Each record is collected by public `alloc::io::read_until` with delimiter LF,
or by `alloc::io::read_line` in text mode. Both operate directly on one
`alloc::buffered::Reader<std::stream::Descriptor>` with 1024-byte backing.
There is no second collection loop or private delimiter scanner.

The program passes the actual remaining fill/consume quota into every owned
collector. Each record receives the smaller of the configured record cap and
the remaining logical input allowance. After 16384 nonempty records, a
zero-byte collection may establish empty EOF but rejects further input.
An exact-fit unterminated record similarly needs an EOF observation. A zero
record cap therefore accepts only empty stdin.

The owned helper includes the delimiter in its byte cap. Its overflow check
does not consume or drain an excess byte. A provider fill may already have
read ahead into the 1024-byte buffer; those pending bytes are discarded when
the program rejects the input. The 4 MiB limit applies to acknowledged logical
record bytes, not a physical host-read total. A terminal nonempty EOF record
ends collection immediately because EOF has already been observed.

UTF-8 is checked only after LF or EOF. A source, call, storage or byte-limit
failure in an incomplete record takes precedence over malformed text in that
prefix. Any retained failure owner is explicitly destroyed; no partial record
is resumed or added to the report. Failure abandons all previously staged rows.

Successful Vec/String record owners are destroyed after obtaining their
counts and before staging that row. The canonical CSV Record is reused, and
`alloc::io::Buffer` holds the complete output. The CSV Record and buffered
provider are released before the first data stdout write. Only the staged
output owner remains through publication and is destroyed afterward on
success or failure. Stdin/stdout/stderr descriptors stay borrowed and are
never closed by the program.

| Resource | Bound |
| --- | ---: |
| Record bytes, including LF | Configured 0..1048576; default 65536 |
| Total logical input | 4194304 bytes |
| Nonempty records | 16384 |
| Fill and consume delegations, shared across all records | 131072 total |
| Buffered reader backing | 1024 bytes |
| Staged output | 1048576 bytes |
| Private CSV writer calls | 32768 total |
| Data stdout attempts | 2048 total |
| Help stdout attempts | 64 total |
| Diagnostic stderr attempts | At most 8 |

Fill and consume each spend one public input operation, including EOF,
Interrupted and errors. This differs from the provider's internal Read calls.
The current buffered provider delegates at most one Read per fill; pending
buffered bytes need no host read. These quotas impose no wall-clock timeout
on blocking I/O.

At most 16385 rows, including the header, are staged. Each row is smaller than
1024 bytes, so the private writer quota admits every bounded report without
interruptions. A conservative 35-byte maximum data row also fits the 1 MiB
output cap. The current native Descriptor transfers at most 1024 host bytes
per write, so bounded output fits its 2048-attempt budget without failures.

Output advances only by confirmed positive counts. Interrupted retries spend
attempts; zero, invalid counts, other errors or exhaustion stop without replay.
An output failure may leave a confirmed prefix of the fully prepared report.
No rollback or atomic publication is claimed.

## Status and acceptance

| Exit | Meaning |
| ---: | --- |
| 0 | Complete report or help written |
| 2 | Invalid CLI or UTF-8, record/input/count/call or output-staging limit |
| 3 | Input I/O or argument-capture host failure |
| 4 | Argument, provider, record, CSV or staging allocation failure |
| 5 | Data/help output or SIGPIPE-policy failure |
| 6 | Unexpected input/storage/provider/formatting contract failure |

SIGPIPE is ignored before argument capture. Setup failure returns 5 silently.
Other failures preserve their primary status and attempt the exact 30-byte
line `line_report: operation failed\n`, after owned allocations are released.
Diagnostic failure does not replace that status. Successful runs have empty
stderr. Help is exactly 823 bytes; the quoted header is 37 bytes.

All **131 distinct cases** are accepted on native Linux x86_64 CPU output
from the GPU compiler. Acceptance spans two commands:

| Receipt in `target/stdlib-work/` | Accepted scope | Runtime | Registered result |
| --- | --- | ---: | --- |
| `owned-delimited-line-report-first.log` | Model 43, rejection 33, CLI 34 and I/O 19: 129 cases | 12.26 s aggregate | 4 passed, 1 failed before ELF launch |
| `owned-delimited-line-report-quota-retry.log` | Corrected quota group: 2 cases | 12.82 s | 1 passed, 4 filtered |

The first command's quota test never launched the executable: strace 6.8
rejected its unsupported finite injection range `when=1..131067`. This was a
test-tool schedule failure. The oracle then changed only the two quota
schedules, preserving the other four group commands and expectations. The
production source was unchanged. The original mixed result remains part of
the receipt; there is no one-shot five-test pass claim.

Retained evidence is in `/tmp/line-report-model-1lo5t3v1`,
`/tmp/line-report-rejection-vustuoni`, `/tmp/line-report-cli-sb25ngzx`,
`/tmp/line-report-io-xmqpm0k0` and `/tmp/line-report-quota-lrxi4u61`.
The independent model splits byte LF records, restores delimiters and uses
strict Python UTF-8 scalar counts, without reproducing the buffered-provider
engine. Executed cases include coalesced records, CR/LF/NUL, invalid binary,
split UTF-8, empty/final-unterminated records, configured byte bounds, 16384
records and exact 4 MiB logical input. Cap rejection observes buffered pending
data without draining an overlong source; read-ahead is distinct from logical
consumption.

The corrected success quota control tolerates 65533 initial interrupted reads,
then reads two coalesced LF records and EOF: 65535 host reads and 65538 public
operations. It is within quota, not an exact-131072 success witness. The
exhaustion control allows one genuine two-byte read, then interrupts every
later host read. The two records spend four fill/consume calls, leaving
131068 interrupted EOF fills. Its exact 131069 host reads and status 2 verify
that the allowance is shared across records. These compact summaries establish
counts, separately from complete selected release traces.

Six selected, reached allocation failures cover both argv owners, reader
backing, the first owned record, output growth and late growth of a long
record. Each returns 4 with empty stdout and matching explicit releases of
observed successful mappings. Baseline traces verify record cleanup and
provider/CSV cleanup before publication; only staging remains live at stdout.
Actual directory input, closed data/help stdout, read/write interruptions,
later-read and required-EOF failures also pass. A genuine first 1024-byte
stdout transfer followed by second-write EIO leaves exactly that prefix,
returns 5 and releases staging before the diagnostic. A separate compact
summary establishes the 2048-output-attempt limit. This is finite observed
fault coverage, not a proof of lifetime safety or exhaustive cleanup.

Accepted identities (SHA-256):

- Application: `8aec64bbc704ef643e88649c2cab5be55057fb245622ba005b2396a5f53cd810`.
- Original oracle, four non-quota groups: `1beb38be5531ef1a14b4f5bd49645c06130cf838d7237993ab7b1cfc91127fa2`.
- Amended oracle, quota retry: `1f12d18ca4a428584002bc9b31742bb1a782a282f7e995a9d1a0b04b37ead5ef`.
- `alloc::io`: `9eeb63f40cc582d192afa43e5b2e65ffa209bbfc63d6893a3f0af155377b7392`.
- `alloc::buffered`: `08212669340df04f8a6d61d1e17a8af13c7c1d730e01b30ec1f662e3fd302834`.

Rust driver formatting followed runtime acceptance without a behavior change.
The [fixture guide](../tests/fixtures/stdlib_foundation/line_report/README.md)
records commands, independent controls and finite fault profiles. Static
literal byte-count and final-newline checks also pass. The exact standalone
compile above exited 0 with a silent compiler
(`target/stdlib-work/owned-delimited-line-report-build-command.log`). Both
documented pipelines exited 0 and matched their literal CRLF output: 89 bytes
in `target/stdlib-work/owned-delimited-line-report-example-binary.csv` and
74 bytes in `target/stdlib-work/owned-delimited-line-report-example-text.csv`.
These examples overlap the functional corpus and add no distinct case count.

Argument-capture host failures, internal-error injection, arbitrary broken
providers, user-program GPU execution, other targets, automatic lifetime
enforcement, alias safety, exhaustive failure coverage, leak freedom and formal
verification require separate evidence. Production is entirely Lanius and
adds no compiler or host service changes.
