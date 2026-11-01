# Bounded positional file patching

`sample_programs/library/file_patch.lani` compares an existing file range with
expected bytes, then overwrites that same range when every byte matches:

```sh
file_patch [--lock] PATH OFFSET EXPECTED_HEX REPLACEMENT_HEX
printf 'hello' > example.bin
file_patch example.bin 1 656c 4142
```

The example changes `hello` to `hABlo`. Successful patching is quiet: stdout
and stderr are empty. A sole `--help` or `-h` prints usage without opening a
file. Four operands select the useful unlocked workflow; filenames beginning with a
dash, including a path named --lock, remain literal in that form. Five operands
are accepted only when the first is exactly `--lock`; this selects cooperative
locking. There is no short lock alias or trailing lock option. Both modes use
the same preflight, patch and cleanup implementation. The program does not read
stdin.

## Complete preflight before open

The program captures at most five argument values and 24576 total argument
bytes, excluding terminating NULs. It validates everything below and decodes
both hex arguments before opening the target:

- PATH is a nonempty raw Unix byte path, at most 4095 bytes, without NUL. It
  need not be UTF-8. Paths are not normalized; ordinary final symlinks are
  followed by the host open operation.
- OFFSET is a nonempty sequence of ASCII decimal digits representing a u64.
  Leading zeros are allowed; signs, whitespace, prefixes and overflow are
  rejected. The whole requested span must fit the positional library domain:
  `OFFSET + byte_count <= 9223372036854775807`.
- Both hex strings contain only ASCII 0-9, a-f or A-F. They have equal,
  nonempty, even character lengths, yielding 1 through 4096 decoded bytes.
  Prefixes such as 0x, spaces, separators and odd lengths are rejected.

Invalid arguments therefore cannot create, truncate or open a target file.
The payload buffers are three stack arrays for expected, replacement and
actual bytes. No heap payload buffer is required. Argument capture owns its
snapshot separately and releases it before returning.

## Positional comparison and write

The actual application composition is:

```text
checked arguments -> stack hex decoding -> existing ReadWrite file owner
    -> optional exclusive lock -> read_exact_at -> compare -> write_all_at
    -> optional explicit unlock -> one explicit close
```

Open uses `std::file_ops::options()` with ReadWrite access. Create, truncate
and append remain disabled; close-on-exec is enabled. The existing file must
be openable with that access. Host path, permission, descriptor type and
filesystem restrictions remain explicit errors. Open is attempted once.

`core::io::read_exact_at` reads the complete range into the actual stack array
before comparison. Premature EOF or any read error stops without writing.
A mismatch returns its own status and performs no write. A complete match
calls `core::io::write_all_at` with the replacement buffer and the same starting
position, even when replacement and expected bytes happen to be identical.
The program does not seek or change the file description's shared cursor.

Each exact helper has a 16-attempt budget. Every trait call consumes one
attempt, including Interrupted. Only Interrupted retries; WouldBlock, EOF,
zero writes, invalid counts and other errors terminate with the library's
confirmed prefix. The native descriptor adapter checks status flags and
transfers at most 1024 bytes through packed stack staging. It respects the
actual stride of Lanius stack byte arrays; the application never treats a
strided byte array as a contiguous syscall buffer. O_DIRECT is rejected;
O_APPEND is also rejected for positional writes.

## Optional cooperative locking

A leading fifth `--lock` makes one nonblocking Exclusive whole-file advisory
lock attempt immediately after open. Contention, interruption, host errors or
a malformed nonzero success all fail that acquisition. Only an acknowledged
zero success permits the positional read/compare/write and a later unlock.
Acquisition failure skips every positional operation and unlock, then closes
the opened owner once and reports `file_patch: lock failed` with status 6.
There is no retry, waiting or spin loop.

After acknowledged acquisition, the same bounded patch function runs. Unlock
is attempted exactly once afterward, including mismatch, read and write errors.
Close is then attempted exactly once, even if unlock fails. All diagnostics
occur after those cleanup attempts, in primary phase, unlock, close order.
Ordinary four-operand mode performs no lock or unlock operation.

An earlier patch status wins over unlock and close failures. With no earlier
failure, unlock error returns 6; otherwise close error returns 3. Lock failure
also retains status 6 if close fails. A close failure after completed writes
returns an error even though file data may already be changed. A cleanup error
adds its diagnostic without replacing an earlier primary status.

These advisory locks protect cooperating clients that lock the same open-file
identity. They do not prevent writers that ignore the protocol or replace the
pathname. Locks belong to an open file description; duplicates share that lock
state and can release or change it. This application creates no duplicate or
single-handle guard pretending to own shared alias state. Evidence on a local
Linux filesystem does not establish NFS/SMB or every mount's semantics.

The owner remains live and borrowed through every operation. The existing
close invalidates it before one host attempt and is never retried after an
error. Argument and payload lifetimes remain the same in both modes; locking
adds no heap storage, data synchronization or ownership transfer. See the
[locking contract](library-file-locking-plan.md) for shared-descriptor and
conversion responsibilities.

## Mutation and failure limits

The read, comparison and write are separate operations. In unlocked mode,
another writer can change the file between them or during a multichunk
read/write. Locked mode excludes cooperating independent opens holding the
same file lock throughout this interval. It supplies no atomic compare-and-swap,
pathname transaction or content rollback.
A mismatch or read error causes no file-content writes by this process;
concurrent external changes remain outside that statement.

A later write failure can leave the already confirmed replacement prefix.
A close error can follow a fully written replacement. The application neither
flushes/synchronizes file data nor promises crash durability. Return zero means
the bounded comparison/write and close completed successfully, not that a
concurrent or persistent transaction was committed.

| Resource | Bound |
| --- | ---: |
| Captured arguments / total argument bytes | 5 / 24576 |
| Path bytes | 4095 |
| Decoded comparison/replacement bytes | 1..4096 |
| Characters per hex operand | 2..8192 |
| Stack payload arrays | Three arrays, each 4096 logical bytes |
| Positional read / write attempts | 16 / 16 |
| Bytes per native positional transfer | 1024 |
| Open / close attempts | One each after successful preflight/open |
| Optional lock / unlock attempts | One / one only after acknowledged acquisition |
| Help stdout attempts | 64 |
| Attempts per diagnostic | 8 |

Call budgets do not impose a wall-clock deadline on host filesystem or output
operations. Existing filesystem size/space and access restrictions may reject
a span that passes the library's arithmetic domain check. Positional operations
and payload staging allocate no heap storage; this does not eliminate the
explicit argument-snapshot allocations.

| Exit | Meaning |
| ---: | --- |
| 0 | Matching range replaced and close completed, or help written |
| 1 | Full read completed but expected bytes did not match; no write attempted |
| 2 | Invalid argument count, path, decimal/span, hex or length bounds |
| 3 | Argument capture I/O or file open/read/write/close failure |
| 4 | Argument snapshot allocation failure |
| 5 | SIGPIPE setup or help stdout failure |
| 6 | Lock acquisition or unlock failure, unless an earlier patch error wins |

Phase diagnostics are exact single lines prefixed by `file_patch: `:
`invalid arguments`, `argument capture failed`, `allocation failed`,
`open failed`, `lock failed`, `positional read failed`,
`expected bytes did not match`, `positional write failed`, `unlock failed`,
`close failed` or `output failed`. After cleanup attempts, a primary phase
failure is printed first, followed by any unlock failure and then close failure.
At most three such lines are attempted, each with its own eight-call budget.
A failed diagnostic preserves its status. SIGPIPE is ignored before I/O;
setup failure returns 5 before printing any diagnostic.

## Target and verification

The verified target is native Linux x86_64 CPU code emitted by the GPU
compiler, using Linux positional descriptor and advisory-lock services.
Device-side GPU execution is outside this profile. Application production is
entirely Lanius using decimal/byte/path, argument, file and portable I/O APIs;
it adds no runtime ABI or Rust/Python library implementation.

### Current ordinary-mode acceptance

The current source passed all four registered ordinary/unlocked application
groups on 2026-10-28: model 24, CLI 35, preservation 6 and I/O 17, totaling
82 native cases in 7.73s after a 1.68s driver build. The receipt is
`target/stdlib-work/file-lock-file-patch-regression.log`. This run compiled
the updated source through the GPU compiler and passed the shared strict ELF
checker before native execution.

Executed application source SHA-256:
`b2a6984c1bf73d0092327286bf858725ee729dcb4a51f1b13876160fa9ad7528`.
Current ordinary-mode oracle SHA-256:
`412368ccc6b4c2cfc87bd642071c06d0af68dbe112f98dc03c487b31da99b6d5`.
Evidence directories:

- Model: `/tmp/file-patch-model-8d76obp0`.
- CLI: `/tmp/file-patch-cli-qg8u8n2y`.
- Preservation: `/tmp/file-patch-preservation-g_72q6d6`.
- I/O: `/tmp/file-patch-io-ut_xqt0c`.

This ordinary run exercises the four-operand path. The historical receipts
below repeat these 82 ordinary-mode cases against an earlier source and are
not additional distinct coverage.

### Current optional-lock acceptance

The same application source passed all four new locked-workflow groups,
totaling 49 cases across two focused registered runs on 2026-10-28:

| Accepted group | Cases | Receipt under `target/stdlib-work/` |
| --- | ---: | --- |
| Model | 15 | One test, 7.73s; `file-lock-app-model-first.log`, three other tests filtered |
| Faults, protection and bounds | 15 + 4 + 15 | Three tests, 7.62s; `file-lock-app-boundaries.log`, model filtered |

Both runs compiled the current source through the GPU compiler and passed the
shared strict ELF checker before Linux x86_64 CPU execution. Evidence directories:

- Model: `/tmp/locked-file-patch-model-qhtvtmvs`.
- Bounds: `/tmp/locked-file-patch-bounds-qrrrrt84`.
- Faults: `/tmp/locked-file-patch-faults-nrqc6k4w`.
- Protection: `/tmp/locked-file-patch-protection-oztdgsqn`.

Locked-workflow oracle SHA-256:
`1a55a38db71cfe5aa957df496ae2acd111f1b64844f18ffc8ed0a9fbe1a3ab57`.
The 49 new cases and 82 current ordinary cases are separate profiles; the old
ordinary receipts below overlap the current ordinary corpus.

The locked models include binary ranges, 1025/4096-byte transfers, a sparse
position above 4 GiB, mismatch/EOF cleanup and the literal four-operand path
named `--lock`. Bounds cases check complete validation before open or lock.
Traces require acknowledged acquisition before every payload read, complete
reads before writes, one explicit unlock and then one close. Failed acquisition
permits no payload I/O or unlock. The only observed allocations are the two
argument-snapshot mappings, with matched releases; two selected allocation
denials are reached before open.

Fault cases exercise acquisition EINTR/EAGAIN/ENOLCK without retries, unlock
errors, read/write retries while held, open/read/close failures, ordered
phase/unlock/close diagnostics and primary-error preservation. A second-write
failure retains the confirmed 1024-byte prefix. Injected unlock and close
errors skip those kernel calls: their evidence establishes one attempt,
no retry and error precedence, rather than successful kernel cleanup.

Two independent-process protocols use observation-only Linux x86_64 ptrace
syscall stops, requiring Linux 5.3+ syscall information. For small and
4096-byte patches, a separate host open fails to acquire an exclusive lock at
each native positional-read/write entry, then acquires it after the native
unlock succeeds and before close. The helper checks the previously confirmed
write prefix at those barriers without changing native registers, results or
file bytes. Shared and exclusive host-holder cases also exclude all payload
I/O. These are finite local-filesystem observations; they do not prove lifetime,
leak, arbitrary failure-schedule or distributed-filesystem behavior.

See `tests/fixtures/stdlib_execution/locked_file_patch/README.md` for retained
commands and protocol details, and `tests/stdlib_locked_file_patch_execution.rs`
for the registered driver. Reproduce the locked groups with a warm build and
configured GPU:

```sh
timeout --kill-after=2s 100s flock -w 95 target/stdlib-work/library-gpu.lock \
  env CARGO_TARGET_DIR=target/stdlib-build LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=70000 \
  cargo test --test stdlib_locked_file_patch_execution -- --nocapture --test-threads=1
```

### Historical positional-only application receipts

The earlier four-operand source below passed all four registered application
groups on 2026-10-28, totaling 82 native cases across two focused runs. These
receipts retain that earlier source identity and do not establish current lock
behavior:

| Accepted group | Cases | Receipt under `target/stdlib-work/` |
| --- | ---: | --- |
| Model | 24 | One test, 7.18s; `positional-io-file-patch-model-first.log`, three other tests filtered |
| CLI, preservation and I/O | 35 + 6 + 17 | Three tests, 7.57s; `positional-io-file-patch-boundaries.log`, model filtered |

Both historical runs compiled that positional-only source through the GPU compiler and
passed the shared strict ELF checker before execution. Evidence directories:

- Model: `/tmp/file-patch-model-6o4bv68n`.
- CLI: `/tmp/file-patch-cli-evyl3tz3`.
- Preservation: `/tmp/file-patch-preservation-uxp628zx`.
- I/O: `/tmp/file-patch-io-ojbhxuo7`.

The independent test-only oracle creates binary files and computes expected
prefix/replacement/suffix bytes. Cases cover nonzero positions, every byte,
1023/1024/1025/4096-byte boundaries, unchanged replacements, hex case, leading
zero positions, Unicode/non-UTF8 paths, final symlinks and seeded models.
Sparse cases above 4 GiB check sentinel windows, untouched holes, unchanged
logical size and bounded allocated blocks without materializing huge holes.
Mismatch and partial-EOF cases verify preservation; invalid arguments are
rejected before any target open.

Traces require advancing positional offsets with transfers at most 1024 bytes,
a complete expected read before any write, no seek or shared-cursor payload
I/O, and one close attempt after every successful open. Valid four-operand
executions observe exactly the two argument-snapshot allocations and matched
same-address/same-size releases, with no extra positional or payload
allocation. Two selected argument-allocation denials are reached before open.
These are finite syscall observations, not a lifetime/leak or arbitrary
failure-schedule proof.

Failure cases include read/write retries and errors, open errors, two
16-attempt EINTR exhaustions, close errors and primary mismatch preservation
when close also fails. A second-chunk write EIO leaves exactly the first
confirmed 1024 replacement bytes and preserves the rest. No positive transfer
count is fabricated. Injected close EIO skips the kernel syscall: that case
checks one attempt, no retry and diagnostic/status policy, not that a kernel
close actually occurred before exit. Successful-write/close-error behavior
therefore remains explicitly capable of returning 3 after data changed.

Historical executed application source SHA-256:
`13eb71092f9a8595f0e4b4d313da0dc3d6f0eedf9b0b843887f3bb305b6d92e3`.
Historical oracle SHA-256:
`62cc1c6fc6199429bc6da4428e21818f072c53998d7d791a28431470bcaade17`.
See `tests/fixtures/stdlib_execution/file_patch/README.md` for retained
commands, detailed fault scope and file checks, and
`tests/stdlib_file_patch_execution.rs` for the registered driver. Any later
whitespace-only driver formatting changes no application behavior and is not
represented as a native rerun. With a warm build and configured GPU, reproduce
using:

```sh
timeout --kill-after=2s 100s flock -w 95 target/stdlib-work/library-gpu.lock \
  env CARGO_TARGET_DIR=target/stdlib-build LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=70000 \
  cargo test --test stdlib_file_patch_execution -- --nocapture --test-threads=1
```

The [positional I/O guide](stdlib-positional-io.md) records separate portable
trait/helper and native staging contracts and library evidence. The
[locking plan](library-file-locking-plan.md) records the added advisory API and
its required contention/cleanup gates. This
application imports `std::file_ops` to bring the File positional trait
implementations into scope and qualifies slice-view construction. It changes
no compiler, ABI or proof source. Concurrent atomic updates, crash durability,
automatic ownership and formal verification remain outside this application
contract.
