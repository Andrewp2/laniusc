# Parallel binary chunk checksums

`sample_programs/library/parallel_checksums.lani` reads bounded binary stdin,
maps the existing `core::crc32` implementation over fixed-size chunks through
`std::pool::map`, and emits a deterministic CSV report. The pool uses native
workers from `std::thread`; the caller also processes work. Output order is
input order regardless of worker scheduling.

All five executable test groups pass: 105 native cases and 15 separate
host-only oracle controls. The supported target is Linux x86_64/glibc CPU
execution of GPU-compiled output, linked with `atomic`.

## Command and output

```text
parallel_checksums [--workers N] [--chunk BYTES]
parallel_checksums --help
```

| Option | Meaning |
| --- | --- |
| `--workers N`, `-w N` | Requested total workers, including caller: 1..32; default 4 |
| `--chunk BYTES`, `-c BYTES` | Consecutive chunk size: 1..1048576; default 4096 |
| `--help`, `-h` | Show help without reading stdin; must be the sole argument |

Numeric options accept 1..64 ASCII decimal digits, including leading zeros.
Signs, whitespace, prefixes, nondigits, overflow, duplicates, unknown options
and operands fail. The shared CLI parser accepts attached values such as
`-w2`, `--chunk=4096`, exact long names and a `--` terminator. The terminator
does not admit operands. No CPU-affinity query changes the explicit defaults.

Input is binary: NUL, invalid UTF-8, CR and LF are ordinary bytes. There is
no record parsing. Chunks cover stdin exactly once, with a shorter final
chunk when needed. Empty input has no chunks and emits only the header.

The exact header is `chunk,offset,length,crc32` followed by LF. Every row
contains four unsigned decimal values and ends in LF. Chunk indices and
byte offsets start at zero. CRC values are the existing reflected
CRC-32/ISO-HDLC result, also computed by the independent zlib oracle.

For an executable built from the source, this example has the expected
output below; its inputs also appear in the runtime corpus:

```sh
printf '123456789' | ./parallel_checksums --workers 2 --chunk 4
```

```csv
chunk,offset,length,crc32
0,0,4,2615402659
1,4,4,2119325191
2,8,1,2366072709
```

## Admission, threading and ownership

The complete input must reach EOF within its byte and call limits before
threaded work starts. Chunk-count admission precedes scratch allocation or
worker creation. Descriptor and checksum arrays have independent checked
allocations sized with `core::mem::size_of`, and use the public
`std::parallel::Shared` descriptor expected by the pool. All descriptors are
initialized before mapping; each borrows immutable input storage. Each
checksum position has one writer. The mapper and chunk descriptors contain
plain values and borrowed views, with no nested cleanup authority.

One non-generic `fn(ptr)->ptr` worker entry calls the concrete generic
`std::pool::map_entry<Chunk,u32,Crc32>`. The pool assigns one chunk descriptor
per claim. Its synchronous contract retains input, descriptors, checksums
and control storage until every started worker has joined. A failed thread
creation reduces parallelism: the caller and successfully started workers
still complete every chunk. Requested workers are an upper bound, not a
promise that the host can start them all.

A join failure has a different contract. If the pool cannot establish that
all workers have stopped using borrowed storage, its panic terminates the
process with SIGILL on this native target
before returning into caller cleanup. The program neither prints a partial
report nor claims normal owner retirement in this exceptional path. It does
not retry an uncertain join or detach a worker.

After a successful map, the program stages the complete report in
`alloc::io::Buffer`. Descriptor/checksum scratch and the input owner are
released before stdout publication. Only the staged output remains live
while writing. Ordinary allocation, input, validation and staging failures
clean up retained owners and publish no data stdout. Argument storage is
released before input because parsed options contain only scalar values.

| Resource | Bound |
| --- | ---: |
| Captured arguments, excluding executable | 8 |
| Captured argument bytes | 512 |
| Numeric token bytes | 64 |
| Input bytes | 1048576 |
| Input attempts, including EOF, Interrupted and cap probe | 16384 |
| Chunks | 65536 |
| Requested workers, including caller | 32 |
| Staged output bytes | 4194304 |
| Data stdout attempts | 8192 |
| Help stdout attempts | 64 |
| Diagnostic stderr attempts | 8 |
| Bytes requested per read/write | 1024 |

The input collector may consume one additional byte to detect excess input.
The chunk count uses `(length-1)/chunk+1` only for nonempty input, so an exact
multiple creates no extra chunk. Admitted indices and offsets fit i32.
Scratch byte products are checked before allocation or dereference.

The output limit is conservative: the 26-byte header plus at most 65536
33-byte rows fits within 4 MiB. There is no separately reachable output-cap
claim for otherwise admitted input. Attempt limits bound retries but not
the duration of a blocking call. Thread stack configuration comes from the
host's default pthread policy.

Once publication starts, an output failure may leave the confirmed prefix
of the accepted CSV. Writes advance only by positive valid counts.
Interrupted retries spend attempts; zero, invalid counts, another error or
exhaustion stops publication. No output rollback is provided.

| Exit | Meaning |
| ---: | --- |
| 0 | Complete CSV or help output |
| 2 | Invalid CLI, input/chunk/call limit or staging limit |
| 3 | Input, signal or argument-capture host failure; unexpected storage/pool contract result |
| 4 | Source allocation failure |
| 5 | Data/help stdout failure |

SIGPIPE is ignored before argument capture. Ordinary failures attempt the
37-byte diagnostic `parallel_checksums: operation failed\n` after cleanup;
diagnostic failure preserves the primary status. An unresolved worker join
instead follows the process-termination policy above.

## Focused verification

The registered driver is `tests/stdlib_parallel_checksums_execution.rs`.
Model, CLI and boundary groups use an ordinary native-linked executable.
Resource and threading groups link the shared test-only real-pthread probe;
successful create/join calls still use glibc. Its environment faults affect
only the emitted program, with no preload or production test hooks.

| Group | Executed cases |
| --- | ---: |
| Binary data and independent zlib model | 32 |
| CLI and help admission | 26 |
| Input, chunk-count, chunk-size and worker bounds | 6 |
| Source allocation and I/O failures | 31, including 19 reached allocation failures |
| Admission before side effects, real workers, fallback and join termination | 10 |

The fixed and seeded model covers all byte values, embedded NUL/newlines,
invalid UTF-8, empty input, exact chunks and final remainders. The oracle
uses Python's standard zlib implementation and ordinary byte slicing.
It does not reimplement CRC32. Seed `0xC32A2026` fixes generated data.

Native ownership observations reuse the current shared multithread
source-site verifier. Every traced TID is classified; source allocation and
release must occur on the main thread for this pure mapper. Exact source
mapping extents are checked separately from native pthread/loader mappings.
Probe identities must be joined before publication, and no source owner may
be freed while a created worker remains unjoined.

The resource baseline drives one ENOMEM execution per reached source
allocation. Other cases exercise early/late I/O errors, interrupted retries,
zero writes, exact attempt exhaustion, signal failure and closed stdout.
Thread tests inject first/later creation failures and require full zlib
output; first/later join failures must reach the injected fault, terminate
with SIGILL, leave backing live and produce no stdout. One 1 MiB case
compares exact one-worker and four-worker output,
observes three real worker identities and their successful joins, and records
elapsed times. It makes no speedup claim.

Three additional traced cases establish the admission ordering directly:
invalid CLI performs no source read, stdout write or thread operation;
the input-limit case consumes the excess-byte probe without starting workers;
and the chunk-limit case reaches EOF before rejecting without workers or
stdout. The ordinary CLI/boundary corpus remains separately untraced.

Fifteen host-only controls currently pass: six model checks, one valid
ownership/publication sequence and eight deliberately invalid sequences.
They reject publication before EOF or joins, leaked owners, duplicate thread
identities, reads or allocations after publication, premature owner release
and thread operations after publication. Run them without compiling Lanius:

```sh
timeout --kill-after=2s 100s python3 -I -B \
  tests/fixtures/stdlib_execution/parallel_checksums/oracle.py controls
```

The five registered tests pass in 16.39 seconds on Linux x86_64/glibc.
The 1 MiB witness observes three real workers and matches the serial output;
its single timing observation is not a performance benchmark. Each executable
invocation has a 15-second timeout and each oracle group an 80-second bound.
Supported-target evidence, enforced borrowing/data-race safety and formal
verification remain distinct from these finite tests.
