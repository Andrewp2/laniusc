# Native runtime allocator

`alloc::allocator::{alloc, dealloc, realloc}` are host calls into the x86_64
runtime block that every native executable and object carries
([`runtime_abi.slang`](../shaders/codegen/lir/x86/runtime_abi.slang); readable
source in [`runtime_raw_width.s`](../shaders/codegen/lir/x86/runtime_raw_width.s),
section `.text.alloc_bytes`). Until this change every allocation was its own
anonymous `mmap`, so each one also took a page fault, and every release was a
`munmap`. The runtime now pools small blocks.

## Pooled mode (the default)

- Requests of 1 to 1,048,576 bytes use power-of-two classes from 16 bytes to
  1 MiB. Blocks are carved from 2 MiB arenas, and each class has its own
  free list. A freed block goes back on its class list and is never unmapped.
  When an arena runs out, a new one is mapped and the rest of the old one is
  left unused.
- The classes from 64 KiB to 1 MiB (the mid tier) exist so that hash map
  tables and growing buffers reuse freed blocks instead of paying an `mmap`,
  page faults and an `munmap` on every growth. A 1 MiB block wastes the rest
  of its arena when the arena has less than 1 MiB left.
- Requests above 1 MiB and up to 8 MiB use the classes 2, 4 and 8 MiB. Each
  block is one mapping of its whole class. A freed one is kept in its pool's
  cache (up to two 2 MiB mappings and one each of 4 and 8 MiB, so at most
  16 MiB per pool) and unmapped once the cache is full. Freed or not, the
  untouched part of a class mapping costs address space, not memory.
- Requests above 8 MiB keep one exact `mmap` each, released with `munmap`.
- `dealloc` and `realloc` pick the class from the size the caller passes, so
  blocks carry no header. Callers must pass the allocation's size, as the API
  already required.
- A reused block is zeroed up to the requested size, so every allocation
  reads as zero, like a fresh mapping.
- Alignment up to 8 is accepted, as before. Pooled blocks are 16-byte aligned,
  not page-aligned.
- `realloc` within one class returns the same block and zeroes the bytes it
  gains. Across classes it first takes a free block of the new class (from
  the class list or the large-mapping cache), copies the common prefix,
  zeroes the bytes gained and frees the old block. Between two mappings
  (2 MiB and up) with nothing cached, it uses `mremap` with `MREMAP_MAYMOVE`,
  which grows the mapping in place when the address range after it is free
  and moves its pages without copying otherwise; shrinking a mapping gives
  its tail back in place. Anything else allocates, copies and frees. When an
  allocation or `mremap` fails, `realloc` returns null and the old block is
  unchanged. Either way the grown part reads as zero.
- Size 0, a zero or non-power-of-two alignment, and alignment above 8 still
  return null.

The pool state is one 4 KiB `MAP_32BIT` page holding the class heads, the
arena cursor and the arena end. Its address is kept in the upper half of the
argc word at `[R15 + 4]`, which was unused: the kernel and the CRT bridge
store argc zero-extended, and every argc reader now loads 32 bits. The value 0
means not decided yet, 1 means direct mode, and anything else is the state
page. The first allocation, of any size, decides.

So allocation now needs the runtime's R15 context, as argument and
environment access already did (see
[library-concurrency-dependencies.md](library-concurrency-dependencies.md)).

## Threads

The allocator is thread-safe, with no lock on the hot path. Every thread
shares R15 (the C entry and `crt_entry` both load the fixed process vector
`0x100000000000`), so a thread cannot be told apart by R15. It is identified
instead by its thread pointer at `%fs:0`, which glibc sets per thread.

Each thread allocates from and frees into its own pool. A pool is a page laid
out exactly like the single pool above, so the allocation and free code is
unchanged except for which pool it resolves. A freed small block is
interchangeable memory of its size class, so a free from a foreign thread
joins the **freeing** thread's own class list and can be reused there.

That alone would let memory grow with traffic in a producer/consumer pattern:
if thread A allocates a class and thread B frees it but never allocates it,
B's list grows by one block per message while A keeps carving new memory. So
the blocks flow back:

- Every 256 frees into a class, the freeing thread keeps 63 blocks on its
  list and splices the rest onto that class's shared list in the state page
  (`state + 512`), under the spinlock at `state + 120`.
- When a thread's own list for a class is empty, it checks the shared list
  (a lock-free peek, then the lock) and adopts the whole chain before carving
  new arena memory.

The common alloc and free paths still take no lock and use no atomics: a free
adds one counter increment and compare (counters at `pool + 256`), and only a
miss on an empty list peeks at the shared list. A thread strands at most a few
hundred blocks per class, so memory is bounded by live data. In a two-thread
test that passes 2,000,000 1,000-byte messages (1.9 GB of traffic) from a
producer to a consumer, resident memory grows by under 1.1 MiB.

A thread finds its pool like this:

- Raw mode (R15 is not the fixed vector) is single-threaded and never reads
  `%fs`; it uses the one state page.
- The thread that creates the state page records its `%fs:0` at `state + 112`
  and uses the state page as its own pool.
- Any other thread hashes its `%fs:0` into an open-addressed table of
  `(thread pointer, pool)` pairs, held in a 16 KiB mapping that `state + 128`
  points to (1024 slots). The lookup is a lock-free read. The first operation
  on a new thread maps a fresh pool page and inserts it under a spinlock at
  `state + 120` (taken once per thread, never on the hot path); the pool is
  stored before the thread pointer, so the x86 store order publishes it
  safely.

The state page is claimed with a 32-bit `lock cmpxchg` on `[R15 + 4]`, so
threads racing on the very first allocation agree on one state page; a loser
unmaps its spare page and retries.

A thread beyond the 1024 table slots, or whose pool mapping fails, falls back
to a direct `mmap` for each allocation and leaks a freed small block rather
than unmapping an arena sub-range. This is safe and affects only programs with
more than 1024 live threads.

Blocks of 2 to 8 MiB are cached per pool like small blocks: a freed mapping
joins the freeing thread's cache, which is capped, so memory stays bounded.
Blocks above 8 MiB are direct `mmap`/`munmap`/`mremap` on every thread, with
no shared state. A thread without a pool maps each block of 8 MiB or less as
its whole class, so `dealloc` and `realloc`, which see only the size, agree
on its length.

## Direct mode

Direct mode makes every request its own `mmap` and every release a `munmap`,
with exactly the old syscalls. It is selected in two ways:

- `LANIUS_ALLOC=mmap` in the environment;
- failure to map the state page.

Direct mode uses the same instructions as the old runtime, kept byte for byte
as the tail of the array: the allocation `mmap`, the null-on-failure check
and the adjacent `munmap` thunk.
[`source_allocations.py`](../tests/fixtures/native_c/source_allocations.py)
recognizes that tail.

Tests that trace or inject failures into allocation syscalls depend on one
`mmap` per allocation. They cover allocation ledgers, `inject=mmap:...:when=N`
ordinals, ptrace observers and `/proc/PID/maps` comparisons, and they run in
direct mode:

- the Rust tests launch strace through `common::strace()` or
  `common::traced_timeout()`;
- the Python oracles pass `strace -E LANIUS_ALLOC=mmap`;
- shell launches use `exec strace -E LANIUS_ALLOC=mmap`;
- the ptrace drivers (`text_grep_faults`, `locked_file_patch`) set the
  variable themselves.

`raw_host_width_copy.lani` checks `var_count() == 1`, so it cannot carry the
variable. It now maps its guard pages itself instead of assuming page-aligned
allocations.

## Measurements

These are untraced runs on the 3070 laptop on 2026-11-01. Each binary ran
pooled and with `LANIUS_ALLOC=mmap`, at load average 12 to 19.

| Workload | Direct (`mmap` per allocation) | Pooled |
| --- | ---: | ---: |
| Allocate and free a 1,000-byte `Vec<u8>` | 6.3 µs | 0.19 µs |
| `alloc::io::read_line`, 1 MiB × 64 in 1,000-byte lines | 848–858 ms | 187–193 ms |
| h2c load test (100 clients × 20 requests), h2c phase wall time | 0.19–0.23 s | 0.10–0.11 s |
| h2c load test, server CPU for both phases | 0.40–0.45 s | 0.24–0.26 s |
| Same, under heavier load: server system time / minor faults | 0.34–0.38 s / 20,430 | 0.09 s / 1,450 |
| `stdlib_hash_map_perf` u64 insert, 1,048,576 keys | 337–342 ms | 312–316 ms |

Making the allocator thread-safe left the single-thread fast path as fast as
before, within noise. A C microbench pinned to one CPU calls the previous
(single-pool) bytes and the thread-safe bytes alternately: 2,000,000
allocate-and-free pairs of about 1,000 bytes, best of 12 rounds, at load
average 25 to 40. The best runs were 33.2 against 33.6 ns per pair in raw
mode and 34.4 against 34.3 ns in CRT mode, where every call also reads
`%fs:0`. Most of a pair's cost is zeroing the block. The Lanius
`vec alloc`, `read_line` and hash-map insert phases varied far more between
runs at that load (by up to 2x) than between the two allocators.

The `thread_alloc` fixture (below) runs in about 1.1 to 2.8 s and peaks at
7 MiB resident.

The hash map spends little time allocating. Before the mid tier its tables
grew past 32 KiB early and those allocations stayed direct; with the mid tier,
tables up to 1 MiB come from the pool. The other bulk-caller phases, which
move megabyte buffers, are unchanged.

### Mid tier and large classes

[`stdlib_alloc_perf/bench.lani`](../tests/fixtures/stdlib_alloc_perf/bench.lani)
times alloc/free-heavy work from 4 KiB to 1 MiB and growth across 1 MiB, and
[`bench.c`](../tests/fixtures/stdlib_alloc_perf/bench.c) runs the same phases
on glibc (`malloc`, and `calloc`, which zeroes as `alloc` does). Every phase
writes one word per 4 KiB page of each block. Two interleaved runs per
allocator on the 3070 laptop, 2026-11-01, at load average 53 to 62, in ms:

| Phase | Before the mid tier | Mid tier only | Mid tier + 2..8 MiB classes | glibc `malloc` | glibc `calloc` |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1 GiB of 4 KiB alloc/touch/free | 39–55 | 33 | 34–61 | 11 | 32–35 |
| 1 GiB of 64 KiB | 1,360–1,458 | 25–27 | 27–48 | 1.3–1.5 | 19–23 |
| 1 GiB of 256 KiB | 1,147–1,159 | 25–26 | 24–25 | 2.4–2.6 | 19–22 |
| 1 GiB of 1 MiB | 1,245–1,256 | 28–31 | 32–39 | 4.0–4.1 | 22 |
| mixed: 40,000 steps, 64 slots, 4 KiB–1 MiB | 4,956–5,012 | 480–492 | 465–538 | 428–453 | 815–822 |
| double: realloc 4 KiB → 4 MiB, 400 rounds | 1,946–2,004 | 2,125–2,236 | 236–323 | 12–14 | 11–14 |
| step: realloc +4 KiB to 2 MiB, 40 rounds | 173–182 | 349–476 | 5.3–6.4 | 0.34–0.36 | 0.35–0.39 |

Whole run: 4.3 million minor faults before the mid tier, 759,000 with the
mid tier only, 13,900 now (glibc 163,000); peak resident 13, 30 and 31 MiB
(glibc 17 MiB). `LANIUS_ALLOC=mmap` takes 1.1–1.6 s per GiB in the fixed
phases.

- The fixed phases now cost what zeroing costs: 1 to 2.5x the time of
  `calloc`. Plain `malloc` does not zero, so it is 3x faster at 4 KiB and 8
  to 20x faster above.
- The mid tier alone made `step` slower than before: every `realloc`, even
  within one class, allocated, zeroed, copied and freed. Same-class `realloc`
  in place fixed that (55 to 90x faster than the mid tier alone).
- `double` was dominated by page faults on fresh mappings above 1 MiB; the
  2..8 MiB classes and their cache took it from about 2 s to 0.24–0.32 s.
  glibc is still about 20x faster there: it grows the block in place at the top of
  its heap and does not zero, while each class change here copies the block
  and zeroes the bytes gained.
- The 1M-key u64 hash map insert (`stdlib_hash_map_perf`), 10M u64 `Vec`
  pushes and the `read_line` phase of `stdlib_bulk_callers` are unchanged
  within noise at that load (insert 287–637 ms against 298–470 ms before;
  best push round 575–994 ms against 535–598 ms; `read_line` 159–333 ms
  against 148–158 ms; three interleaved runs, which varied by 2x).
  `Vec` growth cannot use `realloc`: `u64` elements are laid out downward
  from the top of the storage, so their positions depend on the capacity,
  and `Vec::relocate` keeps its typed allocate, copy and free. Hash map
  rehashing re-scatters entries and cannot use `realloc` either.

## Verification

- A CPU harness maps the assembled bytes and calls them with R15 pointing at
  a fake argument vector. It runs 200,000 random alloc, free and realloc
  operations (1 byte to 20 MB, alignments 1 to 8) in each mode. It tags every
  live block and checks that no block is overwritten, that every allocation
  reads as zero, that realloc keeps contents and, in pooled mode, that the
  bytes a realloc gains read as zero. Two mutations are caught: skipping the
  zeroing on reuse, and the wrong class in `dealloc`.
- Open issue: with the 2..8 MiB classes, 5 of about 215 runs of that raw
  harness reported one corrupted byte inside a block of a few MiB (at block
  offsets 441,131, 2,132,459, 4,262,379, 8,878,571 and 13,613,547; three of
  them at page offset `0x9eb`). All five ran while the machine was swapping
  under compile jobs (1.9 GB of swap in use). The other runs, including 104
  in a row after that, the debug build of the harness and the threaded
  harness passed. The cause is not found: it may be an allocator path that
  only memory pressure reaches, or the kernel.
- A second harness maps the bytes at the fixed vector `0x100000000000`
  (so the allocator runs in its threaded path) and drives them from real
  pthreads, so each thread's `%fs:0` differs. 1 to 32 threads each run 150,000
  tagged operations, and a third of the time a thread hands a live block to
  another thread through a queue for that thread to verify and free. Pooled
  and direct modes both pass, repeated. It caught the first draft's bug, where
  the first-allocation path clobbered the alignment argument before a losing
  thread restarted. The same harness runs the producer/consumer memory-bound
  test above, and 2,000 sequential spawn/join pairs: glibc reuses a joined
  thread's descriptor, so its `%fs:0` and pool come back and the table does
  not fill. More than 120 repetitions of the threaded modes pass. One early
  producer/consumer run crashed once and has not reproduced since, including
  under a fault reporter and with paired runs; it may have been the harness's
  own inline-assembly call, which writes below the stack pointer.
- 187 fixtures were compiled with the new runtime. They include the string,
  I/O, UTF-8, vector, sort and allocation-failure fixtures, plus
  `stdlib_ordered_navigation` `edits.lani`, which lowers `RLIMIT_AS`. Each one
  gives the same exit code, stdout and stderr pooled and in direct mode. The
  only difference is the hash map benchmark's timing output.
- 25 environment and argument fixtures behave the same with the old and the
  new compiler under eight environment and argument combinations, which
  checks the 32-bit argc loads.
- `raw_host_width_tables.py` passes. It reassembles every width-sensitive
  array, and it now also checks the `dealloc`/`realloc` entry offsets inside
  the allocator array. Before this change it failed, because the readable
  assembly still had the old `MAP_32BIT` flags.
- [`thread_alloc.lani`](../tests/fixtures/stdlib_execution/concurrency/thread_alloc.lani)
  runs the allocator under `std::pthread`:
  - 1, 4 and 16 threads each run 20,000 tagged alloc, realloc and free steps;
  - two producers pass 40,000 tagged blocks through a Condvar queue to two
    consumers, which verify and free them while the main thread also
    allocates;
  - 1,000 sequential spawn/join pairs whose bodies allocate.

  Ten runs pass. `tests/stdlib_concurrency_execution.rs` registers it next to
  `threads.lani`; that Rust test has not been run, but the program was built
  with `--native-link --native-library atomic` and checked by hand. The
  emitted runtime matches the table (`raw_host_width_tables.py --elf`).
- The strace and ptrace expectations were updated by reasoning only and have
  not been run.
