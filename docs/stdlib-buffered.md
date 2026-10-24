# Buffered byte streams

The library and binary-copy sample are admitted as **x86_64 Linux ELF programs
produced through the GPU compiler**, using compiler checkpoint
`59612b3431d7b0cdff16a6faecf881f62a675503`. The source programs run as native
processes; this evidence does not cover user GPU kernels or other targets.
Five focused groups passed compilation, strict ELF/jump checking, native
execution, and their stated byte/ownership/fault assertions. Their elapsed
test times are not throughput benchmarks.

The module is `alloc::buffered`, containing a fixed-capacity reader and
writer over a borrowed `core::io::Read` / `core::io::Write`. The stream contracts
in `stdlib/core/io.lani` and the manual ownership/storage rules in
`stdlib/alloc/vec.lani` remain authoritative. In particular, an ordinary `Write`
error accepts no source bytes from that call, and `flush` succeeds only with
`Ok(0)`. Neither operation implies synchronization to storage or close.

[Runtime writer formatting](stdlib-format-write.md) composes through this
same interface with bounded scratch. Its counts describe acceptance by the
immediate buffered writer; pending bytes still require explicit finish,
recovery or discard. The [CSV report](stdlib-format-report.md) exercises
prevalidated formatting and final publication failures.

## API

```lanius
reader<R>(inner: &R, capacity: i32) -> Result<Reader<R>, core::io::Error>
    where R: core::io::Read;
writer<W>(inner: &W, capacity: i32) -> Result<Writer<W>, core::io::Error>
    where W: core::io::Write;

// Reader<R> implements Read; Writer<W> implements Write.
// Both expose borrow(), is_active(), is_faulted(), capacity(),
// take_parts() -> Result<Parts<I>, core::io::Error>, discard() -> i32.

Reader<R>::buffered() -> View<u8>;
Reader<R>::fill_buf() -> Result<View<u8>, core::io::Error>;
Reader<R>::consume(count: i32) -> Result<i32, core::io::Error>;

Writer<W>::pending() -> View<u8>;
Writer<W>::finish() -> Result<i32, core::io::Error>;

struct Parts<I> {
    inner: &I,
    buffer: Vec<u8>,
    start: i32,
    length: i32,
    faulted: bool
}
Parts<I>::bytes() -> View<u8>;
Parts<I>::discard() -> i32;
```

The sketches omit `&self` and fully qualified result/view types for readability;
the module source contains the exact declarations. This API uses the existing
core I/O errors and manual cleanup; it does not add automatic drop.

## Allocation and manual owners

Capacity is a byte count in `1..=2147483647`. Zero and negative capacities return
`InvalidInput` before allocation or inner I/O. There is no special zero-capacity
mode. The constructor reserves one `Vec<u8>` allocation, initializes its full
capacity once, and preserves that length for the adapter's entire active life.
Allocation failure returns `AllocationFailed` and releases any construction
storage. Initialization costs O(capacity) byte stores.

After construction, this adapter never grows or allocates. An inner stream may
have its own allocation/I/O behavior. Accepting the maximum capacity does not
promise that the allocator can satisfy it or that initialization is quick.

`Reader`, `Writer`, and `Parts` are shallow-copy records containing one active
allocation owner. Keep one active owner; copying a descriptor does not duplicate
ownership. State and Vec fields must originate from this API and remain library
maintained, except that the handoff intentionally transfers the Vec to its
caller. No automatic cleanup runs. The inner endpoint remains borrowed; these
APIs never destroy or close it.

## State and zero-count precedence

An adapter starts active and fault-free. All read/write/fill/consume/flush/finish
operations check state first:

1. Inactive returns `InvalidInput`, including a zero-count read/write.
2. Active but faulted returns `InvalidCount`, including a zero-count read/write.
3. Otherwise read/write validate nonnegative, nonoverflowing offset/count.
4. A valid count of zero returns `Ok(0)` without accessing elements or doing I/O.

Pure metadata does no I/O. After handoff, discard, or successful writer finish,
capacity and buffered/pending ranges are empty, `is_active()` is false, and
`is_faulted()` is false. The transferred Parts retains the previous fault flag.
`discard()` remains idempotent and returns zero on an inactive adapter.

## Reader: logical bytes versus read-ahead

`fill_buf` returns the existing unread range, or makes exactly one nonempty
inner read into the empty buffer. Short reads are normal. It publishes bytes
only after validating `0 <= returned_count <= capacity`. Zero means an empty
result for this call; no permanent EOF cache is set. An error is returned
directly without retrying, advancing logical position, or publishing bytes.

`read` returns at most `min(count, available)` bytes. If unread bytes exist, it
copies those and does not refill again during that call. Otherwise it calls
`fill_buf` once. Native slice indexing preserves the source/destination stride;
this does not assume stack byte arrays have the heap byte layout. There is no
large-read bypass in this first scope.

`consume(n)` advances through already buffered input only. It accepts
`0 <= n <= buffered().len()` and returns `Ok(n)`. Bounds errors preserve the
range. When the range becomes empty its offsets reset to zero.

Successful fills advance the inner stream by their complete returned count;
the logical reader advances only by bytes returned to callers or consumed.
There is no implied seek/rewind and no position estimate. Do not resume direct
inner reads while unread data is held by the active adapter.

## Writer: acceptance and partial flush

`write` appends only a prefix fitting the current unused tail. If any tail space
exists, it copies a fitting prefix, returns `Ok(accepted)`, and performs no inner
I/O. It does not attempt a drain after accepting new source bytes.

If the tail is full, `write` first drains **all old pending bytes**. Each valid
positive inner count advances the stored offset immediately. An error,
`Interrupted`, or `WouldBlock` returns directly; zero progress produces
`WriteZero`. The current source has not been accepted at any such failure.
After the complete old drain succeeds, offsets reset, a current-source prefix
is copied, and `Ok(accepted)` is returned without further I/O. There is no
compaction or direct-write bypass. Source bytes accepted in this call cannot
be passed to the inner stream until a later operation.

The pending range is exactly the suffix not yet accepted by the borrowed inner
after ordinary partial-flush failures. Earlier buffered data may have been
accepted by that inner even when the current `write` returns an error. This is
compatible with the core `Write` contract:
the error concerns zero acceptance from the current source, not rollback of
earlier writes.

Acceptance is layer-local. If the inner is another buffered writer, its
successful write may retain bytes in its own allocation. Empty outer pending
bytes do not prove those bytes reached a device. The inner flush is therefore
required even when this layer's pending range is empty.

`flush` drains pending bytes, then calls `inner.flush()` once. Empty pending
bytes do not skip the inner flush. An inner flush error leaves the buffer active
and pending empty, so a retry still performs the inner flush. A nonzero successful
inner flush count violates the core contract, faults the adapter, and returns
`InvalidCount`. This library does not change SIGPIPE or other global policy;
inner writes/flushes retain their endpoint and process signal requirements.

`finish` calls `flush`, then releases the byte allocation and inactivates the
writer only on success. It returns `Ok(0)`. On any error it keeps the owner,
pending range, and fault state for inspection, retry if permitted, or handoff.

## Invalid counts and handoff

Negative/oversized read or write results and nonzero successful flush results
produce `InvalidCount` and make the adapter faulted. Further I/O is refused.
Counts are checked before they can become buffer indices or offsets.

The fault flag describes invalid successful counts observed at this layer.
An `Err(InvalidCount)` returned by a lawful inner is propagated as an ordinary
error without inventing a successful-count violation at the outer layer. A
nested inner may have its own fault state; the outer flag is not a complete
status report for the entire endpoint chain.

Faulting is defensive detection of a broken inner contract, not recovery of
unknown effects. A faulty inner may have consumed input, sent output, or failed
to obey physical memory requirements. This adapter cannot reconstruct those
effects or make an unsafe inner implementation safe.

`take_parts` performs no I/O/allocation, transfers the existing allocation and
borrowed endpoint, and inactivates the original wrapper. For `faulted=false`:

- Reader Parts contains exactly the unread logical range. Consume/process this
  range before resuming direct reads from `inner`, including that inner's own
  read-ahead buffer if it is another buffered reader. This range counts only
  read-ahead held by the transferred layer, not all read-ahead in the chain.
- Writer Parts contains exactly the range not yet accepted by its borrowed
  inner. Deliver it, then flush the inner stream as required; handoff itself
  does neither.

For `faulted=true`, the flag must remain attached to the recovery decision:

- Reader Parts does not publish any bytes from the invalid-count read and does
  not promise the next underlying position is the expected position.
- Writer Parts contains the suffix **not confirmed accepted by this inner**
  before the invalid result. Sending it again could duplicate unknown inner
  effects; exact nonacceptance is not promised under this condition.
- A failed inner flush may leave an empty candidate range but a faulted flag.

Parts stores scalar offsets, not a view pointing at a temporary record. Its
buffer has full initialized length equal to the former capacity; only
`start..start+length` carries the range semantics above. `bytes()` borrows that
range. A caller that transfers the shallow Vec descriptor into a separate
active owner logically consumes Parts and must stop using Parts, including its
`discard()` method. Copying the field cannot create a second allocation owner.

## Explicit discard and view lifetimes

Adapter `discard()` frees its buffer without flushing/closing and returns the
tracked unread/pending byte count released. Under a fault this is a tracked
range count, not a claim about actual delivery. Parts `discard()` similarly
releases its transferred allocation and clears its metadata. Both names denote
intentional abandonment; there is no implicit flush, drain, or hidden cleanup.

All published views are read-only **by convention**; the language does not
enforce this restriction. They expire on any mutating operation, handoff, or
discard. Do not use a reader's own buffered view as its destination, or a
writer's own pending view as its source. No caller operation may mutate the
adapter's backing allocation through another alias.

The inner endpoint and its physical backing must outlive the adapter and any
handed-off Parts. Do not perform competing I/O/seek or mutate it reentrantly
while the adapter uses it. Nested adapters are permitted through the same
borrowed contracts; outer adapters must be settled or discarded before their
inner adapters are released. Their own borrowing/view/alias rules still apply.

Logical offset checks do not establish physical bounds. Callers must supply a
slice actually backing the full claimed range, including correct native stride
and a valid endpoint for an empty range. Source/destination must not overlap
adapter storage or the inner endpoint's mutable I/O backing. Traps caused by
unbacked slices, forged owners, or unlawful inner implementations are outside
the recoverable-error/cleanup contract.

## Work and blocking scope

- Construction initializes capacity bytes after one successful reserve.
- A read makes at most one inner read and copies at most capacity bytes.
- `fill_buf` makes at most one inner read; buffered inspection and consume make
  none.
- A drain begins with at most capacity pending bytes. Every continuing write
  confirms at least one byte, so it makes at most that initial pending count in
  inner write calls. Errors/zero progress return immediately; there is no
  internal EINTR/WouldBlock retry.
- A flush adds exactly one inner flush call only after a successful drain.
- A write copies at most capacity new bytes after any required drain; there is
  no repeated memmove of a partially drained suffix.
- Handoff and discard make no inner calls. Allocator deallocation and inner
  operations have their own contracts and may block.

These are abstract adapter bounds, not machine-instruction counts, bounded
elapsed time, a deadline, or a guarantee that an arbitrary inner returns.

## Binary copy sample

With a compiler built from this checkout, run from the repository root:

```sh
mkdir -p target/stdlib-work
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  --stdlib-root stdlib sample_programs/library/buffered_copy.lani \
  -o target/stdlib-work/buffered-copy
timeout --kill-after=2s 100s target/stdlib-work/buffered-copy < input.bin > output.bin
cmp input.bin output.bin
```

`sample_programs/library/buffered_copy.lani` copies raw stdin bytes to stdout
through actual `std::stream::Descriptor` endpoints, `Reader` and `Writer` with
4096-byte capacities, and `core::io::copy` with 256 logical scratch bytes. It
uses the existing packed view over i32-array backing, rather than assuming a
repeated integer literal creates a correctly typed u8 array. Native fixed-array
backing and descriptor staging may occupy additional stack space; 256 describes
the logical scratch capacity. Owned buffering is fixed at 8192 bytes.

The sample takes no arguments. It sets the process-wide BrokenPipe disposition
to Ignore before buffer allocation; this turns a closed stdout pipe into a
checked error so cleanup can run. The library never changes signal policy.
Stdin/stdout descriptors remain borrowed and are not closed or reconfigured.

Successful copy requires `writer.finish()` to return `Ok(0)`, then releases the
reader. Failed writer construction releases the already allocated reader.
Copy or finish failure explicitly discards both remaining byte owners and
returns failure. A failed finish retains the writer until that discard; no
owner is silently dropped. The sample emits no diagnostic text into its binary
stdout stream or stderr.

| Exit status | Meaning |
| --- | --- |
| 0 | EOF copied and buffered writer plus inner flush completed |
| 2 | Unexpected command-line arguments |
| 3 | Signal setup, copy, finish, or other I/O failure |
| 4 | Buffer construction allocation failure |

This is streaming output. An error can leave an output prefix, consumed input
including read-ahead, and intentionally discarded pending bytes. Copy's written
counter counts acceptance by the buffered writer, not delivery to stdout.
`core::io::copy` retries Interrupted according to its existing contract; this
sample treats any failed final finish as an abort. Fixed buffering does not
bound total input, work, blocking time, or elapsed time. There is no timeout,
rewind, staged/atomic output, or automatic recovery promise.

## Native admission gates

`tests/stdlib_buffered_execution.rs` uses the production `stdlib` root and
`tests/fixtures/stdlib_foundation/buffered` as its explicit fixture source root.
It has no overlay-copy machinery or dependency on an ignored directory.
Executable bytes pass the existing `TempArtifact::write_bytes` strict ELF/jump
checker; compilation and native runs use the established timeout paths. The
closed-output case uses the existing bounded `timeout` plus `Command::output`
pattern, preserving an actual stdout pipe redirection that the common capture
helper would otherwise replace.

The four library fixture groups and separate sample group passed:

| Group | Accepted checks |
| --- | --- |
| reader | logical bytes versus read-ahead; existing-buffer short reads; copied bytes survive buffer reuse; empty/invalid requests; unread handoff; no permanent EOF cache; one-shot EINTR; invalid count/fault/state priority |
| writer | batching without I/O; copied-source independence; short acceptance; confirmed old prefix then error with zero current-source acceptance; retained suffix/retry; inner flush errors with empty pending; failed finish ownership; write-zero/EINTR; invalid count after a confirmed prefix; nonzero successful flush; explicit discard |
| composition | actual imported `Reader<Reader<_>>` and `Writer<Writer<_>>` implementations through `core::io::copy`, stack-byte source and packed Vec destination |
| allocation | exactly four constructor allocations and every reached ENOMEM position, exact prefix cleanup, no inner method calls |
| sample | one compile, byte-for-byte stdin/stdout at lengths 0, 1, 4095, 4096, 4097 and 10000; each of two constructor failures; actual closed stdout pipe at lengths 1 (finish failure) and 10000 (copy/drain failure), with EPIPE/Ignore and exact cleanup |

The scripted fixture peers count every valid invocation, including zero-count
calls, so a local zero-count return is distinguished from hidden forwarding.
The three behavior fixtures require successful construction; only the dedicated
allocation fixture and sample group inject allocation failures. The sample
group compiles its executable once and reuses it for all ten native cases.

### Exact allocation oracle

Every traced live address is paired with its allocation identity and exact
requested length. Reused addresses are accepted only after the old owner was
released. Unknown/double/wrong-size releases, mremap, extra allocations, failed
releases, nonempty final ownership sets, unexpected mmap failures, and missing
injections fail the oracle. There is no minimum-count fallback.

| Fixture | Checked successful lengths | Checked release identities |
| --- | --- | --- |
| reader | 4, 2, 2, 2, 2 | 0, 1, 2, 3, 4 |
| writer | 4, 1, 1, 2, 2, 2, 2, 2, 2 | 0, 1, 2, 3, 4, 5, 6, 7, 8 |
| composition | 7, 3, 2, 3, 2 | 4, 3, 2, 1, 0 |
| allocation baseline | 2, 3, 4, 5 | 3, 2, 1, 0 |
| sample success/closed pipe | 4096, 4096 | 1, 0 |

Identities are zero-based successful-allocation ordinals. Allocation-fixture
baseline must exit 0. Each separately injected mmap failure must be reached
exactly once, return native exit 2, attempt exactly the prefix through that
position, and release the preceding successful owners in reverse order:

| Failed constructor allocation | Successful sizes | Release order |
| --- | --- | --- |
| 1 | none | none |
| 2 | 2 | 2 |
| 3 | 2, 3 | 3, 2 |
| 4 | 2, 3, 4 | 4, 3, 2 |

The sample's two constructor failures similarly require native exit 4 and exact
successful prefixes of its two 4096-byte requests, with no input/output syscall.
Its successful and closed-pipe runs require Ignore to be installed before the
first buffer allocation. Both real closed-pipe cases must reach a stdout write
returning EPIPE, return 3, and release both buffers exactly once. Sample tracing
suppresses printed signal events with `signal=none`; signal delivery and the
process policy are unchanged, and the actual sigaction/EPIPE calls remain
checked.

The size oracle follows the current Linux x86 source path:
`core::mem::size_of<u8>()` is 1, `Vec::relocate` requests `size * capacity` with
alignment 8, x86 `runtime_abi.slang` forwards that size unchanged into mmap's
length argument, and its dealloc thunk forwards the original size to munmap.
These are **syscall argument** sizes, not measured physical/resident pages or a
CPU page-rounding assumption. The accepted runs matched these exact lengths.

## Runtime evidence

The five accepted groups used five successful GPU compiler invocations and
18 native executions. Each executable passed the shared strict ELF/jump check.
The allocation group executed its baseline and all four reached allocation
failures; the sample group compiled once for all ten binary/constructor/pipe
cases. The exact profiles above were asserted in every relevant run.

| Exact Rust test | Native runs | Elapsed | Terminal log under `target/stdlib-work/buffered-admission/` |
| --- | --- | --- | --- |
| `reader_preserves_logical_bytes_handoff_and_fault_state` | 1 | 4.64 s | `reader-parser-fix.log` |
| `writer_preserves_current_acceptance_pending_offsets_and_inner_flush` | 1 | 4.89 s | `writer.log` |
| `imported_nested_readers_and_writers_compose_through_copy` | 1 | 5.77 s | `composition-typed-local.log` |
| `each_of_four_construction_failures_releases_exact_preceding_owners` | 5 | 5.18 s | `allocation.log` |
| `binary_copy_sample_finishes_and_releases_buffers_on_pipe_and_allocation_errors` | 10 | 5.04 s | `sample.log` |

These are individual gate times including compilation and instrumentation.
There is no throughput, large-workload, other-target, or user-GPU-kernel
benchmark claim.

Two initial attempts are retained separately from those accepted results:

- The first reader executable returned zero, but its test then failed because
  the harness required literal `") = "` spacing in an aligned munmap trace.
  `reader.log` records that failed 4.78 s attempt. The driver now parses the
  argument terminator, whitespace, and result separator separately and includes
  the event/full trace in delimiter diagnostics. The library was unchanged.
- The first composition compilation failed with `LNC0006` at the chained
  `alloc::vec::with_capacity(7).unwrap()` expression; `composition.log` records
  the failed 3.46 s attempt. The accepted fixture first stores an explicitly
  typed `Result<Vec<u8>,alloc::vec::Error>` and then unwraps it. All real nested
  buffered wrappers and the generic copy remain intact. This is a distinct
  constructor-result context-inference boundary, not a missing buffered
  implementation. The exact original full fixture, hash, and history are
  preserved in [buffered_constructor_chain](../tests/fixtures/stdlib_compiler_state/buffered_constructor_chain/README.md).

No library implementation change was needed during these admissions. Independent
source review closed with no remaining finding in the ownership, acceptance,
read-ahead, fault-state, nested buffering, bounds/stride, or cleanup contracts.
