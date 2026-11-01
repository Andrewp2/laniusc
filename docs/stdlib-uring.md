# io_uring: `std::uring`

`std::uring` drives Linux io_uring through raw syscalls, with no liburing.
It calls `io_uring_setup` (425), maps the submission ring, the completion
ring and the SQE array, and calls `io_uring_enter` (426). On top of that it
builds the nop, read, write, readv, writev, openat, close, accept, recv and
send operations, plus `Ring::transfer`, a batched copy engine that the cat
and copy samples use.
The ring's head and tail words are shared with the kernel and go through
`std::atomic` (an acquire load of the CQ tail, release stores of the CQ head
and SQ tail), so programs are native-linked with libatomic:

```sh
target/release/laniusc --native-link --native-library atomic --stdlib-root stdlib \
  sample_programs/library/uring_cat.lani -o target/stdlib-work/uring_cat
```

Linux x86_64 only. io_uring must be enabled
(`/proc/sys/kernel/io_uring_disabled` is 0). The checks run on kernel 7.0.

## Rings and operations

```lani
let ring: std::uring::Ring = std::uring::setup(64).unwrap();
ring.read(fd, buffer, 4096, 0, 7);           // user_data 7
let done: std::uring::Completion = ring.wait().unwrap();
// done.user_data() == 7; done.result() is the byte count or -errno
ring.destroy();
```

| Call | Effect |
| --- | --- |
| `setup(entries)` / `setup_with(entries, flags)` | Creates a ring with 1..=4096 entries (the kernel rounds up to a power of two). The completion ring is twice as large. `setup` passes `SETUP_SUBMIT_ALL`. SQPOLL, IOPOLL and NO_SQARRAY change the protocol and are refused |
| `nop`, `read`, `write`, `readv`, `writev`, `openat`, `close`, `accept`, `recv`, `send` | Prepare one SQE carrying the caller's `user_data`. The offset `CURRENT` (-1) means the file position |
| `push(opcode, fd, offset, address, length, op_flags, user_data, flags)` | Prepare any other SQE in the same 64-byte layout |
| `link_last()` | Set IOSQE_IO_LINK on the last prepared SQE. The next SQE starts only after this one succeeds, and fails with -ECANCELED otherwise |
| `submit()` | Publish the prepared SQEs and enter. Returns how many the kernel took |
| `submit_and_wait(n)` | The same, then block until `n` completions are ready |
| `peek()` | Consume one ready completion, or return `None` |
| `wait()` | Consume one completion, submitting pending SQEs and blocking when none is ready |
| `ready()`, `pending()`, `owed()`, `space()` | Completions ready; SQEs prepared but not submitted; operations whose completions are not yet consumed; SQEs that can be prepared now |
| `overflowed()`, `dropped()` | The kernel's CQ overflow and dropped-SQE counters |
| `destroy()` | Unmap the rings and close the ring descriptor |

Helpers: `map_buffers`/`unmap_buffers` give private zeroed memory.
`stage_path` copies a path into a NUL-terminated slot and rejects interior
NULs. `iovec` fills one iovec table entry, and `seekable(fd)` tests whether
lseek works.

Each failed operation arrives as a negative `Completion::result()`. The
operation calls themselves fail only with `Error::Full`, `InvalidInput` or
`Closed`. Setup, mmap and enter failures are `Error::Host(errno)`.
`io_uring_enter` is retried on EINTR, and EBUSY/EAGAIN from the kernel become
`Error::Busy`.

Buffers, path slots, iovec tables and accept address slots must stay valid
and untouched until their completion is consumed. A Ring belongs to one
process and is used by one caller at a time.

### Backpressure

`push` returns `Error::Full` in two cases. The first is when the submission
ring has no free entry. The second is when the owed completions (prepared
plus in flight, not yet consumed) already equal the completion ring's size.
The second rule means the completion ring can never overflow: the kernel
never has to buffer completions in its overflow list. A caller that gets
`Full` consumes a completion (`wait`) and tries again.

## `Ring::transfer`: batched copy

`transfer(input, output, buffers, block, depth, stream, output_at)` copies
`input` to `output` through `depth` buffers of `block` bytes. The limits are
depth <= 64, 2*depth <= both ring sizes and block <= 64 MiB.

- **Positional input** (`stream` false): up to `depth` reads stay in
  flight, at offsets 0, block, 2*block, and so on. The window starts at one
  read and doubles with each full block. A short read is continued at the
  offset where it stopped, and a 0 result marks EOF.
- **Stream input** (pipes, stdin): one CURRENT-position read stays in
  flight. Each result is written as it arrives.
- **Positional output** (`output_at >= 0`): every chunk a read returns is
  written at once, at `output_at` plus its input offset. Reads and writes
  overlap, and so do writes to different blocks.
- **Ordered output** (`output_at` = `CURRENT`, for pipes, ttys and O_APPEND
  files): blocks are written one at a time, in input order, at the file
  position.

A short write is continued. Each completion tag carries the slot, the
chunk start and the chunk length, so no per-write table is needed. EINTR and
EAGAIN results are retried. The first failure stops new reads. Once every
operation in flight has completed, transfer returns `Read(errno)` or
`Write(errno)`. `transferred()` counts the bytes written, even after a
failure.

`cat_output(fd)` picks `output_at` for appending, as `cat` does. It returns
the file position when fd is seekable and not O_APPEND, and `CURRENT`
otherwise. `finish_output` then sets the position past the bytes written,
so `(cat a; cat b) > f` keeps working.

## Samples

- `sample_programs/library/uring_cat.lani`, `uring_cat [FILE...]`: GNU `cat`
  without options. Names are opened 32 at a time with one batch of OPENATs.
  The same `io_uring_enter` also carries the previous batch's CLOSEs. Each
  file goes through `transfer` with eight 128 KiB buffers. `-` and no
  arguments read stdin. A bad name prints `uring_cat: NAME: errno N` and is
  skipped, and the exit status becomes 1. A failed write to stdout prints
  `uring_cat: write error: errno N` and exits 1.
- `sample_programs/library/uring_copy.lani`, `uring_copy SRC DST`: `cp` for
  one file. Both opens go in one submission, linked, so a missing SRC
  cancels the DST open and DST is left untouched. Eight positional reads
  stay in flight with overlapping positional writes. Both closes go in one
  final submission, and a failed DST close is an error.

## Checks

`tests/fixtures/stdlib_execution/concurrency/uring.lani checks DIR` prints
66 exact checks:

- **Ring-full backpressure:** an 8-entry ring takes 8 NOPs before `Full`.
  After submission it takes 8 more, until 16 completions are owed. The 17th
  is refused even though the SQ is empty. Consuming one completion admits one
  more, and draining consumes all 16 with the exact user_data sum.
- **Stream:** 10,000 operations (NOPs and one-byte reads at known offsets)
  go through the 8-entry ring. There are 9,985 `Full` refusals. Every
  user_data completes exactly once with the right byte. The kernel's
  overflow and dropped counters stay 0.
- **Short reads and EOF:** a 37-byte file answers a 100-byte read with 37
  bytes, a read at EOF with 0, and a read at offset 30 with 7.
  `readv` over 10+20+30-byte iovecs fills 10, 20 and 7 bytes. A pipe holding
  5 bytes answers a 4096-byte read with 5, and after the writer closes, a
  read returns 0.
- **Errors:** a missing path gives -ENOENT. A bad fd gives -EBADF for read
  and close. A write to an O_RDONLY fd gives -EBADF, recv on a file gives
  -ENOTSOCK, and a read of a directory gives -EISDIR. In a NOP → bad read →
  NOP chain, the link fails and the third op gets -ECANCELED. `transfer`
  reports `Read(EBADF)` and `Write(ENOSPC)` (/dev/full) with nothing left
  owed, and `setup(0)` is refused.
- **Network:** loopback TCP accept through the ring reports the peer address
  length and family. The ring sends and receives both ways, with the recv
  queued before its send, and recv returns 0 once the peer closes.
- **transfer:** a 10,007-byte file is copied in 1000-byte blocks, three in
  flight, with positional and with ordered output. Both copies read back
  byte for byte.

`uring_oracle.py CAT COPY DIR SEED` checks the samples against GNU `cat` and
`cp`, with 97 cases per seed:

- File sizes on block boundaries (0, 1, 4095–4097, 128 KiB ±1, 8 blocks ±1,
  and so on) plus random sizes up to 3 MB, alone and concatenated.
- Missing files and directories mixed in. These give the same stdout, exit 1
  and the same errno text, in order.
- Stdin and a FIFO fed in random chunks with pauses. This forces short
  reads. The stdin runs also cover `-` between files.
- 300 small files, which cross the 32-name batches.
- stdout as a new file (positional writes), an O_APPEND file (ordered
  writes) and one descriptor shared by two runs.
- Copies over a longer existing DST (truncation), and a missing SRC that
  leaves DST untouched.
- Write errors on /dev/full, with DST named in the copy diagnostic.

Seeds 1–4 show 0 mismatches.

## Benchmarks

`target/claude-work/s4/uring/bench.py` runs eight interleaved rounds and
discards the first. Output files are removed before each run. The table
shows median wall ms, with the minimum in parentheses, at a load average of
about 7 from other jobs. The read/write loop is the fixture's
`loop-cat`/`loop-copy`: blocking read(2) and write(2) of 128 KiB.

| Case | GNU cat/cp 9.4 | read/write loop | std::uring |
| --- | --- | --- | --- |
| 512 MiB file > /dev/null | 42.6 (39.8) | 42.8 (42.3) | 48.3 (47.0) |
| 512 MiB file > new file | 169.1 (163.8) | 173.3 (171.0) | 131.1 (126.1) |
| copy 512 MiB | 168.9 (164.2) | 174.5 (167.7) | 132.3 (128.4) |
| 2000 × 4 KiB files > /dev/null | 31.9 (31.3) | 14.6 (14.2) | 21.6 (21.4) |

Where the time goes:

- **To /dev/null**, every tool is bound by the page-cache-to-user copy.
  std::uring is 13% slower there. All of it is kernel time: user time is
  under 10 ms. That is io_uring's per-request cost on 4,096 reads and 4,096
  writes, even though it makes about one enter per block where the loop
  makes two syscalls.
- **To a file, and copying**, std::uring is 1.3x faster than GNU. On ext4,
  buffered writes cannot complete without blocking, so the kernel hands them
  to io-wq workers. With positional output, several block writes run on those
  workers at once while the next reads complete inline. GNU `cp` 9.4 copies
  one chunk at a time.
- **Many small files:** std::uring takes 21.6 ms against 31.9 ms for GNU
  `cat` (which also calls fstat and fadvise per file), and the plain
  open/read/write/read/close loop takes 14.6 ms. Each file costs one lseek
  and two enters. The first enter carries one read: the read window starts
  at 1 and doubles with each full block. The second carries the chunk write
  and the continuation read that finds EOF. Opens and closes ride in 32-name
  batches. The next step would be a per-batch small-file path: one read per
  file in the open batch.

An earlier transfer kept its slot table in five local `[i64; 64]` arrays. It
spent about 10 µs of user time per call initializing and scanning them, and
small files took 43 ms. The table now lives in a page owned by the ring.
