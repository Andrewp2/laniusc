# Byte streams

The stream APIs separate allocation-free contracts (`core::io`), owned byte
storage (`alloc::io`) and native file descriptors (`std::stream`). All library
behavior is implemented in Lanius; descriptor operations call existing host
bindings.

[`std::file::File`](stdlib-files.md) owns descriptors, implements the same
Read/Write contracts, and provides explicit close and ownership transfer.
Descriptor adapters below continue to borrow handles.

The [resumable-copy increment](stdlib-resumable-copy.md) adds borrowed Copier
state with pending scratch, cumulative confirmed bytes and per-step read/call
quotas. Stops distinguish EOF, quotas and WouldBlock direction; abort preserves
the tracked suffix. Ordinary errors remain resumable, while malformed successful
counts fault the state. The blocking copy convenience now uses this same engine.
A [borrowed JSON encoder](extended-json-streaming.md) supplies an ordinary Read
provider. All six copier and four JSON library gates pass, including separate
72-case transfer and 978-case encoding models. The migrated normalizer passes
four groups/100 native cases, and its standalone build/examples also pass.
Earlier receipts retain their source/API scope, and selected current stream
regressions are recorded separately in the copier guide.

The separate [borrowed reader-adapter increment](stdlib-io-adapters.md) adds
Take byte quotas and Chain concatenation directly to core::io. Read and BufRead
remain independent capabilities. Actual first-source EOF permanently advances
Chain; Take can observe a later source recovery. Invalid successful replies
fault an adapter, while ordinary provider errors propagate without retry.
All seven library tests pass, including the 1,576-case independent model, actual
buffer ownership and four reached allocation denials. The concat_bytes program
passes all four groups/115 cases and its standalone build/examples on native
Linux x86_64.
Historical receipts below do not establish these additions.

The [shared Seek increment](stdlib-seek.md) adds SeekFrom, a Seek-only bound
and checked offset/position/rewind helpers. It replaces memory cursors' old
inherent seek(i32) with canonical trait methods and adds opt-in File/buffered
providers. Portable admission/direct/model, native File and real application
gates pass, including scripted buffered behavior and selected existing
regressions. Earlier receipts keep their scope.

The separate [positional-I/O increment](stdlib-positional-io.md) adds ReadAt /
WriteAt contracts and attempt-bounded exact/all helpers, with File adapters
in `std::file_ops`. Each call uses an explicit byte position without changing
the shared file cursor. Portable contracts, an independent 11,012-case model
and native adapter gates pass. The real file-patch program passes four
groups/82 process cases. The stream receipts
below cover their earlier API/source scope. One selected existing stream
regression separately passes in 11.34s with two native fixtures; it is not a
whole-stream-suite rerun.

[Fixed-capacity buffered adapters](stdlib-buffered.md) now execute through these
same traits. `alloc::buffered::Reader<R>` and `Writer<W>` borrow their inner
streams and own explicit byte buffers; they support nested wrappers, unread or
pending-byte handoff, checked counts, explicit finish and manual cleanup.
Five focused groups include eighteen native executions covering partial I/O,
allocation failures and a binary-copy application. The historical implementation
routing failure remains preserved; current generic transport and these adapters
have separate executable evidence.

The [bounded delimiter increment](stdlib-delimited-io.md) adds standalone
BufRead, caller-buffer `read_until` and allocation-free `skip_until`. Small
native admission/direct contracts, the 18,000-case model and 91-case record
selection program pass, with selected regressions separate. This finite native
Linux x86_64 increment is accepted. Earlier stream/buffered receipts do not
establish these additions.

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
| `copier(reader, writer, scratch_view)` | Checked borrowed state; `step(read_limit,max_calls)` retains pending bytes and explicit stops/progress |
| `Write.flush()` | `Result<i32, Error>`; zero means all library buffering is drained |

Pass borrowed stream owners to the generic helpers, for example
`core::io::write_all(buffer.borrow(), bytes, 0, count)`. Supplied stream types
provide `borrow()`. Custom implementations can expose an equivalent borrow.

`read_exact`, `write_all` and `copy` retry `Interrupted`. They return `WouldBlock` immediately; they do not
poll, wait for readiness, or impose timeouts. Repeated interruptions can prevent
completion. Exact reads convert early EOF to `UnexpectedEof`; complete writes
convert zero progress to `WriteZero`. Counts outside the requested range produce
`InvalidCount`. Copier bounds each step's direct attempts; the blocking
helpers retain their retry behavior.

`Failure` contains `cause` and `completed`. `CopyFailure` contains `cause`,
`read` and `written`, all measured from the beginning of that operation. Copy
may consume an input chunk before a write fails, so `read` may exceed `written`.
These counts record acknowledged transfers; a broken implementation returning
an invalid count cannot establish what actually happened. Copy clips each read
to its remaining `u64` headroom and returns `CountOverflow` when none remains;
counter exhaustion does not establish EOF.

Copy requires positive scratch capacity. Source, destination and scratch ranges
must not overlap. Helpers neither flush nor close streams. Failed transfers can
leave a valid prefix in a destination or external output; they are not atomic.

## Borrowed memory streams

`slice_reader(bytes, length)` and `slice_writer(bytes, length)` return checked
constructors for `SliceReader` and `SliceWriter`. Negative lengths fail; backing
storage and its lifetime remain caller responsibilities.

Both types expose i32 `position()`/`remaining()` and canonical
`Seek.seek(SeekFrom)` returning u64. Start/Current/End stay within `0..=length`;
invalid state or target returns InvalidInput and preserves the position.
The old inherent seek(i32) is removed; import `core::io` and pass SeekFrom.
Reads stop at the input length; writes stop at destination capacity. A full
writer returns zero, which `write_all` converts into `WriteZero`.

Byte indexing preserves the view's native stride. Fixed arrays and packed heap
buffers both work. Stream copies share their underlying bytes but have separate
cursor values; use borrowed receivers when one cursor should advance across
calls. Views must remain valid for the lifetime of the stream.

SliceReader also implements the canonical BufRead trait. `fill_buf` borrows
its remaining original bytes; `consume(n)` validates and advances that cursor
without copying or allocation. Delimiter helpers need only `B: BufRead`,
include the delimiter and distinguish Delimiter/Eof/Limit. Their call budget
counts fills and consumes; only Interrupted fills retry. Copy-before-consume
can leave `DelimiterFailure.copied > consumed`. See the
[delimiter guide](stdlib-delimited-io.md) for limits, exact acknowledgement
and borrowed-view rules.

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

The [shared Seek guide](stdlib-seek.md) records portable admission/direct/model
acceptance and a selected existing stream regression (one test, two native
fixtures in 11.00s). Native File gates pass across separate direct/fault
receipts, and the real reverse-records program passes four groups/86 cases.
Three scripted buffered tests pass separately in 9.95s, and four selected
existing buffered regressions pass in 10.57s (one writer-only test filtered).
Historical absolute-cursor receipts do not establish these additions.

The receipts below predate BufRead and its delimiter helpers. Selected
regressions and acceptance for that increment are tracked separately in the
[delimiter guide](stdlib-delimited-io.md).
One selected old stream test passed in 11.59s with the two native
core_io/alloc_io fixtures; three other stream tests were filtered.

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
programs. Wasm and user-program GPU support are unverified.
[Buffered adapters](stdlib-buffered.md) and [owned files](stdlib-files.md)
have their own executable profiles; asynchronous I/O and cancellation remain
on the [full library roadmap](library-roadmap.md).

An imported nested-helper composition exposed a compiler layout limitation.
The source and reproduction command are retained in
[stream_copy_dependency](../tests/fixtures/stdlib_foundation/stream_copy_dependency/README.md).
That historical production version handled partial writes directly in its own
loop. The current copy convenience shares the Copier engine; its new acceptance
is tracked separately in the [resumable-copy guide](stdlib-resumable-copy.md).
This source migration alone does not revalidate the retained compiler reduction.
