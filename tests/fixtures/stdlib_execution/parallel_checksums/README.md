# Parallel checksum executable oracle

This fixture runs `sample_programs/library/parallel_checksums.lani` using an
independent `zlib.crc32` model and the shared real-pthread test probe. The
contract is in `docs/stdlib-parallel-checksums.md`; the registered driver is
`tests/stdlib_parallel_checksums_execution.rs`.

## Selectors

| Rust selector | Group | Cases |
| --- | --- | ---: |
| `parallel_checksums_matches_zlib_for_binary_chunks` | `model` | 32 |
| `parallel_checksums_validates_cli_before_input_or_output` | `admission` | 26 |
| `parallel_checksums_enforces_input_chunk_and_worker_bounds` | `limits` | 6 |
| `parallel_checksums_reached_allocations_and_io_failures_retire_owners` | `resources` | 12 + A |
| `parallel_checksums_runs_real_workers_handles_spawn_fallback_and_traps_on_failed_join` | `threads` | 10 |

A is the number of source allocations actually reached in that binary's
resource baseline. Every source mmap ordinal is failed individually; the
oracle requires the exact source site to be reached, status 4, empty stdout
and balanced surviving source owners. Allocation schedules retain the
main TID's global syscall ordinals, including native mappings.

Model, admission and limits use the ordinary program linked with `atomic`.
Resources and threads also link `stdlib_thread_lifecycle/thread_probe.c`
with `dl`. Its documented environment controls fail selected real-pthread
call ordinals; no test calls or hooks are added to the Lanius program.
Successful calls still execute real glibc create/join operations.

The fixed/generated model uses zlib and independent byte slicing; seed
`0xC32A2026` fixes generated inputs. Exact/excess boundaries cover one MiB
input and 65536 chunks. All bytes, including malformed UTF-8 and NUL, remain
ordinary input. Empty input has no chunks, and a final short chunk is kept.

The source-map observer is reused from
`stdlib_thread_pool_lifecycle/resources.py`, which verifies current sized
source/runtime instruction sites and classifies all TIDs. Source owners
remain on the main thread in these pure-worker cases. Native/CRT/pthread
mappings do not count as source owners. Probe records establish exact
successful create/join identities in main-thread order. Source owners
cannot be freed while a worker remains unjoined, and stdout cannot begin
before input EOF and all joins. Thread work or source allocation after
publication is rejected.

Join-failure cases require SIGILL, empty stdout, an actual
injected join failure and the same live source mappings at failure and
termination. These cases deliberately do not claim ordinary cleanup.
Creation-failure cases require the complete independent output and successful
joins for every worker that did start. The 1 MiB serial/threaded witness
records elapsed times but sets no performance threshold or speedup claim.
This group also traces three rejected inputs: invalid CLI has no source
reads, stdout writes or thread operations; excess input reaches its extra-byte
probe without workers/stdout; excess chunk count reaches EOF but starts no
workers and writes no stdout. These observations supplement the untraced
admission and boundary corpus.

I/O faults cover early/late read and write errors, EINTR recovery, zero
writes, signal setup and closed stdout. Suffix EINTR schedules require
exactly 16384 source read attempts or 8192 source stdout attempts plus eight
source diagnostic attempts. The write schedule starts after thread-probe
records, so it cannot silently corrupt a probe call. A late write error
must leave exactly the first confirmed 1024 CSV bytes.

The executable timeout is 15 seconds; the complete oracle group timeout is
80 seconds. Evidence remains in the printed `/tmp/parallel-checksums-GROUP-*`
directory, including input and per-TID strace files. Linux x86_64/glibc,
Python 3, a C compiler, libatomic, strace and the shared native ELF inspection
tools are required.

## Current evidence

```sh
timeout --kill-after=2s 100s python3 -I -B \
  tests/fixtures/stdlib_execution/parallel_checksums/oracle.py controls
```

Current result:
`parallel-checksums-controls=15 model=32 admission=26 limits=6 resources=12+A threads=10`.
Controls exercise six exact model checks, one accepted trace shape and eight
rejected ownership/admission/thread-order mutations.

All five native groups pass in 16.39 seconds on Linux x86_64/glibc:
32 model, 26 admission, six limits, 31 resource and ten thread cases.
The resource group reaches 19 source-allocation failures; the 1 MiB thread
case observes three real workers and matches serial output. Host controls
remain separate from these 105 native execution cases.
