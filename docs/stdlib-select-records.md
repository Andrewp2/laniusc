# Buffered binary record selection

`sample_programs/library/select_records.lani` selects records from binary
stdin through the public buffered delimiter protocol:

```sh
printf 'one\ntwo\nthree\n' | select_records 10 2
```

The example writes `one\nthree\n`. The CLI is exactly
`select_records DELIMITER EVERY`, or a sole `--help` / `-h`.

Both values use the existing unsigned decimal parser: ASCII digits only,
with leading zeros allowed. DELIMITER is 0..255 and EVERY is 1..65536.
Signs, spaces, prefixes, missing/extra operands and mixed help are invalid.
Capture admits two argument values and 128 total bytes, excluding terminating
NULs; each numeric token is at most 64 bytes. Help bypasses stdin.

## Record and selection contract

DELIMITER is one arbitrary byte, including NUL or non-UTF8 bytes. Records
include their terminating delimiter. Zero-based record indices
0, EVERY, 2*EVERY, ... are selected and concatenated without alteration.
A final nonempty record without a delimiter is also eligible.

Empty input has no records. Each delimiter completes a record, so consecutive
delimiters form separate one-byte records. A trailing delimiter creates no
phantom final record. There is no text decoding, newline stripping, escaping
or replacement of record separators.

| Admitted data | Bound |
| --- | ---: |
| Logical input bytes | 1048576 |
| Staged output bytes | 1048576 |
| Records | 65536 |
| Bytes per record, including a terminating delimiter | 65536 |

Both selected and discarded records must satisfy the limits. A record of
exactly 65536 bytes is valid if its final byte is the delimiter. If instead
it is unterminated, the application accepts it only after an additional EOF
observation. At an exact input-byte or record-count boundary it also probes
for EOF. These probes use public `read_until` with one scratch byte:
EOF admits the boundary; any extra byte rejects the staged result.

## Actual public composition

A fixed-capacity `alloc::buffered::Reader<Input>` with 4096 logical bytes
borrows an input adapter over the existing stdin Descriptor. The application
uses:

- `core::io::read_until` for selected records, copying into a 1024-byte
  caller scratch array in bounded chunks.
- `core::io::skip_until` for discarded records, consuming the remainder
  of their admitted byte span without copying to output.
- `alloc::io::Buffer` for atomic appends of successful selected chunks.

A helper's delimiter ending completes the current record. A chunk limit
continues the same record; it is not EOF. An EOF ending finishes input without
creating an extra record. Exact-boundary EOF probes use the same public
delimiter helper rather than a separate parser or direct stdin bypass.

The adapter's `core::io::Read` implementation counts actual Descriptor read
attempts and caps physical read-ahead. The buffered reader implements
`core::io::BufRead`; the portable helpers see that public protocol. They
may consume existing unread bytes without another host read.

Any helper failure aborts the operation, including failure after earlier
logical consumption. Its scratch may contain more copied bytes than the
provider acknowledged consumed. The application does not append that failure
prefix, infer rollback or retry it. All earlier staged output remains private
and is destroyed; no bytes are replayed.

## Attempts, read-ahead and publication

| Resource | Bound |
| --- | ---: |
| Actual stdin Descriptor read attempts, including EOF and Interrupted | 8192 |
| Physical stdin bytes observed, including excess-byte admission | 1048577 |
| Direct provider calls per delimiter-helper invocation | 16384 |
| Buffered reader capacity | 4096 logical bytes |
| Caller selected-record scratch | 1024 logical bytes |
| Native Descriptor transfer per host call | At most 1024 bytes |
| Data stdout attempts, including Interrupted | 8192 |
| Help stdout attempts | 64 |
| Diagnostic stderr attempts | 8 |

The one extra physical byte allows rejection of input exceeding the 1 MiB
logical cap. Reader fill may read ahead within that bound before logical
consumption; input and record limits refer to consumed record bytes, not a
claim that every fill ends exactly on a delimiter.

The helper quota counts both fill_buf and consume attempts, including
Interrupted. It is separate from the adapter's global raw-read bound.
Interrupted fill retries are provided by the helper; consumption failure is
never retried. The input adapter makes at most one Descriptor read per call,
including failed/Interrupted attempts, and refuses further host access at its
attempt or physical-byte cap.

Record/chunk loops make progress through at most the admitted logical bytes,
or terminate on EOF/error. A zero-progress non-EOF success is treated as an
internal error. The record/input/count caps are checked before another
ordinary record operation.

No stdout begins until EOF is admitted and all records, including discarded
ones, satisfy the limits. The buffered reader is explicitly discarded before
publication. Data writes advance only by confirmed positive counts; output
failure may leave a confirmed prefix, which is not replayed or rolled back.
The attempt limits do not impose a wall-clock timeout on blocking host I/O.

## Ownership and statuses

The input adapter borrows the live stdin Descriptor. The buffered reader owns
one fixed byte allocation, released by exactly one `discard` on every
recoverable path after construction. It does not close stdin. Output has one
separate Buffer owner, starts without backing, and grows only for successful
selected chunks. It is destroyed after publication or any failed selection.
The argument snapshot is released before main returns. No owner copy gains a
second cleanup authority; automatic destruction is not assumed.

| Exit | Meaning |
| ---: | --- |
| 0 | Complete selected bytes written, or help written |
| 2 | Invalid CLI, input/output/record/count/helper/raw-input-attempt limit |
| 3 | Stdin or argument-capture host error |
| 4 | Argument, buffered-reader or staged-output allocation failure |
| 5 | Data/help stdout or SIGPIPE-policy failure |
| 6 | Unexpected logical/provider/progress/buffer contract failure |

Errors attempt the exact line `select_records: operation failed\n` using
at most eight stderr write attempts. Failed diagnostics preserve the primary
status. SIGPIPE is ignored before I/O; setup failure returns 5 without a
diagnostic. Successful runs have no stderr output. Empty input or an empty
selected result intentionally produces no stdout write.

## Target and acceptance

All four registered application groups passed on the first runtime attempt
in one 8.51s run after a 1.83s driver build, totaling 91 unique native cases:

| Accepted group | Cases | Evidence directory |
| --- | ---: | --- |
| Model | 33 | `/tmp/select-records-model-vos26kjf` |
| Limits | 8 | `/tmp/select-records-limits-_34skmon` |
| CLI | 33 | `/tmp/select-records-cli-nyt88bci` |
| I/O | 17 | `/tmp/select-records-io-l3z5medd` |

The receipt is `target/stdlib-work/delimited-io-select-records-first.log`:
four tests passed with no filtered tests. The registered driver compiled
through the GPU compiler, required an actual ELF64 x86-64 executable and
passed the shared strict jump gate before native Linux x86_64 CPU execution,
using existing Descriptor and allocator services. GPU-device execution and
other backends remain unverified.

Executed application source SHA-256:
`9856d42ffc8a6c78738cf0b71d1f5b423f46559a155e317a10be42fd6343d346`.
Oracle SHA-256:
`a483a17687314607ae4f8475e18783cf597ed2f1dc2b6d3687c878d77d306910`.

The independent test-only oracle splits raw bytes at the delimiter, retains
separators and the final nonempty record, then selects the requested indices.
It imports no production buffering or delimiter implementation. Models cover
empty/consecutive/trailing/final records, NUL/non-UTF8 delimiters, cadence,
selected/skipped boundaries, exact 65536-byte records, 65536 records, exact
1 MiB input/output and seeded streams. A sparse 1 MiB case retains only its
first 16-byte record and observes at most four mappings, checking that skipped
data does not acquire source-sized retained storage.

The reader's configured 4096-byte capacity is distinct from its observed
native transfers: the Descriptor stages at most 1024 bytes per host read.
Cases span both sizes, but do not claim actual 4096-byte host refills. Limit
cases reject selected and skipped oversized records, excess input/counts and
later failure after an already selected prefix, always with empty stdout.
CLI cases cover exact syntax, help bypass, numeric/argument bounds and the
128-byte argument boundary.

Five selected allocation-denial sites are reached: both argv allocations,
the fixed reader and first/last selected-output growth. This is not every
allocation ordinal. Each returns 4 with empty stdout. Complete traces require
explicit successful same-address/same-size releases for observed successful
mappings. The baseline observes actual EOF and reader release before stdout,
with no allocation after EOF.

I/O cases execute input errors, closed stdout, read/write EINTR, later and
required-EOF read failures and SIGPIPE setup failure. A second-write EIO
follows an actual successful 1024-byte write and leaves exactly that
independently selected prefix. No successful count is fabricated. Compact
interruption summaries check 8192 input errors, or 8192 output errors plus one
successful stderr diagnostic; those summaries do not observe releases.
Provider-call budgets, raw I/O-attempt caps and blocking host deadlines remain
distinct. Direct helper-quota behavior has separate library requirements;
these application cases do not establish every quota schedule.

These finite observations do not establish automatic lifetime enforcement,
general aliasing safety, leak freedom, exhaustive fault schedules or formal
verification. A provider's physical backing and borrowed-view lifetime remain
library preconditions. Forced internal-error paths are not claimed here.

See `tests/fixtures/stdlib_execution/select_records/README.md` for retained
commands and detailed scope, and `tests/stdlib_select_records_execution.rs`
for the registered driver. Whitespace-only driver formatting after these
receipts does not represent a native rerun. With a warm build and configured
GPU, reproduce using:

```sh
timeout --kill-after=2s 100s flock -w 95 target/stdlib-work/library-gpu.lock \
  env CARGO_TARGET_DIR=target/stdlib-build LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=70000 \
  cargo test --test stdlib_select_records_execution -- --nocapture --test-threads=1
```

Production is entirely Lanius and adds no compiler, runtime ABI, proof or host
service. No Rust/Python library implementation, JSON transport or Wasm
dependency is introduced. See the
[buffered delimiter plan](library-delimited-io-plan.md) for the separate
protocol/helper contracts and library acceptance requirements.
