# Buffered seek record-reversal application fixture

The independent model partitions the original file into WIDTH-byte chunks
and joins them in reverse order, preserving bytes within each chunk. It imports
no production seek, buffering or file implementation. Record identities vary
even at widths 1024 and 4096 so accidental unchanged output fails the model.
Every real-file case checks that original bytes and size remain unchanged.

CLI is exactly `reverse_records PATH WIDTH` or sole `--help`/`-h`. PATH is
1..4095 raw non-NUL Unix bytes, including non-UTF8; WIDTH is strict unsigned
ASCII decimal 1..4096 with leading zeros allowed and at most 64 bytes.
The application never reads stdin and follows a final symlink normally.

| Group | Cases | Scope |
| --- | ---: | --- |
| model | 28 | Empty/singleton/binary records; widths 1, 255/256/257, 1023/1024/1025, 4095/4096; maximum 4096 records and 1 MiB file; raw/non-UTF8/Unicode/4095-byte paths, literal help filename, symlink and seeded bytes |
| limits | 7 | Small/large-width divisibility, excess file bytes and excess record count; all with empty stdout |
| cli | 29 | Missing/extra/mixed arguments, strict decimal/sign/space/non-ASCII/overflow and path/token bounds, sole help bypass before open |
| io | 22 | Baseline, four reached argv/reader/output-reserve allocation denials, real missing path and FIFO ESPIPE, selected open/read/End/Current/absolute-seek/close errors, primary-error preservation, actual closed stdout, read/write retries, real output prefix and attempt bounds |

Full traces require a single read-only CLOEXEC open, no create/truncate/append,
ordinary reads and lseek on that descriptor, no file writes, and exactly one
close attempt before stdout. The baseline verifies End/Start/Current-derived
absolute positions, reader release before close, one exact output reserve
before any file read, and no later allocations. Every successful observed
mapping requires explicit same-address/same-length release.

The selected four ENOMEM sites must be reached at matching baseline ordinals
and arguments, return 4 and leave stdout empty. The I/O cases reuse one source
pathname so argv-allocation size comparisons remain meaningful. Combined
reader ENOMEM and close EIO must preserve primary status 4. Injected close
errors suppress the actual kernel close: evidence establishes one attempt,
with final descriptor cleanup performed by process exit. It does not establish
that the failed call itself released the descriptor.

The unseekable FIFO uses a separately held host read/write anchor, so opening
the app's read-only endpoint cannot block waiting for a writer. A Python host
control confirms actual ESPIPE on End seek. No sleeps or successful transfer
count injection are used. Seek EINTR is not retried; read/write EINTR retries
preserve the complete independent output.

The prefix control requires one real successful 1024-byte stdout write before
the second write returns EIO, retaining exactly that model prefix with status 5.
All earlier failures publish nothing. Compact summaries exercise 8192 read
errors or 8192 write errors plus one successful diagnostic; those summaries
observe attempt bounds, not the full mapping-release ledger. Separate full
traces check selected cleanup paths. These are finite observations without
automatic lifetime, leak-freedom or exhaustive-fault guarantees.

The Rust driver compiles once per libtest process, explicitly requires a
little-endian ELF64 x86-64 executable and applies the shared strict jump gate.
The standalone oracle also rejects non-ELF targets. Native children have
15-second deadlines and registered groups 85-second deadlines. Evidence retains
commands, exact stdout/stderr/status and selected syscall traces; real source
files remain available for inspection.

```sh
python3 -B tests/fixtures/stdlib_execution/reverse_records/oracle.py controls
python3 -B tests/fixtures/stdlib_execution/reverse_records/oracle.py model PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/reverse_records/oracle.py limits PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/reverse_records/oracle.py cli PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/reverse_records/oracle.py io PATH_TO_ELF
```

## Acceptance

**All 86 native cases passed** in four registered tests, with no failures or
filtered tests, in 8.00 seconds. Receipt:
`target/stdlib-work/seek-app-projection-helpers.log`.

| Group | Cases | Evidence |
| --- | ---: | --- |
| model | 28 | `/tmp/reverse-records-model-dxwg03ej` |
| limits | 7 | `/tmp/reverse-records-limits-99rdjo91` |
| cli | 29 | `/tmp/reverse-records-cli-lbohjsan` |
| io | 22 | `/tmp/reverse-records-io-9n87z9dw` |

The accepted application uses the actual public generic buffered Seek
implementation, including End, Start and negative Current through read-ahead.
Production `alloc::buffered` factors its enum payload extraction into private
projection helpers. The [buffered dependency record](../../stdlib_foundation/buffered_seek/README.md)
preserves the prior source candidates and separate controls; this receipt
establishes application execution with the admitted source, without claiming
a compiler root cause or compiler repair.

Accepted identities (SHA-256):

- Application: `dde87e595d74e90273c55205f8e6e372f19c4104233b5d7ff4a40f1fae7e3451`.
- Driver after rustfmt only: `ba2d0e66d0fb382b437730cedebd655bceb906522718a52f00a7e9873b64f67c`.
- Oracle: `dfa11ca8e49818788c7e026a5890ad0735c6654a751a1fe95f9285e1f58b6985`.
- Buffered library: `08212669340df04f8a6d61d1e17a8af13c7c1d730e01b30ec1f662e3fd302834`.

The inspected baseline opens one read-only CLOEXEC file and uses ten lseeks:
one End, five absolute Start targets `4100, 3075, 2050, 1025, 0`, and four
Current(0) queries. Read-ahead is reconciled before each preceding record.
It releases the reader, closes the file successfully once, then publishes
5125 independently reversed bytes. The exact-size output allocation occurs
before any file reads, with no later allocation. Source contents remain
unchanged, including maximum-boundary, raw-path and symlink model cases.

All four selected mmap denials were reached: argv ordinals 1 and 2 precede
open; reader/output ordinals 3 and 4 each trigger one explicit file-close
attempt. They return 4 with empty stdout and matching releases for every
successfully observed mapping. Combined reader ENOMEM and close EIO preserves
primary status 4. The failed close is still scoped to one attempt and eventual
process-exit descriptor cleanup as described above.

Actual FIFO End seek fails with ESPIPE and status 3. An interrupted absolute
seek stops after its fourth lseek without retry. Read/write interruption
controls produce the complete correct output. The real prefix trace records
1024 successful stdout bytes followed by EIO, preserves exactly the independent
prefix and returns 5. Compact summaries record 8192 read errors (status 2), or
8192 write errors plus one diagnostic write (status 5, 8193 writes total).
These summaries establish attempt bounds; separate full traces check the
selected explicit cleanup paths.

### Admission history

The first model admission failed during compilation, before ELF generation
or application execution. `target/stdlib-work/seek-app-model-first.log` reports
zero passed tests, one failed model test and three filtered tests in 2.64
seconds. It reports `LNC0008` at unchanged `stdlib/core/iter.lani:239:39` for
`Mapper<T,core::option::Option<U>>`, reached through
`alloc::buffered -> alloc::vec -> core::iter`. The remaining groups were not
run at that point. This was an admission failure, not a runtime model failure.
The application and oracle stayed unchanged; the accepted projection-helper
source above removes the current application admission block. Historical
diagnostics alone do not establish a general nested-trait limitation.

Eight CPU control families passed, including literal vectors, generated corpus
counts, reversal involution and deliberately missing cleanup. A separate
Python host control established the FIFO anchor/ESPIPE setup. The native
receipt supplies the application evidence separately. GPU device execution,
formal verification, concurrent-file mutation, forced internal-error states,
automatic lifetime guarantees and exhaustive faults remain unclaimed.
