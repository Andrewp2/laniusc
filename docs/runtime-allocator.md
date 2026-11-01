# Native runtime allocator

`alloc::allocator::{alloc, dealloc, realloc}` are host calls into the x86_64
runtime block that every native executable and object carries
([`runtime_abi.slang`](../shaders/codegen/lir/x86/runtime_abi.slang); readable
source in [`runtime_raw_width.s`](../shaders/codegen/lir/x86/runtime_raw_width.s),
section `.text.alloc_bytes`). Until this change every allocation was its own
anonymous `mmap`, so each one also took a page fault, and every release was a
`munmap`. The runtime now pools small blocks.

## Pooled mode (the default)

- Requests of 1 to 32,768 bytes use power-of-two classes from 16 bytes to
  32 KiB. Blocks are carved from 1 MiB arenas, and each class has its own
  free list. A freed block goes back on its class list and is never unmapped.
  When an arena runs out, a new one is mapped and the rest of the old one is
  left unused.
- Larger requests keep one `mmap` each. `dealloc` releases them with
  `munmap`, and `realloc` between two large sizes uses `mremap`.
- `dealloc` and `realloc` pick the class from the size the caller passes, so
  blocks carry no header. Callers must pass the allocation's size, as the API
  already required.
- A reused block is zeroed up to the requested size, so every allocation
  reads as zero, like a fresh mapping.
- Alignment up to 8 is accepted, as before. Pooled blocks are 16-byte aligned,
  not page-aligned.
- `realloc` with a pooled block on either side allocates the new size, copies
  the common prefix and frees the old block. When the new allocation fails,
  it returns null and the old block is unchanged.
- Size 0, a zero or non-power-of-two alignment, and alignment above 8 still
  return null.

The pool state is one 4 KiB `MAP_32BIT` page holding the class heads, the
arena cursor and the arena end. Its address is kept in the upper half of the
argc word at `[R15 + 4]`, which was unused: the kernel and the CRT bridge
store argc zero-extended, and every argc reader now loads 32 bits. The value 0
means not decided yet, 1 means direct mode, and anything else is the state
page. The first allocation of 32 KiB or less decides.

So allocation now needs the runtime's R15 context, as argument and
environment access already did (see
[library-concurrency-dependencies.md](library-concurrency-dependencies.md)).
The allocator is not thread-safe. Forked workers each get their own copy of
the pools, but threads sharing one process vector share one pool state, so
thread bodies must not allocate. Before this change concurrent allocations
happened to be safe, because each one was a separate syscall.

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

The hash map spends little time allocating. Its tables grow past 32 KiB
early, and those allocations stay direct. The other bulk-caller phases, which
move megabyte buffers, are unchanged.

## Verification

- A CPU harness maps the assembled bytes and calls them with R15 pointing at
  a fake argument vector. It runs 200,000 random alloc, free and realloc
  operations (1 byte to 70 KB, alignments 1 to 8) in each mode. It tags every
  live block and checks that no block is overwritten, that every allocation
  reads as zero and that realloc keeps contents. Two mutations are caught:
  skipping the zeroing on reuse, and the wrong class in `dealloc`.
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
- The strace and ptrace expectations were updated by reasoning only and have
  not been run.
