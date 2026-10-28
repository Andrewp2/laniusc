# Bounded positional file patching

`sample_programs/library/file_patch.lani` compares an existing file range with
expected bytes, then overwrites that same range when every byte matches:

```sh
file_patch PATH OFFSET EXPECTED_HEX REPLACEMENT_HEX
printf 'hello' > example.bin
file_patch example.bin 1 656c 4142
```

The example changes `hello` to `hABlo`. Successful patching is quiet: stdout
and stderr are empty. A sole `--help` or `-h` prints usage without opening a
file. Four operands are otherwise required; filenames beginning with a dash
are ordinary paths in that four-operand form. The program does not read stdin.

## Complete preflight before open

The program captures at most four argument values and 24576 total argument
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
    -> read_exact_at -> compare -> write_all_at -> one explicit close
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

The owner is borrowed throughout the patch operation. Every successfully
opened owner is closed exactly once before phase diagnostics, on success,
mismatch and failure. The existing close operation invalidates its owner
before one host attempt and is never retried after an error. A close failure
after successful writes returns status 3: the file data may already be changed.
If another error occurred first, its status is preserved and close failure is
reported separately.

## Mutation and failure limits

The read, comparison and write are separate operations. Another writer can
change the file between them or while a multichunk read/write is in progress.
The tool supplies no lock, atomic compare-and-swap or transactional rollback.
A mismatch or read error causes no file-content writes by this process;
concurrent external changes remain outside that statement.

A later write failure can leave the already confirmed replacement prefix.
A close error can follow a fully written replacement. The application neither
flushes/synchronizes file data nor promises crash durability. Return zero means
the bounded comparison/write and close completed successfully, not that a
concurrent or persistent transaction was committed.

| Resource | Bound |
| --- | ---: |
| Captured arguments / total argument bytes | 4 / 24576 |
| Path bytes | 4095 |
| Decoded comparison/replacement bytes | 1..4096 |
| Characters per hex operand | 2..8192 |
| Stack payload arrays | Three arrays, each 4096 logical bytes |
| Positional read / write attempts | 16 / 16 |
| Bytes per native positional transfer | 1024 |
| Open / close attempts | One each after successful preflight/open |
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

Phase diagnostics are exact single lines prefixed by `file_patch: `:
`invalid arguments`, `argument capture failed`, `allocation failed`,
`open failed`, `positional read failed`, `expected bytes did not match`,
`positional write failed`, `close failed` or `output failed`. A primary phase
failure followed by close failure prints the primary line and then the close
line, preserving the primary exit. Failure to write a diagnostic preserves its
status. SIGPIPE is ignored before I/O; setup failure returns 5 before printing
any diagnostic.

## Target and verification

The verified target is native Linux x86_64 CPU code emitted by the GPU
compiler, using Linux positional descriptor services. Device-side GPU execution
is outside this profile. Production is entirely Lanius using existing
decimal/byte/path, argument, file and portable I/O APIs; no new host service,
runtime ABI or Rust/Python library implementation is added.

All four registered application groups are accepted on 2026-10-28, totaling
82 unique native cases across two focused runs:

| Accepted group | Cases | Receipt under `target/stdlib-work/` |
| --- | ---: | --- |
| Model | 24 | One test, 7.18s; `positional-io-file-patch-model-first.log`, three other tests filtered |
| CLI, preservation and I/O | 35 + 6 + 17 | Three tests, 7.57s; `positional-io-file-patch-boundaries.log`, model filtered |

Both runs compiled the unchanged application through the GPU compiler and
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

Executed application source SHA-256:
`13eb71092f9a8595f0e4b4d313da0dc3d6f0eedf9b0b843887f3bb305b6d92e3`.
Oracle SHA-256:
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
trait/helper and native staging contracts and library evidence. This
application imports `std::file_ops` to bring the File positional trait
implementations into scope and qualifies slice-view construction. It changes
no compiler, ABI or proof source. Concurrent atomic updates, crash durability,
automatic ownership and formal verification remain outside this application
contract.
