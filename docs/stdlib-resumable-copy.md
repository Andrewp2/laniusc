# Resumable byte copying

The [stream-encoding increment](library-stream-encoding-plan.md) adds a borrowed
`core::io::Copier<R,W>` that retains confirmed transfer progress and pending
scratch bytes between calls. The existing blocking `copy` convenience uses
the same transfer engine. All six copier library gates pass on the finite
native Linux x86_64 profile. Earlier stream receipts retain their original
source and API scope; migrated application acceptance is separate.

## API and admission

```text
CopySide = Read | Write | State
CopyStop = Eof | ReadLimit | CallLimit | ReadWouldBlock | WriteWouldBlock
CopyStep { read:u64, written:u64, calls:u64, stop:CopyStop }
CopyStepFailure { cause:Error, read:u64, written:u64, calls:u64, side:CopySide }
copier<R,W>(reader:&R, writer:&W, scratch:View<u8>)
    -> Result<Copier<R,W>,Error> where R:Read, W:Write
Copier.borrow() -> &Copier<R,W>
Copier.read_count() -> u64
Copier.written_count() -> u64
Copier.pending() -> View<u8>
Copier.is_active() -> bool
Copier.is_done() -> bool
Copier.is_faulted() -> bool
Copier.abort() -> View<u8>
Copier.step(read_limit:u64, max_calls:u64)
    -> Result<CopyStep,CopyStepFailure>
```

Construction requires a positive scratch length, nonnegative start and a
mathematical end no greater than `i32::MAX`. Invalid metadata returns
`InvalidInput` before provider calls or backing access. The original descriptor
and actual byte stride are preserved. The caller supplies initialized physical
backing, disjoint live ranges and stable endpoints; logical validation cannot
establish those facts.

Only Read and Write are required. Copying introduces no allocator, flush,
close, seek, polling or host-service operation. Providers retain their own
effects and blocking behavior. The local [stream contracts](stdlib-streams.md)
govern byte acknowledgements. Rust's [copy](https://doc.rust-lang.org/std/io/fn.copy.html)
and [Read](https://doc.rust-lang.org/std/io/trait.Read.html) are comparison
references for copying to EOF and short reads; Lanius specifies its quotas,
retained state and error handling here.

## Progress, quotas and stops

`read` and `written` in every result are **cumulative confirmed byte counts**
since construction. `calls` counts direct Read/Write attempts in **this step**.
The query methods expose the same cumulative counts. A provider error
acknowledges no bytes for that attempt.

Every step drains pending output before reading again. `read_limit` bounds
only newly acknowledged input during that step. It does not cap writes of
already-pending bytes. A zero read quota can therefore drain pending output;
once empty, it returns `ReadLimit`. Reaching a read quota makes no extra EOF
probe.

Each direct provider attempt spends one call, including Interrupted,
WouldBlock, errors and a successful EOF read. Interrupted retries while the
step has allowance. The quota does not count provider-internal calls, bound
their duration or impose a deadline.

| Stop | Meaning and retained state |
| --- | --- |
| `Eof` | A positive-length read returned zero, or that EOF was already recorded; no pending bytes remain |
| `ReadLimit` | This step admitted its allowed new bytes and has no pending output; EOF has not been inferred |
| `CallLimit` | Another provider call would exceed the step allowance; pending output, if any, remains |
| `ReadWouldBlock` | The reader returned WouldBlock; the same state can be resumed explicitly |
| `WriteWouldBlock` | The writer returned WouldBlock; the unacknowledged suffix remains pending |

EOF is permanent for this copier even if the provider could later produce
more input. A short positive read is not EOF. `is_done()` means EOF was
observed, `is_faulted()` means a malformed successful reply was detected, and
`is_active()` means `abort()` has not been called. These facts are independent;
aborting a completed state preserves its recorded EOF.

### Exact precedence

At step entry, these checks run in order without provider calls:

1. Inactive returns `InvalidInput` with side State.
2. Faulted returns `InvalidCount` with side State.
3. Cached EOF returns Eof, even when both quotas are zero.

For pending output, call allowance is checked before writing. For an empty
pending range, the order is new-read allowance, call allowance, then cumulative
read headroom. A new request is:

```text
min(scratch.length, remaining step read allowance, u64::MAX - total_read)
```

Zero headroom returns `CountOverflow`/State without a provider call or a
permanent fault. It does not prove EOF. Thus an empty pending range with both
quotas zero returns ReadLimit, while pending bytes with no call allowance
return CallLimit. Confirmed writes cannot exceed confirmed input, so a valid
write cannot overflow the cumulative written count.

## Errors and malformed replies

Ordinary provider errors return `CopyStepFailure` with the affected Read or
Write side. A successful zero write produces `WriteZero`. Both preserve
resumable state; the caller decides whether another attempt is appropriate.
Provider `Err(InvalidCount)` is also an ordinary error.

An `Ok` count outside `0..=requested` instead permanently faults the copier.
That attempt is counted, but confirmed byte counters and pending metadata
remain at their preceding values. The provider's actual physical effects are
unknown, so those bookkeeping facts do not establish safe replay. Further
steps return `InvalidCount`/State with zero calls. No error rolls back source
consumption or already-published output.

## Pending bytes, abort and lifetime

`pending()` is a read-only live View of the tracked scratch suffix. Its
descriptor and contents are valid only until the next state operation or
caller reuse. The copier neither clones that suffix nor transfers scratch
ownership.

`abort()` marks the state inactive and returns the same tracked span. It
preserves counts, pending metadata and EOF/fault flags. Repeating abort returns
the same span without effects. After ending all state aliases, the caller can
deliberately recover or discard the bytes and reuse its storage. Recovery after
a malformed provider reply still has the physical uncertainty described above.
There is no reset or endpoint-rebinding API.

One active state controls its endpoints and scratch. Copying the value does
not create an independent transfer: keep shallow state aliases inactive.
Do not reenter the copier, use the endpoints through interfering aliases,
modify scratch or invalidate any borrowed backing while the state is active.
No automatic borrow checking, destruction or cleanup is supplied.

## Blocking convenience and composition

`core::io::copy(reader, writer, scratch, capacity)` retains its existing
`Result<u64,CopyFailure>` signature. It drives the same transfer engine,
retries Interrupted and reports WouldBlock or other errors immediately. It
has no useful small total call bound. Its local state is abandoned on return;
use Copier when the caller needs to resume or recover a tracked pending span.

Reads now clip to cumulative counter headroom. The former conservative refusal
of an entire scratch-sized request near `u64::MAX` is not retained. A genuinely
exhausted counter still cannot be used to infer EOF. Neither convenience nor
resumable copying flushes or closes a provider.

A [borrowed JSON Encoding](extended-json-streaming.md) implements Read, so it
can be connected to any conforming Write through this copier. The
[JSON normalizer](extended-json-normalize.md) uses fixed scratch and bounded
steps to publish encoded bytes without a complete output String.

## Evidence and supported scope

The reviewed source is `stdlib/core/io.lani` at SHA-256
`121c3a6271e24e2f7c387e47fc85ee617af93afa23bec786676d325f8a301b0b`.
All six copier library gates pass across separate runs: five native tests and
one group with two capability rejections. The [direct and model fixtures](../tests/fixtures/stdlib_copy/README.md)
check generic providers, exact call order, ordinary error recovery, retained
suffixes/abort, malformed-success faults, quotas and actual strides. Three
pure direct fixtures have complete no-host-effects traces. The independent
FIFO model checks 72 cases and 348 actions across two layouts, including actual
pending-view bytes and full source/output/scratch observations. Its twelve
comparator corruption controls are separate from the native case count.
Seeded near-maximum counters test arithmetic; they transfer only two actual
bytes in the direct witness.

The [resource gate](../tests/fixtures/stdlib_stream_encoding/resources/README.md)
uses live source/sink/scratch owners at 4,096 and 262,144 payload bytes. It
checks the full 4,076-byte retained suffix after a short write and Host(5),
zero-new-read-quota recovery, observed EOF, unchanged guards and provider reuse.
Ten pure phases contain no host calls. All six caller allocations have exact
explicit releases; no allocation failure is invented for the copier.

| Receipt under `target/stdlib-work` | Accepted scope |
| --- | --- |
| `stream-encoding-copy-admission-qualified.log` | Tiny generic native test, 1/1 / 5.45s; separate Rust build 0.19s |
| `stream-encoding-copy-direct.log` | Capability-rejection group accepted within a 1-pass/2-compile-failure run / 4.69s; two independent missing-bound fixtures |
| `stream-encoding-copy-direct-revised.log` | Both corrected positive direct tests, 2/2 / 6.60s; separate Rust build 1.68s |
| `stream-encoding-copy-model.log` | Independent model, 1/1 / 6.62s; 72 cases / 348 actions / two layouts; separate Rust build 0.19s |
| `stream-encoding-copy-resources-revised.log` | Live owners and pending recovery, 1/1 / 6.64s; separate Rust build 0.19s |
| `stream-encoding-regression-stream-contracts.log` | One selected existing stream-contract test / 12.76s; separate Rust build 1.94s, outside new-gate counts |
| `stream-encoding-regression-native-copy.log` | One selected existing binary-copy/host-failure test / 6.15s; separate Rust build 0.19s, outside new-gate counts |

The first tiny admission stopped before runtime because unqualified Eof was
ambiguous with the existing delimiter variant.
`stream-encoding-copy-admission.log` records 0 passed / 1 failed in 2.38s.
Qualifying the new variant matches changes no contract and establishes
no compiler dependency; the accepted retry above uses the corrected source.
The first broader direct command accepted its capability-rejection group but
two positive fixtures stopped at compilation because their trace helper needed
an explicit `isize`-to-`i64` cast. The first combined resource run accepted both
JSON gates but rejected the copier fixture's implementation visibility before
execution (`LNC0021`); its result was 2 passed / 1 failed in 11.61s, after a
separate 1.77s Rust build, in `stream-encoding-resources.log`. The narrow retry
fixed only fixture visibility. These fixture corrections change no production
code; the initial mixed commands are not wholly passing receipts.

The initial runtime target is native Linux x86_64 CPU output from the GPU
compiler. User-program device execution, other hosts, enforced lifetimes and
formal verification remain separate. The historical imported-helper
[copy reduction](../tests/fixtures/stdlib_foundation/stream_copy_dependency/README.md)
records an older forwarding shape; this increment does not by itself establish
whether that exact source is repaired. The full library goal remains open.
