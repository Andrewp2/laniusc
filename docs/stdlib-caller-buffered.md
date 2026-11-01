# Caller-provided buffered streams

`core::buffered` separates byte buffering from storage allocation. Its reader
and writer borrow a caller-provided `View<u8>` and an endpoint. The allocating
`alloc::buffered` wrappers own a Vec and use the same core state machine.
The [frozen plan](library-caller-buffered-plan.md) defines this increment.
Current native acceptance is pending; earlier buffering and Seek receipts
retain their original source and API scope.

## Factories and capabilities

```text
core::buffered::reader<R>(inner:&R, buffer:View<u8>) -> Result<Reader<R>,io::Error>
    where R:Read
core::buffered::writer<W>(inner:&W, buffer:View<u8>) -> Result<Writer<W>,io::Error>
    where W:Write
reader_from_parts<R>(parts:&Parts<R>) -> Result<Reader<R>,io::Error> where R:Read
writer_from_parts<W>(parts:&Parts<W>) -> Result<Writer<W>,io::Error> where W:Write
```

The restoration factories exist in both `core::buffered` and
`alloc::buffered`, using the Parts type from their own module. The existing
allocating factories still take a positive byte capacity instead of a View.
Read, Write, BufRead, Seek and their errors are the existing `core::io`
protocols; no storage trait or alternate protocol is introduced.

| Adapter | Protocol bounds | Additional methods |
| --- | --- | --- |
| Reader<R> | Read and BufRead under R:Read; Seek under R:Read+Seek | `buffered()` |
| Writer<W> | Write under W:Write; Seek under W:Write+Seek | `pending()`, `finish()` |
| Both | Metadata and lifecycle methods | `borrow()`, `capacity()`, `is_active()`, `is_faulted()`, `take_parts()`, `discard()` |
| Parts<I> | Handoff metadata | `borrow()`, `bytes()`, `discard()` |

Core constructors require positive View length, nonnegative start and an
i32-representable start+length. Invalid metadata returns `InvalidInput` before
backing access or an endpoint call. Valid construction neither initializes
the selected bytes nor allocates. The caller must supply physical backing
for the entire View and keep it live; logical metadata checks cannot establish
the source slice's physical length.

The buffer retains its original offset and signed byte stride. Adapter
start/end state is relative to the selected View. Provider calls and byte
copies include the original offset; an interior or descending View does not
become a packed byte array. Logical capacity is the selected element count,
not a claim about its physical stack or allocation extent.

## Handoff and consuming restoration

Core `Parts<I>` contains `inner:&I`, `buffer:View<u8>`, relative `start:i32`,
`length:i32` and `faulted:bool`. Allocating Parts retains its existing Vec
and the same range/fault meaning. The selected capacity remains available
even when the retained range is empty.

`take_parts()` requires an active adapter, makes no endpoint call and
inactivates its actual source. It transfers control over the buffer state;
allocating handoff also transfers the single Vec cleanup responsibility.
The endpoint always remains borrowed.

Restoration checks the buffer metadata and a nonnegative retained interval
fully within capacity. Failure returns `InvalidInput` with the actual Parts
unchanged, without backing access or endpoint calls. Success preserves the
exact backing, endpoint, interval and fault flag, then empties the actual
Parts. A second restoration rejects. Allocating restoration transfers the
Vec without allocation or release. Faulted Parts restore a faulted adapter;
restoration does not repair unknown provider effects.

Parts is layer-neutral. Restore the same reader or writer meaning that
produced it: unread input is not permission to send those bytes as output.
End all old views and aliases before restoration. A shallow record copy does
not create an independent controller or another cleanup owner.

For ordinary, nonfaulted state, reader Parts identifies exactly this layer's
unread input; writer Parts identifies its suffix not yet accepted by its
immediate inner writer. Process those bytes before resuming direct endpoint
access. A nested adapter may retain additional read-ahead or output. When
faulted, the retained writer suffix is only the range not confirmed accepted
before the invalid acknowledgement; replay could duplicate unknown effects.
Reader faults do not publish bytes from a malformed successful read.

## Shared I/O transitions

Both storage forms use the existing [buffering contract](stdlib-buffered.md).
The core engine preserves these transitions:

- Inactive returns `InvalidInput`, then faulted returns `InvalidCount`, before
  argument validation or zero-count success. Valid zero-count read/write
  calls make no endpoint call.
- Reader returns existing unread bytes, or makes at most one immediate read
  to fill an empty buffer. Empty is an EOF observation, not a permanent cache.
  `consume` never refills and rejects negative or excessive counts unchanged.
- Writer copies only a prefix fitting unused tail space. When full, it drains
  all old pending bytes before accepting any current source. An ordinary
  failure preserves the suffix after confirmed downstream progress and
  accepts none of the current source bytes. No compaction or large-I/O bypass
  is added.
- Interrupted, WouldBlock and other ordinary errors propagate without hidden
  retries. An ordinary `Err(InvalidCount)` does not itself fault this layer.
  Invalid successful read/write counts or nonzero successful flush results
  do fault it, before those counts can become indices or published ranges.
- Flush drains, then calls inner flush once, even when pending was already
  empty. An inner flush error leaves active, empty pending state for retry.
  Finish succeeds only after flush; no automatic drop or flush occurs.

Acceptance by a buffered writer is local to that layer. Empty outer pending
bytes do not establish delivery through an inner buffer, and flush is not
fsync, close or an atomic-publication guarantee.

## Seek, finish and discard

The conditional implementations preserve [shared Seek](stdlib-seek.md):

| Operation | Effect |
| --- | --- |
| Reader Start/End | One inner seek; successful Start must acknowledge the exact target; success clears unread publication |
| Reader Current(delta) | Query inner Current(0), subtract unread count, check signed arithmetic, then seek Start(target), including delta zero |
| Reader arithmetic rejection | Preserve unread bytes and active state; no repositioning request |
| Reader provider seek error or malformed position | Preserve the error, clear unread publication and fault the reader |
| Writer Seek | Drain and inner flush first, then one seek; flush failure makes no seek; ordinary seek error leaves active empty pending state; malformed Start faults |

Seeking invalidates published views. A successful finish inactivates the
writer; failure retains its state. Core finish/discard never free or clear
caller bytes. Allocating finish releases the Vec only on success; allocating
discard releases it on explicit abandonment. Adapter or Parts discard returns
the tracked retained byte count and empties metadata; repeated discard returns
zero. A faulted count is not a claim about actual delivery.

## Manual lifetimes and effects

Keep one exclusive active controller, its endpoint, selected scratch and all
referenced backing live. State storage, scratch, endpoint mutable backing and
read/write argument ranges must not interfere. Do not drive the endpoint,
edit scratch or reenter the adapter through another alias. Published buffer
and Parts views are read-only observations whose borrows end before the next
state mutation. Nested outer controllers must be settled before their inner
controller or backing is retired.

Core-owned buffering work performs no allocation or cleanup of caller storage.
Provider implementations keep their own effects, allocation and blocking
behavior. Allocating constructors reserve and initialize their Vec once;
subsequent I/O does not grow it. Each completed handoff has one cleanup
authority, with no implicit destruction or unwind recovery.

A read/fill makes at most one direct read attempt. A drain makes at most its
initial pending-byte count in direct write attempts: every continuing result
advances at least one byte. Flush adds one direct flush call; Writer Seek adds
one seek after successful flush, and Reader Current uses at most two seeks.
These bounds exclude provider-internal calls and give no wall-clock deadline
or throughput guarantee.

Rust's [BufReader](https://doc.rust-lang.org/std/io/struct.BufReader.html) and
[BufWriter](https://doc.rust-lang.org/std/io/struct.BufWriter.html) document the
importance of preserving read-ahead and observing flush errors. Lanius keeps
explicit finish, handoff and discard; Rust's Drop behavior, optimized position
queries and internal buffer choices are not part of this contract.

## Consumers, evidence and dependencies

[select_records](stdlib-select-records.md) uses a caller-backed 4,096-element
reader; [format_report](stdlib-format-report.md) uses a caller-backed
17-element writer alongside its seven-byte formatting scratch. Their grammar,
limits, complete-input/preflight admission, output and remaining owned
resources stay the same. Removed buffer allocations and their former failure
sites intentionally disappear. `buffered_copy` stays an allocating-wrapper
regression with separately scoped evidence.

Current direct, model, owner/resource, selected regression and application
acceptance is pending. The initial target is Linux x86_64 CPU output from the
GPU compiler. Portable source does not establish GPU-device or other-target
execution. Physical backing, lifetime enforcement and formal verification
remain separate dependencies; the full library goal remains open.
