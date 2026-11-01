# Shared byte positions and seeking

`core::io` defines one Seek protocol for memory cursors, files and buffered
streams. Read/Write are separate bounds. The [increment](library-seek-plan.md)
has accepted portable arithmetic/cursor, native File, buffered and application
gates on the finite native profile, with selected existing regressions. The
full library goal stays open.

## Core API and offset domain

```text
SeekFrom = Start(u64) | Current(i64) | End(i64)
trait Seek { seek(&self, from:SeekFrom) -> Result<u64,Error> }
offset_position(base:u64, offset:i64) -> Result<u64,Error>
stream_position<S>(stream:&S) -> Result<u64,Error> where S:Seek
rewind<S>(stream:&S) -> Result<u64,Error> where S:Seek
```

Error is `core::io::Error`. Seek success reports the new absolute logical
byte position; Start must acknowledge its exact target. Providers define
whether beyond-EOF positions are allowed. An error makes no general promise
about position or rollback: a provider may flush or move before failing.

| Free function | Contract |
| --- | --- |
| `offset_position(base, offset)` | Mathematical u64 plus signed i64; InvalidInput below zero or above u64::MAX. Checks before arithmetic, including i64::MIN without negation overflow; no effects. |
| `stream_position(stream)` | Exactly one `seek(Current(0))`; preserves its result/error. |
| `rewind(stream)` | Exactly one `seek(Start(0))`; preserves errors and rejects nonzero success as InvalidCount. |

The helpers require only Seek and do not retry Interrupted, allocate, poll or
close. A position query is still a seek operation: a buffered provider may
reconcile read-ahead or flush. One helper dispatch need not mean one host call.

## Memory cursors and migration

SliceReader and SliceWriter implement Seek over `0..=length`. Current uses
the cursor; End uses the fixed length. They validate `0 <= cursor <= length`
before arithmetic and check Start's u64 target before narrowing. Invalid state
or target is InvalidInput, preserving cursor and backing. No seeking touches
bytes or changes length; subsequent I/O preserves the actual byte stride.

The old inherent `seek(i32)` methods are replaced directly. Import `core::io`
and pass `SeekFrom::Start(position as u64)` after validating any signed input,
or use Current/End. There is no compatibility alias. Existing `position()`
and `remaining()` inspections still return i32; shared Seek returns u64.

## File adapter and host limits

Import `std::file_ops` to include File's Seek implementation. Its placement
alongside ReadAt/WriteAt avoids a reverse dependency from `std::file`.
The existing low-level `std::file_ops::seek(file, offset, Origin)` retains
signed-i64 results and Linux-specific Data/Hole origins; those are not
portable SeekFrom variants.

File checks closed-owner Host(9) first. Start above i64::MAX is InvalidInput
without a syscall. Current/End transport the full signed-i64 offset and make
one ordinary lseek attempt; host errors retain their normal mapping. The
full-width result is checked before conversion to u64, and a malformed Start
acknowledgement is InvalidCount. There is no retry or allocation.

The host offset belongs to the open description, so duplicates share it.
Regular files permit seeking beyond EOF without changing file length;
unseekable endpoints report host errors. Append writes retain append policy.
The portable arithmetic domain is u64; it grants no wider Linux file offset.

## Buffered reader: `R: Read` and `R: Seek`

Inactive returns InvalidInput; faulted returns InvalidCount, before inner
calls. Keep exclusive access to the borrowed inner during each operation.

| Origin | Inner calls and publication |
| --- | --- |
| Start/End | One inner seek; successful Start must match its target. Success clears unread bytes but retains allocation. |
| Current(delta) | Query inner Current(0), subtract unread count, apply checked `offset_position`, then inner Start(target). Even delta zero reconciles read-ahead and clears unread bytes on success. |

A query position below unread count is InvalidCount and faults the reader.
If target arithmetic rejects after a successful query, retain unread bytes and
active state; no repositioning call occurred. The query retains its provider's
effects, although conforming Current(0) preserves logical position.

Any actual inner seek error, including a failed query, or malformed Start
acknowledgement faults the reader and clears unread publication. Preserve
the primary error; backing allocation and inner ownership remain retained.
`take_parts`/`discard` permit explicit handoff/release; rebuild after establishing
the inner position. No stale View may be read after seek. There is no automatic
recovery, close, allocation or EOF cache.

## Buffered writer: `W: Write` and `W: Seek`

State checks precede the existing complete flush: drain pending bytes, then
inner flush, then one inner seek. Current is relative to the position after
pending output was accepted. Flush error stops without seeking and preserves
the existing pending-prefix/fault state. Successful partial flushing may
already have moved the inner cursor; no rollback or byte replay is implied.

After successful flush, an inner seek error leaves the active wrapper with
empty pending bytes and an unspecified position. Malformed Start acknowledgement
faults the writer. Success retains the empty allocation. No implicit retry,
close or new allocation occurs. Ordinary [buffered ownership](stdlib-buffered.md),
fault, handoff and borrowed-lifetime rules still apply.

## Application, evidence and targets

The [`reverse_records PATH WIDTH` program](stdlib-reverse-records.md) reads
bounded fixed-width binary records in reverse through buffered Seek/Read,
exercising End/Start and negative Current with read-ahead. It stages output
and retains explicit file/buffer cleanup. Four registered groups pass in
8.00s: limits seven, model 28, I/O 22 and CLI 29, totaling 86 cases.

| Receipt in `target/stdlib-work/` | Accepted scope |
| --- | --- |
| `seek-admission-first.log` | One test/6.30s: Seek-only generic provider, helpers and actual memory cursors. |
| `seek-contracts-first.log` | Two tests/4.74s: one native four-scenario contract process and one marked missing-Seek LNC0008 rejection; admission filtered. |
| `seek-model-first.log` | One test/5.01s: 17,620 independent cases across offset arithmetic, provider effects and reader/writer state, four backing combinations; seed `0x5eeca0261031`. |
| `seek-stream-regression.log` | One selected existing test/11.00s: core_io with six migrated calls and unchanged alloc_io. |
| `seek-file-first.log` | Mixed command/7.62s: real-file/pipe test passes (five descriptors, 19 lseeks); the fault test fails its tool-warning harness. |
| `seek-file-fault-register-retry.log` | Fault-only test/6.19s, one filtered: 18 schedules, five genuine controls and 13 reached injections, with complete 64-bit result checks. |
| `seek-existing-file-regression.log` | One selected existing FileOps test/7.65s; four tests filtered. |
| `seek-app-projection-helpers.log` | Four application tests/8.00s: all 86 native cases. |
| `seek-buffered-factored-peer.log` | Three tests/9.95s: nine reader phases, twelve writer phases, nesting/ownership and all four reached constructor denials. |
| `seek-existing-buffered-regressions.log` | Four selected existing tests/10.57s: actual binary-copy sample, constructor denials, nested copy and reader handoff; one writer-only test filtered. |

[Direct fixtures](../tests/fixtures/stdlib_foundation/seek/README.md) establish
literal boundaries, exact helper dispatch/error preservation and full traces
containing only entry/exit. The [model](../tests/fixtures/stdlib_foundation/seek_model/README.md)
checks exact results, effects, cursor preservation and complete byte states.
These core gates use `core::io` source `16f3f761`; the [File gates](../tests/fixtures/stdlib_foundation/file_seek/README.md)
use FileOps `ba46d750`. Fault retries corrected test-only stderr/unsigned trace
formatting without production changes. Buffered import now executes (one
probe/6.01s) on source `08212669` after two private nongeneric enum-projection
helpers replaced rejected Reader-body spellings; public generic bounds/state
rules are unchanged.
The initial diagnostic pointed misleadingly at Mapper, while local/simple
imported nested-bound controls execute. No compiler repair or general generic
limitation is claimed. [Buffered fixtures](../tests/fixtures/stdlib_foundation/buffered_seek/README.md)
check exact call/effect order, all-host-call-free pure phases and matching
allocation releases. The retained original-source controls record a narrow
admission dependency, not a broad generic limitation. Earlier stream/file/
buffered receipts keep their source/API scope. Accepted execution is Linux
x86_64 CPU output from the GPU compiler; other targets, direct device execution, automatic
lifetimes and formal proof are unverified. No compiler, ABI or native service
is added.

References: official [Seek](https://doc.rust-lang.org/std/io/trait.Seek.html),
[BufReader](https://doc.rust-lang.org/std/io/struct.BufReader.html) and
[Linux lseek](https://man7.org/linux/man-pages/man2/lseek.2.html).
Lanius explicitly specifies checked fixed memory cursors, fallible Start
acknowledgements and its reader fault policy independently of Rust choices.
