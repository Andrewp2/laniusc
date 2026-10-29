# Owned line report application fixture

CLI is `line_report [--text] [--max-bytes N] [--help]`, with `-t`, `-m N`
and `-h` aliases. N is unsigned ASCII decimal, 1..64 token bytes, with leading
zeros permitted; its value is 0..1048576, default 65536. Duplicate options
and operands reject. Help validates otherwise supplied options and bypasses
stdin. Captured argv is limited to 16 arguments and 1024 total bytes.

Input records include LF and any preceding CR. A final nonempty unterminated
record is retained; empty EOF adds no record. NUL is data, and binary mode
admits every byte. Text mode requires strict UTF-8 and counts every Unicode
scalar, including CR/LF/NUL and noncharacters. Output is fully quoted CRLF CSV
`record,bytes,scalars,ending`: positions start at zero, binary scalar fields
are empty and endings are `lf`/`eof`. Empty input emits only the 37-byte header.

The independent Python model splits only at byte LF, restores each delimiter,
retains a nonempty tail and counts strict-decoded Unicode scalars. It uses
neither a buffered-provider model nor the production helper implementation.
Literal CRLF/NUL/invalid-binary output controls anchor the generated expected
CSV. Ordinary collection and whole-input acceptance are separate fixtures.

| Group | Cases | Scope |
| --- | ---: | --- |
| model | 43 | Empty/LF/CRLF/NUL/unterminated input, all byte values, Unicode, 200 coalesced records in both modes, 1023/1024/1025 bytes, split UTF-8, zero/one/exact/default/maximum record caps, 16384 records and 4 MiB logical input |
| rejection | 33 | Malformed UTF-8 with LF/EOF/later records, pending data at zero cap, delimiter-inclusive record limits, excess record count, aggregate cap and no overlong-record drain |
| cli | 34 | Arity/operands/options/duplicates, numeric spelling/range/token and snapshot caps, valid help bypass, short clusters and attached required values |
| quota | 2 | Long-retry success within quota and shared fill/consume budget exhaustion after two coalesced records |
| io | 19 | Two baselines, six selected reached ENOMEM sites, actual input/output host errors, EINTR, required EOF/UTF-8 precedence, real output prefix, signal failure and output attempts |

## Bounds and successful resumption

The app uses the public owned `read_until`/`read_line` functions over one
1024-byte canonical buffered stdin owner. The configured byte bound includes
LF. Logical input is limited to 4 MiB, nonempty records to 16384 and direct
fill/consume delegations to 131072 across all records. Each next collection
receives the remaining aggregate bytes and calls. An empty fill at an exact
bound succeeds; nonempty pending data fails without consumption or draining.
Buffered host read-ahead is separate from acknowledged logical consumption.

Coalesced 400-byte controls require 200 correct records with exactly one
positive host read and one EOF read. Subsequent records must use the pending
buffer rather than lose or replay bytes. Four 1 MiB LF-ended records admit
the aggregate limit and observe actual EOF. The excess-input trace rejects
after at most one 1024-byte read-ahead beyond that logical boundary, without
draining the remaining source. A four-byte record cap likewise rejects an
overlong line after one actual 1024-byte read. Error recovery/resumption is not
exposed by this app: any failure discards private buffered pending data and
aborts. Direct helper tests separately cover retained/unacknowledged owners.

The two quota controls send `LF LF` through one positive buffered read. The
first injects 65533 initial read interruptions, then allows the real two-byte
read and EOF. It must succeed with 65535 actual reads and 65533 errors. Its
65538 public fill/consume calls are within the shared budget; this is not an
exact-131072 success witness.

The second allows the first two-byte read, then injects every later read with
`when=2+`. The two records cost four fill/consume calls, leaving 131068 public
calls for interrupted EOF fills. It must return 2 with empty stdout after
131069 actual reads and 131068 errors. Resetting the quota for the EOF helper
would permit four extra interrupted calls, violating the exact count. These
supported schedules keep the production quota unchanged. No positive transfer
count is fabricated. Summary traces establish attempts, not a full owner ledger.

## Ownership and failure scope

CLI owners retire before reader construction. Each collected record owner
retires before staging its summary. Before stdout, the reusable CSV record,
buffered reader and their allocations retire; only output staging remains.
Full selected traces match every successful mapping with an explicit release
at the same address/requested length and permit address reuse after release.
They reject borrowed descriptor closes and other allocation services; a
diagnostic requires every owned mapping already retired.

Six selected mmap failures cover both argv owners, reader backing, the first
owned record, output growth and late growth of a long owned record. Each
must be reached at its baseline ordinal/arguments, return 4, release obtained
owners and publish nothing. The long-record failure may follow provider
read-ahead; it makes no rollback or restoration promise. These are selected
sites, not all allocations or all possible errors.

Actual directory stdin returns 3, and actual closed data/help stdout returns
5. Read/write EINTR must retry to exact output; input EIO on a later read or
required EOF publishes nothing. An input error before terminal validation
precedes malformed UTF-8. The output-prefix control lets a real 1024-byte
write succeed, injects EIO into the second write and requires exactly that
prefix with status 5 and cleanup before the diagnostic. The app has no
artificial write segmentation. A separate compact summary checks 2048 output
interruptions plus one successful diagnostic; it does not provide the full
release ledger. Signal failure is silent before argument capture.

The driver compiles once per libtest process, requires actual little-endian
ELF64 x86-64 output and uses the shared strict jump gate. The standalone oracle
also rejects non-ELF files. Every native child has a 15-second deadline and
each group 85 seconds. Exact command/input/output/status and selected traces
are retained. Root alone runs compiler/Cargo/native commands.

```sh
python3 -B tests/fixtures/stdlib_foundation/line_report/oracle.py controls
python3 -B tests/fixtures/stdlib_foundation/line_report/oracle.py model PATH_TO_ELF
python3 -B tests/fixtures/stdlib_foundation/line_report/oracle.py rejection PATH_TO_ELF
python3 -B tests/fixtures/stdlib_foundation/line_report/oracle.py cli PATH_TO_ELF
python3 -B tests/fixtures/stdlib_foundation/line_report/oracle.py quota PATH_TO_ELF
python3 -B tests/fixtures/stdlib_foundation/line_report/oracle.py io PATH_TO_ELF
```

## Acceptance

The first registered target run passed model 43, rejection 33, CLI 34 and
I/O 19: **129 native cases** in an aggregate 12.26 seconds. Its quota test
stopped before launching the ELF because strace 6.8 rejects the original
finite injection range `when=1..131067`. This was a test-tool schedule failure,
not an application failure. The registered result was four passed and one
failed; receipt `target/stdlib-work/owned-delimited-line-report-first.log`.
The original executed oracle was
`1beb38be5531ef1a14b4f5bd49645c06130cf838d7237993ab7b1cfc91127fa2`;
application `8aec64bbc704ef643e88649c2cab5be55057fb245622ba005b2396a5f53cd810`.

Only the two quota schedules were repaired, using a bounded finite range
and `when=2+`. The retry passed one registered test in 12.82 seconds, with
four filtered tests and zero failures; receipt
`target/stdlib-work/owned-delimited-line-report-quota-retry.log`. Both amended
cases executed native behavior and their exact compact count assertions.
Together, the receipts accept **all 131 distinct native Linux x86_64 cases**.
This is not a fresh five-test all-pass target: the original full target remains
the mixed four-pass/one-tool-failure receipt described above.

| Group | Cases | Evidence |
| --- | ---: | --- |
| model | 43 | `/tmp/line-report-model-1lo5t3v1` |
| rejection | 33 | `/tmp/line-report-rejection-vustuoni` |
| cli | 34 | `/tmp/line-report-cli-sb25ngzx` |
| io | 19 | `/tmp/line-report-io-xmqpm0k0` |
| amended quota | 2 | `/tmp/line-report-quota-lrxi4u61` |

Accepted identities (SHA-256):

- Application, unchanged across receipts: `8aec64bbc704ef643e88649c2cab5be55057fb245622ba005b2396a5f53cd810`.
- Original oracle for the four accepted groups: `1beb38be5531ef1a14b4f5bd49645c06130cf838d7237993ab7b1cfc91127fa2`.
- Amended oracle for quota acceptance: `1f12d18ca4a428584002bc9b31742bb1a782a282f7e995a9d1a0b04b37ead5ef`.
- `alloc::io`: `9eeb63f40cc582d192afa43e5b2e65ffa209bbfc63d6893a3f0af155377b7392`.
- `alloc::buffered`: `08212669340df04f8a6d61d1e17a8af13c7c1d730e01b30ec1f662e3fd302834`.
- `alloc::string`: `2196e427ba4091eafc7de4c13ae66c640027fa1f3ad1b5c63b2c53b2348d6282`.

The inspected baseline releases its 40-byte/6-byte argv mappings before the
1024-byte reader allocation. It admits 200 records from 4200 input bytes,
observes EOF and produces 4327 output bytes. The CSV record's 24-byte/64-byte
owners and the reader retire before stdout. Only the 4736-byte output mapping
remains through publication and is released afterward.

Five selected baseline allocation failures reach ordinals 1/2/3/9/128:
argv owners, reader, first 21-byte owned record and 4736-byte output growth.
The sixth selected site is an 8192-byte long-record growth request in a
separate baseline. It fails after 4098 bytes have been read ahead; the prior
4096-byte record backing and reader/header staging owners are released before
the diagnostic. Every selected fault returns 4 and publishes nothing. This
does not imply that the buffered extra two bytes were acknowledged consumed
or restored to the host stream, and it is not an exhaustive fault campaign.

The inspected prefix case has a genuine 1024-byte write, second-write EIO,
status 5, then output release before the diagnostic. An EIO on the required
EOF returns 3 without publishing previously staged rows. Exact logical input
ends with a real EOF read; excess input ends after one 1024-byte read-ahead,
without a drain. Coalesced cases retain 200 rows from one 400-byte positive
read and one EOF. Actual EISDIR/EPIPE, input/output EINTR, silent signal failure
and the 2048-output-attempt summary also passed.

The amended success schedule records exactly 65535 actual reads/65533 errors
and the correct two-row CSV, status 0. The shared-budget failure records
131069 reads/131068 errors, empty stdout and status 2. The first is explicitly
within budget; the second demonstrates the boundary after four public
fill/consume calls for two records. Their summary traces establish counts
separately from selected full ownership ledgers.

The GPU compiler produced strict-admitted ELF64 programs and execution was
on the CPU. The four non-quota group bodies and production source remained
unchanged for the retry. Root formatted only Rust drivers after acceptance;
driver hashes are omitted. No additional runtime rerun is claimed.

Bounded CPU controls pass for literal byte/text outputs, record endings,
record/aggregate/UTF-8 references, corrected quota arithmetic, exact help/header/
diagnostic lengths, corpus counts and a deliberately missing owner release.
Argument-host failure, internal-error injection, arbitrary broken providers,
exhaustive faults, automatic lifetime enforcement, user GPU execution and formal
proofs remain unclaimed.
