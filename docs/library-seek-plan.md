# Portable seek protocol and buffered positions

This increment supplies the missing shared Seek protocol in the full library
roadmap. It includes memory cursors, the Linux File adapter and buffered
readers/writers. Production remains Lanius; no compiler/runtime/ABI/proof work.

## Core API

```text
SeekFrom = Start(u64) | Current(i64) | End(i64)
trait Seek { seek(&self, from:SeekFrom) -> Result<u64,Error> }
offset_position(base:u64, offset:i64) -> Result<u64,Error>
stream_position<S>(&S) -> Result<u64,Error> where S:Seek
rewind<S>(&S) -> Result<u64,Error> where S:Seek
```

Seek success returns the new absolute logical byte position. Start success
must equal its requested position. Errors have no general rollback/position
guarantee: a provider can flush, move or otherwise have effects before failing.
No helper retries Interrupted, allocates, polls or closes. Providers define
whether positions beyond EOF are supported. Read and Write are separate bounds.

offset_position performs mathematical u64 + signed i64, returning InvalidInput
below zero or above u64::MAX. Handle i64::MIN without signed negation overflow;
admit subtraction/addition before executing it. It has no side effects.
stream_position makes exactly one Current(0) seek; rewind exactly one Start(0)
seek and checks exact-zero success, otherwise InvalidCount. Preserve errors.

SliceReader and SliceWriter implement Seek and accept only targets in 0..=length.
Start checks the u64 target before narrowing. Current uses cursor; End uses
length. Validate 0<=cursor<=length before arithmetic; invalid state/target is
InvalidInput with unchanged cursor and backing. Preserve actual byte stride.
Replace the old inherent seek(i32) methods directly; migrate repository callers
without aliases. Existing position()/remaining() inspection retains i32 results.

## File adapter

The implementation for std::file::File belongs in std::file_ops, alongside
existing ReadAt/WriteAt implementations, avoiding a module dependency cycle.
Import that module to select the implementation. The existing low-level
file_ops::seek(offset,Origin) retains Linux-specific Data/Hole behavior.

Check closed owner Host(9) first. Start above i64::MAX is InvalidInput with no
syscall; signed Current/End offsets use the complete i64 domain. Delegate one
ordinary lseek through the existing host engine, without retry or allocation.
Check full-width result before converting to u64; malformed Start acknowledgement
is InvalidCount. Relative host errors map normally. Seeking changes the shared
open-description offset, including duplicates. It never changes file length;
ordinary files permit seeking beyond EOF, and unseekable endpoints report host
errors. Append writes retain their existing host append policy.

## Buffered reader: R:Read and R:Seek

Activity/fault checks precede all inner calls. Inactive is InvalidInput; faulted
is InvalidCount. No automatic recovery or new owner state is added.

- Start/End delegate one seek. Successful Start must acknowledge its target.
  On success discard the unread range, retaining buffer allocation.
- Current first queries inner Current(0). Its result must be >= unread bytes;
  logical position is inner position minus that unread count. Apply checked
  offset_position, then perform one inner Start(target). Even Current(0)
  reconciles read-ahead this way and discards unread bytes on success. The
  query+absolute operation requires exclusive access to the borrowed inner.
- A target-arithmetic rejection after a successful query preserves the unread
  range and active state: no repositioning was requested. Query may have its
  provider-defined effects, although a conforming Current(0) preserves logical
  position. A malformed query position faults the reader.
- Any error from an actual inner seek, or malformed Start acknowledgement,
  faults the reader and clears unread publication. Preserve the primary error;
  do not imply rollback or retry. Allocation/inner ownership remain retained.
  Existing take_parts/discard recover/release the buffer; rebuild explicitly
  after reestablishing the inner position. This includes a failed position query.
- Never read the borrowed View after seeking. No new allocation, implicit close,
  EOF cache or changes to ordinary Read/BufRead behavior.

## Buffered writer: W:Write and W:Seek

Check activity/fault state first, then use the existing complete flush policy
(drain pending bytes and inner flush) before one inner seek. Current therefore
uses the logical position after pending bytes are accepted. Flush failure stops
without seeking and preserves the existing pending-prefix/fault semantics;
successful partial flushing may already have moved the inner cursor.

After successful flush, propagate inner seek errors with an empty pending range;
the wrapper remains active, with no position rollback guarantee. Malformed Start
acknowledgement faults the writer. Successful seek retains the empty allocation.
Never replay already accepted output, and do not close or allocate.

## Acceptance

- Native admission through a Seek-only provider, SliceReader/Writer, File and
  actual buffered composition; missing bounds rejected at marked uses.
- Literal boundaries plus an independent arbitrary-precision model of signed
  offsets, all seek origins, forged states, error preservation and byte strides.
- Scripted buffered read-ahead/flush/seek outcomes, exact call order, failures
  before/after effects, malformed acknowledgements, nested adapters, ownership
  handoff and constructor OOM. Distinguish buffer publication from backing.
- Real File native behavior, duplicate cursor sharing, seek beyond EOF, actual
  unseekable error, closed-owner/high target admission, full-width offsets and
  selected reached syscall errors. No fake successful data-transfer counts.
- A real reverse_records PATH WIDTH program reads fixed-width binary records
  in reverse order through buffered Seek/Read, staging output before publication.
  Validate width1..4096, file<=1MiB, divisible length and <=4096 records; support
  empty input and binary/non-UTF-8 paths. Use End/Start and negative Current
  seeks to exercise logical read-ahead reconciliation. Explicit limits/owners,
  actual output-prefix errors and independent executable model tests.
- Selected existing stream, buffered and file-operation regressions protect the
  changed boundaries; no broad optional GPU reruns. Root serializes native and
  compiler commands with the existing lock; every command is below two minutes.

Preserve root README, AI_POLICY and CONTRIBUTING. Missing compiler support gets
a minimal reproduction/control and dependency record; do not absorb compiler work.
References: [Seek](https://doc.rust-lang.org/std/io/trait.Seek.html),
[BufReader](https://doc.rust-lang.org/std/io/struct.BufReader.html) and
[Linux lseek](https://man7.org/linux/man-pages/man2/lseek.2.html).
The explicit reader fault policy and bounded fixed memory cursors are specified
above independently of Rust's implementation choices.
