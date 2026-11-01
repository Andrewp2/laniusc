# Concatenate a bounded byte prefix

`sample_programs/library/concat_bytes.lani` opens two files, concatenates their
byte readers and writes at most a requested number of bytes to stdout. It uses
the public `Chain`, `Take`, fixed buffered reader and owned input collector.
All data is staged before publication; early EOF is normal success.

## Build and use

From the repository root with the compiler binary built:

```sh
mkdir -p target/stdlib-work
timeout --kill-after=2s 100s flock -w 95 target/stdlib-work/library-gpu.lock \
  target/stdlib-build/debug/laniusc --stdlib-root stdlib --source-root extended \
  --emit x86_64 sample_programs/library/concat_bytes.lani \
  -o target/stdlib-work/concat_bytes
printf 'abc' > target/stdlib-work/concat-first.bin
printf 'DEFG' > target/stdlib-work/concat-second.bin
target/stdlib-work/concat_bytes --limit 5 \
  target/stdlib-work/concat-first.bin target/stdlib-work/concat-second.bin
```

The expected stdout is exactly the five bytes `abcDE`, with no final newline.

Binary bytes are preserved, and the result can be shorter than the limit:

```sh
printf '\000A\377' > target/stdlib-work/concat-first.bin
printf 'B\n' > target/stdlib-work/concat-second.bin
target/stdlib-work/concat_bytes -n 12 -- \
  target/stdlib-work/concat-first.bin target/stdlib-work/concat-second.bin
```

The expected stdout is exactly the five bytes `00 41 ff 42 0a` in hexadecimal.
The compile and both examples passed; their narrow receipts are recorded below.

## Arguments and paths

The CLI is `concat_bytes --limit N FIRST SECOND`.

| Option | Meaning |
| --- | --- |
| `--limit N`, `-n N` | Required maximum output length, 0..1048576 |
| `--help`, `-h` | Show help without opening either file or reading stdin |
| `--` | End option parsing so subsequent arguments are literal paths |

The canonical `ext::cli` parser permits intermixed options and operands,
attached short values and exact long names. N contains 1..64 ASCII decimal
digits; leading zeros are accepted. Signs, whitespace, prefixes, non-ASCII
digits and overflow reject. Duplicate options, including aliases and repeated
help in a short group, reject. Ordinary execution requires exactly two paths.

Each path contains 1..4095 raw bytes with no NUL; UTF-8 is not required. A
single `-` names a file literally. No stdin fallback, normalization or shell
expansion is performed. Opens follow normal host path and symlink semantics.
The application requests existing files for reading, close-on-exec and no
controlling terminal through `std::file_ops::options()`. It does not require a
regular file or change descriptor blocking mode.

Help waives the required limit and path count, so zero, one or two otherwise
valid paths are permitted with help. Every supplied value is still validated,
and more than two paths reject. All CLI checks finish before any open. The
argument snapshot admits 16 entries and 8192 total raw bytes, excluding argv[0]
and terminating NUL bytes.

## Composition and lifetime

The files open in FIRST, SECOND order. If the first open fails, the second is
not attempted. If the second open fails, the first file is closed before the
diagnostic. Argument storage remains live through the second-open attempt and
is then released; the File owners no longer borrow the path bytes.

Both live File owners are borrowed by `core::io::chain`. A
`core::io::take` caps this concatenation at N. The existing
`alloc::buffered::reader` wraps Take with a 4096-byte allocation, and
`alloc::io::read_to_end` stages at most N bytes with a 16384-call limit. The
buffer allocation still occurs for N zero, but Take returns EOF locally, so
neither file receives a data read. Both files still have to open successfully.

Chain observes the first file's EOF before switching permanently to the second.
A positive short read stays with the first file. Take stops further reads once
N bytes have passed through it, even if either file has more data. Since Take
is inside the buffered reader, this composition does not prefetch file bytes
beyond N. The owned collector's cap probe observes Take's local EOF after the
quota is exhausted. An earlier EOF from the second file also succeeds.

The collector retains confirmed bytes on failure, and the application destroys
that failure owner. It discards the input buffer before returning from
collection, then attempts to close SECOND followed by FIRST. Every opened file
is retired once, even when an earlier operation failed. The first operational
failure remains the primary status; a close error after successful collection
prevents publication. Linux File ownership is invalidated before its one close
attempt, and close errors are never retried.

Only the staged output allocation remains live when stdout publication starts.
It is released on success or output failure before any diagnostic. No adapter
owns, closes or independently copies either File. These are explicit manual
lifetime rules; the program does not establish automatic ownership checking or
recovery from traps.

## Bounds, output and failures

| Resource | Limit |
| --- | ---: |
| Output bytes / staged capacity | N, at most 1,048,576 |
| Input buffer | 4096 bytes |
| Owned collector Read calls | 16384 |
| Data stdout attempts | 4096 |
| Help stdout attempts | 64 |
| Diagnostic stderr attempts | 8 |
| Arguments / raw argument bytes | 16 / 8192 |
| Bytes in each path / numeric token | 4095 / 64 |

The read-call budget counts the collector's delegations, including EOF,
Interrupted and its cap probe. A Chain call can consult both files when it
observes the first EOF. Some buffered reads consult neither file. These counts
are not a claim that direct host calls and collector calls are identical.
The current native File/Descriptor provider transfers at most 1024 bytes per
host read or write. Staging capacity never exceeds N.

Interrupted reads are retried by the bounded collector. Interrupted writes
spend output attempts and retry the same unconfirmed range. Opens and closes
make one attempt each; they do not retry Interrupted. WouldBlock and other
ordinary I/O errors terminate the operation. The count limits impose no
wall-clock timeout on blocking host I/O.

Successful output contains only the exact staged bytes, without framing or an
added newline. A failed write can leave its confirmed stdout prefix; later
attempts never replay confirmed bytes and no rollback is promised. A zero
write or exhausted output budget returns 5. Invalid provider counts or
internal range/count failures return 6. Empty output performs no stdout write,
so a closed stdout alone does not turn a zero-byte result into failure.

| Exit | Meaning |
| ---: | --- |
| 0 | Complete byte output or help |
| 2 | Invalid CLI, input/staging size or call limit |
| 3 | Argument-capture host, file open/read or close failure |
| 4 | Allocation failure |
| 5 | Output or SIGPIPE-policy failure |
| 6 | Invalid provider count or internal state |

The program sets SIGPIPE to Ignore before argument capture. Setup failure
returns 5 silently. Other failures attempt the exact 31-byte diagnostic
`concat_bytes: operation failed\n` after cleanup. A diagnostic failure preserves
the primary status. Successful executions have empty stderr. Help is exactly
907 bytes.

## Acceptance

The exact standalone compiler command above exited 0 with no diagnostic output
(`target/stdlib-work/io-adapters-app-build-command.log`). Both guide examples
then exited 0 with empty stderr: text output was exactly `61 62 63 44 45`, and
binary output was exactly `00 41 ff 42 0a`. These five-byte outputs are retained
as `target/stdlib-work/io-adapters-app-text-example.bin` and
`target/stdlib-work/io-adapters-app-binary-example.bin`, with the comparison
receipt in `target/stdlib-work/io-adapters-app-examples.log`.

All four application groups passed on native Linux x86_64 CPU output from the
GPU compiler: **115 distinct process cases**. The single focused driver command
reported four passing Rust tests in 10.13 seconds, after a separate 1.75-second
Rust build (`target/stdlib-work/io-adapters-app-first.log`).

| Group | Cases | Retained evidence |
| --- | ---: | --- |
| Model | 29 | `/tmp/concat-bytes-model-7n8_yds9` |
| Limits | 12 | `/tmp/concat-bytes-limits-wo9sbb4_` |
| CLI | 45 | `/tmp/concat-bytes-cli-cfk544kv` |
| I/O | 29 | `/tmp/concat-bytes-io-tvu6al17` |

The independent model compares exact output with `(first + second)[:N]`, using
real input files and fixed seed `0xC0CA7B17`. It covers empty/short/binary inputs,
all byte values, boundaries inside and across files, early EOF, non-UTF-8 paths,
symlinks and two independent opens of the same file. Regular input files are
checked afterward for unchanged bytes. Limit cases include zero, transfer and
buffer boundaries, and 1 MiB. Full traces require source reads to respect the
remaining quota, second-file reads to follow first-file EOF, no file reads for
zero quota, and no stdin reads. CLI checks cover the exact help, parsing and
rejection before opens.

The counted I/O baseline reads files of 5101 and 7003 bytes with a 12000-byte
quota. Its trace binds argv retirement after the second open, the 4096-byte
input buffer, initial 1024-byte staging and final 12000-byte staging. Only the
final staged allocation remains live when output starts. Five reached ENOMEM
cases cover both argv allocations, input buffering, initial staging and final
staging. Every selected successful mapping has a matching explicit release at
its address and requested extent. Failed allocation cases publish no bytes and
attempt no later allocation. These are selected finite fault observations.

Other I/O cases cover both opens, both source reads, first-file EOF, retries,
close failures, failure precedence, actual EPIPE and a real 1024-byte stdout
prefix followed by EIO. Injected close errors establish one retirement attempt,
no later use and no publication; strace substitutes the error without executing
the kernel close, so those cases do not prove successful kernel descriptor
release. Ordinary paths require successful closes. Two compact retry-summary
cases establish the 16384-read and 4096-write attempt ceilings without full
allocation/descriptor ledgers. The
[fixture guide](../tests/fixtures/stdlib_execution/concat_bytes/README.md)
records exact profiles and their limits.

Accepted producer identities (SHA-256):

- Application: `26933ffcd7c4cdd1bc0d120d6fa1e32ab4f0b70d47df045dbacd9a920831bba3`.
- Oracle: `d0313ba42cb38d487129b79a8b3752aae4efc6f19f47c2cd1d765f7dbadc1c03`.
- `core::io`: `6d3a6046d72ee3e36249744660a48f6fd4800f9c89e7056ed77fd598a0f3b643`.
- `alloc::buffered`: `08212669340df04f8a6d61d1e17a8af13c7c1d730e01b30ec1f662e3fd302834`.
- `alloc::io`: `9eeb63f40cc582d192afa43e5b2e65ffa209bbfc63d6893a3f0af155377b7392`.

The standalone examples and host-only oracle controls are separate from these
115 cases; overlapping examples add no case count. The
[reader adapter](stdlib-io-adapters.md) guide records library evidence. Other
targets, user GPU execution, exhaustive failure handling, automatic lifetime
enforcement and formal verification need separate evidence.
