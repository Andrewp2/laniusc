# Caller-provided buffered streams

The full standard and extended library goal remains open. This increment
separates buffering from allocation: portable buffered readers and writers
accept caller storage, and allocating wrappers delegate to the same engine.
At the start of the increment, every `alloc::buffered` constructor reserves
and initializes a Vec, while all buffering algorithms live in that module.

## Architecture and public family

Add `core::buffered`, importing the existing `core::io` protocols and errors
and `core::slice::View`. `core::io` does not import the new module. Move the
read-ahead, pending-output, flush and Seek state machines into this module.
Do not introduce a storage trait or a second buffering implementation.

```text
reader<R>(inner:&R, buffer:View<u8>) -> Result<Reader<R>,io::Error>
    where R:Read
writer<W>(inner:&W, buffer:View<u8>) -> Result<Writer<W>,io::Error>
    where W:Write
reader_from_parts<R>(parts:&Parts<R>) -> Result<Reader<R>,io::Error>
    where R:Read
writer_from_parts<W>(parts:&Parts<W>) -> Result<Writer<W>,io::Error>
    where W:Write
```

Reader implements Read and BufRead under `R:Read`, and Seek under
`R:Read,R:Seek`. Writer implements Write under `W:Write`, and Seek under
`W:Write,W:Seek`. Both expose `borrow`, `capacity`, `is_active`, `is_faulted`,
`take_parts` and `discard`. Reader exposes `buffered`; Writer exposes
`pending` and `finish`. Parts exposes `borrow`, `bytes` and `discard`.

Core adapters borrow their endpoint and the selected View. Start/end state
is relative to that View; every provider call and byte access includes its
original offset and preserves the slice's stride. Parts contains `inner:&I`,
`buffer:View<u8>`, relative `start:i32`, `length:i32` and `faulted:bool`.
The underlying selected capacity remains available after a handoff even if
the retained byte range is empty.

`alloc::buffered` retains its actual owning Vec and embeds the canonical core
adapter. It handles allocation, ownership transfer and release, delegating
every I/O transition. Its existing method/factory names remain meaningful
owning APIs. Add matching consuming `reader_from_parts` and
`writer_from_parts` factories and `Parts.borrow`. Existing owning Parts keeps
its actual Vec and range/fault fields. Remove redundant wrapper state rather
than mirroring core state. Migrate the one live record-literal reconstruction
in `buffered_seek/nesting.lani` to restoration; historical compiler snapshots
keep their original source scope. No compatibility alias is justified.

## Admission and lifecycle

Core construction requires positive View length, nonnegative start, and a
nonoverflowing start+length within i32. It validates metadata before reading,
clearing or writing scratch or invoking an endpoint. It neither allocates
nor initializes the selected bytes. Physical backing and its lifetime remain
caller obligations because source slice-length projection is unavailable.

Restoration additionally checks nonnegative retained start/length and that
the whole retained interval fits the selected capacity. Invalid Parts return
InvalidInput unchanged, without endpoint calls or backing access. Successful
restoration preserves exact backing, inner endpoint, retained interval and
fault state, then empties the actual Parts. A second restoration rejects.
Owning restoration transfers its actual Vec only after successful admission;
it never allocates or releases it. Faulted restoration remains faulted.

Parts remains layer-neutral: callers restore the same reader/writer meaning
that produced it. A handoff transfers control, not permission to reinterpret
unread input as output. Shallow copies never create independent controllers
or duplicate cleanup owners. End all old views and aliases before restoring.

Borrowed discard inactivates and empties metadata without releasing or
clearing caller storage. Borrowed successful finish flushes then inactivates;
failed finish retains state. Owning discard/finish additionally release their
Vec at the existing success/explicit-abandon boundary. Neither layer closes,
destroys or otherwise assumes ownership of its borrowed endpoint. Empty
metadata and repeated discard are valid on inactive adapters/Parts.

## Behavior and error contracts

Preserve the existing Lanius [buffering](stdlib-buffered.md),
[stream](stdlib-streams.md), [BufRead](stdlib-delimited-io.md) and
[Seek](stdlib-seek.md) contracts:

- Inactive/faulted checks precede argument checks and zero-count success.
- Reader returns existing unread bytes or fills with at most one immediate
  read. EOF is one observation, not a permanent cache. Consume never refills.
- Writer appends into unused tail; when full, it drains old pending bytes
  before accepting any current source. Ordinary failures preserve the exact
  suffix after confirmed downstream progress. Err accepts no current bytes.
- Interrupted/WouldBlock and other ordinary errors return without hidden
  retries. An ordinary Err(InvalidCount) is not a malformed successful count.
- Malformed successful read/write/flush acknowledgements produce sticky
  faults. Never index or publish using an invalid returned count.
- Flush drains, then calls inner flush once even when pending was empty.
  Finish succeeds only after flush; there is no implicit drop/flush.
- Reader Seek reconciles unread bytes for Current, retains unread data on
  arithmetic rejection, and clears unread publication and sets the sticky
  fault on provider seek failure or malformed position. Writer flushes before seeking and preserves
  the existing ordinary seek-error versus malformed Start behavior.

Keep one exclusive active controller. Endpoint mutable backing, selected
scratch, active state, and read/write arguments must not interfere or reenter.
Published buffer/Parts views are read-only borrowed observations and expire
before the next state mutation. No automatic borrowing or destruction is added.

Drain makes at most its initial pending-byte-count immediate write attempts
before success/error because every continuing response advances by at least
one byte. Flush adds one call; Writer Seek adds one Seek call after successful
flush. Reader Current uses at most two Seek calls. Provider-internal calls,
allocation and blocking time remain outside these direct bounds. No new
flush-step API, polling policy or artificial query-allocation failures are
needed to separate allocation from buffering.

Rust's primary [BufReader](https://doc.rust-lang.org/std/io/struct.BufReader.html)
and [BufWriter](https://doc.rust-lang.org/std/io/struct.BufWriter.html) references
motivate preserving read-ahead and reporting flush errors. Lanius deliberately
uses explicit finish/handoff/discard and manual cleanup; it does not adopt
Rust's implicit Drop behavior or promise identical internal buffering choices.

## Real consumers and acceptance

Migrate `select_records` to a caller-backed 4096-byte reader and `format_report`
to a caller-backed 17-byte writer. Preserve complete grammar, limits, output,
preflight/EOF policy, true I/O failures and remaining owner cleanup. Removed
buffer allocations and their former failure sites intentionally disappear.
Keep `buffered_copy` as an allocating-wrapper regression.

Acceptance requires tiny native admission, direct lifecycle/error/metadata
and capability checks, an independent mixed-state model across native-stride
and packed interior views plus owning wrappers, actual caller-owner/resource
and constructor-failure checks, selected old buffering/Seek regressions, and
both real applications. Check full byte streams and guards, exact provider
effects, partial failure/recovery, handoff/restoration and matched ownership.
Finite scale checks exercise reusable buffers without universal speed claims.

Root serializes compiler/Cargo/native commands under
`target/stdlib-work/library-gpu.lock`; every outer command is capped at
100 seconds. Initial acceptance targets Linux x86_64 CPU output through the
GPU compiler. Core source portability is distinct from proven target support.
No compiler/IR/ABI/extractor/proof or protected std::vec/core::mem/test-harness
changes. Missing support gets a minimal reproduction/dependency. Root README
and human policy files remain untouched; inventories and receipts live in docs.
