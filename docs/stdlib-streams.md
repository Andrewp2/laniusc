# Byte streams

The stream APIs separate allocation-free contracts (`core::io`), owned byte
storage (`alloc::io`) and native file descriptors (`std::stream`). All library
behavior is implemented in Lanius; descriptor operations call existing host
bindings.

[`std::file::File`](stdlib-files.md) owns descriptors, implements the same
Read/Write contracts, and provides explicit close and ownership transfer.
Descriptor adapters below continue to borrow handles.

[Fixed-capacity buffered adapters](stdlib-buffered.md) now execute through these
same traits. `alloc::buffered::Reader<R>` and `Writer<W>` borrow their inner
streams and own explicit byte buffers; they support nested wrappers, unread or
pending-byte handoff, checked counts, explicit finish and manual cleanup.
Five focused groups include eighteen native executions covering partial I/O,
allocation failures and a binary-copy application. The historical implementation
routing failure remains preserved; current generic transport and these adapters
have separate executable evidence.

[Runtime formatting to writers](stdlib-format-write.md) validates the complete
format before publication, emits through caller-sized scratch and reports the
confirmed prefix on failure. It bounds direct writer attempts separately from
format work and performs no implicit flush or close.

## Portable contracts

`Read.read(destination, offset, count)` and `Write.write(source, offset, count)`
borrow a mutable stream receiver and return `Result<i32, Error>`. A successful
count is between zero and the requested count. Short transfers are normal.
Errors report no successful transfer for that individual call. For a nonempty
read, zero means EOF; a zero write means no progress.

Offsets and counts are byte indices. Negative or overflowing ranges return
`InvalidInput`. Zero-length requests succeed without accessing the view or
stream. The caller must provide physical storage for the claimed range:
overclaiming a slice traps on indexing. Count-free operations await the length
projection in [library-dependencies.md](library-dependencies.md).

| Operation | Result and behavior |
| --- | --- |
| `read_exact(reader, destination, offset, count)` | `Result<i32, Failure>`; fills the range or reports the completed prefix |
| `write_all(writer, source, offset, count)` | `Result<i32, Failure>`; writes the whole range or reports the completed prefix |
| `copy(reader, writer, scratch, capacity)` | `Result<u64, CopyFailure>`; copies until EOF using caller-owned scratch |
| `Write.flush()` | `Result<i32, Error>`; zero means all library buffering is drained |

Pass borrowed stream owners to the generic helpers, for example
`core::io::write_all(buffer.borrow(), bytes, 0, count)`. Supplied stream types
provide `borrow()`. Custom implementations can expose an equivalent borrow.

Helpers retry `Interrupted`. They return `WouldBlock` immediately; they do not
poll, wait for readiness, or impose timeouts. Repeated interruptions can prevent
completion. Exact reads convert early EOF to `UnexpectedEof`; complete writes
convert zero progress to `WriteZero`. Counts outside the requested range produce
`InvalidCount`.

`Failure` contains `cause` and `completed`. `CopyFailure` contains `cause`,
`read` and `written`, all measured from the beginning of that operation. Copy
may consume an input chunk before a write fails, so `read` may exceed `written`.
These counts record acknowledged transfers; a broken implementation returning
an invalid count cannot establish what actually happened. Copy stops with
`CountOverflow` before requesting a chunk that could overflow its `u64` total.

Copy requires positive scratch capacity. Source, destination and scratch ranges
must not overlap. Helpers neither flush nor close streams. Failed transfers can
leave a valid prefix in a destination or external output; they are not atomic.

## Borrowed memory streams

`slice_reader(bytes, length)` and `slice_writer(bytes, length)` return checked
constructors for `SliceReader` and `SliceWriter`. Negative lengths fail; backing
storage and its lifetime remain caller responsibilities.

Both types expose `position()`, `remaining()` and checked absolute `seek()`.
Seeking outside `0..=length` returns `InvalidInput` and preserves the position.
Reads stop at the input length; writes stop at destination capacity. A full
writer returns zero, which `write_all` converts into `WriteZero`.

Byte indexing preserves the view's native stride. Fixed arrays and packed heap
buffers both work. Stream copies share their underlying bytes but have separate
cursor values; use borrowed receivers when one cursor should advance across
calls. Views must remain valid for the lifetime of the stream.

## Owned byte buffers

`alloc::io::new()` constructs an empty `Buffer` without allocating.
`with_limit(maximum)` bounds both stored length and reserved capacity; a negative
limit returns `InvalidInput`.

Buffer implements `Write`: each call appends all requested bytes or returns an
error while preserving previous contents. `LimitExceeded` reports the configured
limit; `AllocationFailed` reports allocation failure. Appending a view into the
same buffer works with spare capacity and with growth. Capacity grows
geometrically within the configured limit.

Queries are `len`, `capacity`, `limit` and `as_bytes`. `try_reserve` reserves a
total capacity; `try_clone` returns independent storage with the same limit.
`clear` retains capacity. `destroy` frees storage and resets the owning handle;
repeated destruction of that reset handle is harmless. A plain copy aliases the
allocation, so maintain one owner. Mutating operations can invalidate views.

Copying a reader into a Buffer is the read-to-end operation:

```lanius
let input: alloc::io::Buffer = alloc::io::new();
let source: std::stream::Descriptor = std::stream::stdin();
let received: core::result::Result<u64, core::io::CopyFailure> =
    std::stream::copy(source.borrow(), input.borrow());
```

On failure, the Buffer retains successfully appended chunks. Destroy it after
handling the result. A limit failure may occur after a chunk was read but before
it could be appended; `CopyFailure` preserves that distinction.

## Native descriptors

`std::stream::stdin()`, `stdout()` and `stderr()` borrow the corresponding native
descriptors. `from_handle(handle)` borrows an existing descriptor without
validating it. `Descriptor.raw_handle()` returns that handle. These adapters do
not own, close, duplicate, change flags, or seek the descriptor.

Each read/write transfers at most 1024 bytes through packed stack storage. This
adapts arbitrary Lanius byte strides to the contiguous Linux host ABI without
heap allocation. `std::stream::copy(reader, writer)` supplies its own 1024-byte
scratch buffer and delegates to the portable copy operation.

The native binding returns raw negative Linux errors. The adapter maps `EINTR`
to `Interrupted`, `EAGAIN` to `WouldBlock`, and other errors to `Host(code)` with
a positive errno. See Linux's [read](https://man7.org/linux/man-pages/man2/read.2.html)
and [write](https://man7.org/linux/man-pages/man2/write.2.html) contracts and
[errno definitions](https://github.com/torvalds/linux/blob/master/include/uapi/asm-generic/errno-base.h).
Process signals retain their normal behavior, including SIGPIPE for a broken
pipe. Applications requiring an EPIPE result and manual cleanup explicitly
select [std::signal BrokenPipe Ignore](stdlib-signals.md) before I/O; setup
failure is itself an error. The descriptor adapter does not change process-wide
disposition.

These implementations have no pending library output after a successful write.
Their flush operation therefore succeeds immediately; it does not validate the
descriptor, call fsync, promise disk durability, or close anything. Buffered
adapters must actually drain their pending output before reporting success.

## Execution evidence and limits

`tests/stdlib_stream_execution.rs` executes Lanius programs on x86_64 Linux:

On 2026-10-22, all four test groups passed in 10.99 seconds. Follow-up copy
failure-count checks passed, and the CSV normalizer's stream integration passed
its input/output and allocation-failure suite in 6.14 seconds.

- Borrowed cursors, offsets, unchanged sentinels, EOF, checked seeks, short
  transfers, interruption retries, zero progress and invalid reported counts.
- Independent byte-buffer clones, aliasing appends, capacity limits, clearing
  and repeated destruction.
- Injected allocation failures preserve bytes and the owner; syscall traces
  check that every successful allocation is freed exactly once.
- Native descriptor errors, strided buffers, partial reads and binary copying
  at 0/1/1023/1024/1025/65539 bytes.
- Injected EINTR, EAGAIN, EIO and zero-write results verify retry behavior,
  termination, and the exact output prefix.

`sample_programs/stream_copy.lani` is a bounded-memory binary copy program. Exit
zero means success, one means failure without acknowledged output, and two means
failure after a written prefix. The CSV normalizer also uses these streams;
its quoting, Unicode, malformed-input and generated-table tests still execute.

Run from the repository root, with `strace` installed:

```sh
timeout --kill-after=2s 100s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" \
  CARGO_INCREMENTAL=0 CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --locked --test stdlib_stream_execution -- --nocapture
```

The allocation-free core contains no host calls. Executable target evidence is
currently x86_64 Linux only. The compiler runs on the GPU; these are native CPU
programs. Wasm and user-program GPU support are unverified. Buffered stream
adapters, owned file handles, asynchronous I/O and cancellation remain on the
[full library roadmap](library-roadmap.md).

An imported nested-helper composition exposed a compiler layout limitation.
The source and reproduction command are retained in
[stream_copy_dependency](../tests/fixtures/stdlib_foundation/stream_copy_dependency/README.md).
The production copy operation handles partial writes directly in its own loop;
the generic traits and progress contracts are unchanged.
