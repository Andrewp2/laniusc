# Reverse fixed-width file records

`sample_programs/library/reverse_records.lani` reverses the order of binary
file records while preserving every byte within each record:

```sh
printf 'aabbcc' > records.bin
reverse_records records.bin 2 > reversed.bin
```

The example writes `ccbbaa`. It opens the source read-only and never writes
its contents. The CLI is exactly `reverse_records PATH WIDTH`, or sole
`--help` / `-h`. No stdin is read.

## Admission before reading records

PATH contains 1..4095 raw non-NUL Unix bytes, without a UTF-8 requirement or
normalization. Ordinary final symlinks are followed. With two operands, a
path such as `--help` is literal; only sole help is special.

WIDTH is ASCII decimal 1..4096, parsed by the existing
`core::decimal::parse_u64_range`. Leading zeros are allowed; signs,
spaces, prefixes, empty values and overflow are invalid. The token is at most
64 bytes. Capture admits at most two arguments and 4160 total bytes excluding
terminating NULs. All local validation completes before open.

Open uses `std::file_ops::open(path, std::file_ops::options())`, whose
defaults select read-only access and CLOEXEC with no create, truncate or
append. The program requires a seekable file. Host pathname/access/type and
seek restrictions are errors.

Through the actual buffered reader, `SeekFrom::End(0)` determines the initial
file length. The application admits at most 1048576 bytes, requires exact
divisibility by WIDTH and at most 4096 records. Empty input is valid. These
checks precede output allocation or record reading.

## Buffered seek/read composition

A private Source borrows the one live File and implements public
`core::io::Read` and `core::io::Seek`. Its Read implementation bounds
actual File read attempts; Seek delegates once without retries. Importing
`std::file_ops` selects File's portable Seek implementation.

An `alloc::buffered::Reader<Source>` owns a fixed 4096-byte buffer.
The workflow is:

1. Buffered `End(0)` determines and validates length.
2. For nonempty files, reserve the exact admitted output length once.
3. Buffered `Start(length - width)` selects the last record.
4. Read exactly WIDTH bytes into a caller-backed 4096-byte record array,
   then append that complete record to staged output.
5. Between records, buffered `Current(-2 * width)` selects the preceding
   record. Check every returned absolute position against its expected target.

After each read, the logical position is one record beyond that record's
start. The inner File may have read ahead. A buffered Current seek queries the
inner current offset, subtracts unread bytes, applies the signed offset and
performs an absolute seek. This exercises logical read-ahead reconciliation
instead of privately computing and using only absolute seeks.

No unread byte View is used after seeking. Any seek error, including
Interrupted, stops; a failed seek need not roll back the inner position.
The program discards the reader rather than trying to recover or replay.
Only interrupted reads retry. Positive read counts must make valid progress;
premature EOF is an input error. A partial failed record is never appended.

The source is a normal file, not an atomic snapshot. Concurrent mutation can
change content between reads or cause premature EOF; the program does not
lock the source or promise a consistent transaction. It admits the initial
End length and validates complete record reads against it.

## Staging and ownership

Output uses one `alloc::io::Buffer` with a 1048576-byte logical limit.
For a valid nonempty file, it reserves the full initial length once after
size validation and grows no further. Empty files require no output backing.
The final staged length must equal the initial file length.

The lexical File owner remains live through the Source borrower and buffered
reader. Every recoverable path after reader construction calls exactly one
`discard`, releasing its buffer without closing the borrowed file.
Every acquired file then receives one explicit close attempt. Close invalidates
its wrapper before the host attempt and is never retried. An earlier primary
error retains precedence over a later close error; otherwise close failure
prevents output.

Only after complete reversal, reader discard and successful file close does
stdout begin. CLI, size, allocation, read, seek and close errors therefore
publish no result prefix. The output owner stays live through publication
and is then destroyed. The argument snapshot is destroyed before main returns.
No owner copy gains a second cleanup authority; automatic destruction is
not assumed.

## Work and failure budgets

| Resource | Bound |
| --- | ---: |
| Captured arguments / bytes | 2 / 4160 |
| Raw pathname bytes | 1..4095 |
| Width token bytes | 64 |
| WIDTH | 1..4096 |
| Initial file / staged output bytes | 1048576 |
| Records | 4096 |
| Buffered reader / caller record storage | 4096 logical bytes each |
| Actual File read attempts, including Interrupted | 8192 |
| Native Descriptor bytes per host read/write | At most 1024 |
| Inner seek attempts for nonempty N records | 2*N, at most 8192 |
| Inner seek attempts for an empty file | One End query |
| Data stdout attempts, including Interrupted | 8192 |
| Help stdout / diagnostic stderr attempts | 64 / 8 |

The 4096-byte reader capacity is distinct from the Descriptor's at-most-1024
native staging. Each actual Source read attempt consumes its shared budget,
including interruptions. Buffered reads can consume unread data without a host
call. Backward traversal can reread physical bytes through read-ahead, so the
1 MiB logical extent is not an aggregate physical-read-byte quota.

For N nonempty records, one End and one Start seek plus two inner seeks for
each buffered Current give exactly 2*N successful inner seek calls. No seek
is retried. Partial reads and interrupted reads remain bounded by record
progress and the actual-read quota. These are attempt bounds, not deadlines
for blocking file or stdout operations.

Stdout advances only by confirmed positive counts. Interrupted retries consume
attempts; zero, invalid counts, other errors and exhaustion stop. An output
failure may leave an already published prefix, which is not replayed or rolled
back. Success acknowledges completed descriptor writes, not downstream
consumption or durability.

| Exit | Meaning |
| ---: | --- |
| 0 | Complete reversal written, or help written |
| 2 | Invalid CLI, file-size/divisibility/count limit, actual-read quota or output-buffer limit |
| 3 | Argument/open/read/EOF/seek/close host failure |
| 4 | Argument, reader or output allocation failure |
| 5 | Data/help stdout or SIGPIPE-policy failure |
| 6 | Unexpected logical/count/seek-acknowledgement/progress/buffer failure |

Errors attempt the exact line `reverse_records: operation failed\n` using
at most eight stderr write attempts. Diagnostic failure preserves the primary
status. SIGPIPE is ignored before I/O; setup failure returns 5 without a
diagnostic. Successful runs have no stderr output. An empty file intentionally
produces no stdout write.

## Target and acceptance

All four registered application groups passed in one 8.00s run after a
1.65s driver build, totaling 86 unique native cases:

| Accepted group | Cases | Evidence directory |
| --- | ---: | --- |
| Model | 28 | `/tmp/reverse-records-model-dxwg03ej` |
| Limits | 7 | `/tmp/reverse-records-limits-99rdjo91` |
| CLI | 29 | `/tmp/reverse-records-cli-lbohjsan` |
| I/O | 22 | `/tmp/reverse-records-io-9n87z9dw` |

The receipt is `target/stdlib-work/seek-app-projection-helpers.log`: four
tests passed with no filtered tests. The registered driver compiled through
the GPU compiler, required an actual ELF64 x86-64 executable and passed the
shared strict jump gate before native Linux x86_64 CPU execution, using
existing file, seek, Descriptor and allocator services. GPU-device execution
and other backends remain unverified.

Executed, unchanged application source SHA-256:
`dde87e595d74e90273c55205f8e6e372f19c4104233b5d7ff4a40f1fae7e3451`.
Oracle SHA-256:
`dfa11ca8e49818788c7e026a5890ad0735c6654a751a1fe95f9285e1f58b6985`.
Buffered implementation SHA-256:
`08212669340df04f8a6d61d1e17a8af13c7c1d730e01b30ec1f662e3fd302834`.
That implementation factors private enum projections while retaining the
public generic Seek protocol used by the unchanged application.

The independent test-only model partitions original bytes into fixed-width
chunks and reverses their order without importing production seek/buffering
code. Executed cases include empty/singleton/binary records, widths
1, 255/256/257, 1023/1024/1025 and 4095/4096, maximum file bytes/count,
raw/non-UTF8/Unicode paths, a 4095-byte pathname, literal help filename, a final
symlink and seeded bytes. Wide records have different identities, so unchanged
output cannot pass accidentally. Real-file cases check unchanged source bytes
and size. Limit and CLI cases reject invalid size/divisibility/count and
argument syntax before publication.

The baseline observes one read-only CLOEXEC open, buffered End/Start and
Current-derived absolute positions, one exact staging reserve before any file
read, no later allocations, reader release before close and one close attempt
before stdout. Native reads use the Descriptor's at-most-1024-byte staging;
this is distinct from the reader's 4096-byte capacity. Complete traces require
explicit successful same-address/same-size releases for observed successful
mappings.

Four selected allocation denials reach both argv mappings, reader storage
and the one-time output reserve. Each returns 4 with empty stdout. Combined
reader ENOMEM and close EIO preserve primary status 4. Injected close errors
suppress that kernel call: evidence establishes one attempt/invalidation,
with final host cleanup at process exit, not successful kernel close by the
failed call itself.

I/O cases execute missing-path and actual FIFO ESPIPE failures, selected
open/read/End/Current/absolute-seek/close errors, closed stdout, read/write
EINTR and SIGPIPE setup failure. A separately held FIFO read/write anchor
prevents open from waiting for a writer. Seek EINTR stops without retry;
read/write retries preserve exact model output. An actual successful
1024-byte stdout write precedes second-write EIO, leaving exactly that
independent prefix with status 5. No successful transfer count is fabricated.

Compact interruption summaries check 8192 read errors, or 8192 output errors
plus a successful diagnostic. They establish attempt bounds, not mapping
cleanup; separate complete traces observe selected cleanup paths. These are
finite observations, not automatic lifetime enforcement, general aliasing
safety, leak freedom, concurrent snapshot consistency, exhaustive fault
coverage or formal verification. Forced internal-error paths remain unclaimed.
Buffered provider backing/lifetime remain library preconditions.

See `tests/fixtures/stdlib_execution/reverse_records/README.md` for detailed
scope and retained commands, and `tests/stdlib_reverse_records_execution.rs`
for the registered driver. With a warm build and configured GPU, reproduce:

```sh
timeout --kill-after=2s 100s flock -w 95 target/stdlib-work/library-gpu.lock \
  env CARGO_TARGET_DIR=target/stdlib-build LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=70000 \
  cargo test --test stdlib_reverse_records_execution -- --nocapture --test-threads=1
```

### Earlier admission failure

Before the accepted run, `target/stdlib-work/seek-app-model-first.log`
reported zero passed tests, one failure and three filtered tests in 2.64s.
Compilation stopped before ELF/native execution at `core::iter.lani:239:39`
with `LNC0008` for nested `Mapper<T,core::option::Option<U>>`, reached through
`alloc::buffered -> alloc::vec -> core::iter`. The 1.76s Rust driver build in
that receipt was build evidence only; no application cases ran in that attempt.
The current acceptance above supersedes its blocked status, with application
and oracle identities unchanged. See the
[buffered-seek dependency record](../tests/fixtures/stdlib_foundation/buffered_seek/README.md)
for separate reductions and controls; this application receipt does not claim
a general compiler fix.

Production is entirely Lanius and adds no compiler, runtime ABI, proof or host
service. No Rust/Python library implementation, JSON transport or Wasm
dependency is introduced. See the [seek plan](library-seek-plan.md) for the
separate protocol, File and buffered-position contracts.
