# Buffered byte protocol and bounded delimiter operations

This increment fills a streaming-interface gap in the full library roadmap.
`core::io` owns the portable protocol and helpers; `alloc::buffered` supplies
an allocating adapter. No compiler, runtime, ABI or proof changes are included.

## Public contract

```text
trait BufRead {
    fill_buf(&self) -> Result<core::slice::View<u8>, Error>
    consume(&self, count:i32) -> Result<i32, Error>
}
DelimiterEnd = Delimiter | Eof | Limit
Delimited { completed:u64, ending:DelimiterEnd }
DelimiterFailure { cause:Error, copied:i32, consumed:u64 }
read_until<B>(reader:&B, delimiter:u8, destination:[u8], offset:i32,
              count:i32, max_calls:i32) -> Result<Delimited,DelimiterFailure>
skip_until<B>(reader:&B, delimiter:u8, byte_limit:u64,
              max_calls:i32) -> Result<Delimited,DelimiterFailure>
```

Both helpers require only `B: BufRead`. There is no implicit Read supertrait
or allocation requirement. Normal stream types can implement Read separately.
No text decoding, newline stripping or String/Vec allocation is implied.

`fill_buf` returns the current unread bytes, filling when needed. Empty means
EOF for that observation; EOF need not be permanently cached. Merely filling
does not logically consume bytes, although an adapter can read ahead from its
inner stream. A valid result has nonnegative start/length and nonoverflowing
i32 end; its backing, native stride and lifetime are provider guarantees.
The caller treats returned bytes as read-only and ends the borrow before
another mutating operation on that reader. No concurrent/reentrant access.

`consume(n)` acknowledges exactly n bytes from the last unread range, including
zero. Negative or excessive n is InvalidInput and consumes nothing. Err
acknowledges no logical consumption. Success must return exactly n. It never
refills the underlying stream. Existing reader activity/fault checks still
apply. Providers must retain unread contents on failed consume.

## Helper semantics

- Delimiter is one arbitrary byte, including NUL/non-UTF-8. A found delimiter
  is included in copied/consumed progress. Later bytes remain unread.
- `read_until` fills at most the specified destination range; `skip_until`
  consumes at most byte_limit. Reaching that bound returns Limit without an
  extra EOF/delimiter probe. A delimiter in the final admitted byte wins over
  Limit. An empty provider view gives Eof, retaining prior completed bytes.
- Destination ranges use `valid_range`; negative max_calls is InvalidInput.
  Validate these before any provider call or backing access. A zero byte bound
  returns completed=0/Limit without provider access, even when max_calls=0.
- max_calls counts every direct fill_buf and consume attempt, including
  Interrupted. Before either call, exhausted budget fails LimitExceeded.
  After a nonempty fill, require budget for consume before scanning/copying.
  Filling can therefore read ahead without consuming when the last call is
  exhausted. This is a call budget, not a wall-clock timeout or host-call cap.
- Retry only Interrupted from fill_buf, against the same call budget.
  Propagate other fill errors and every consume error, including Interrupted.
  Do not poll, flush, close or retry consumption implicitly.
- Validate all logical provider View metadata before reading it; malformed
  metadata is InvalidCount with no copy/consume. Physical overclaims can trap.
- Scan only the remaining admitted byte prefix, copy it before consume, then
  require exact consume acknowledgement. Successful completed counts logical
  consumption. Output and provider storage must be disjoint and valid; copies
  preserve actual native byte strides and surrounding destination sentinels.
- Failure.copied is the destination prefix actually copied (zero for skip).
  Failure.consumed is the sum of prior exact consume acknowledgements. Thus a
  consume error can leave copied > consumed with those bytes still unread.
  A malformed consume return gives InvalidCount, records no new acknowledgement
  and leaves actual provider state unspecified. Do not infer rollback or safe
  retry for a nonconforming provider. Earlier progress is never undone.
- Check/derive additions before execution. For read, the whole i32 destination
  span is admitted first. For skip, each consume amount fits both the current
  View and remaining u64 limit, preventing total overflow.

One private engine should serve read and skip with a copying policy; do not
maintain two subtly different retry, admission and progress state machines.

## Implementations and integration

SliceReader implements BufRead over its remaining original native-stride
slice, with checked consumption and no allocation. Its valid initial backing
and owner lifetime remain caller preconditions.

Move the existing Reader<R>.fill_buf/consume behavior in alloc::buffered into
its BufRead implementation (R:Read), using shared private helpers if necessary.
Keep one public protocol member for each operation rather than compatibility
aliases. Preserve reader inactive/faulted checks, no EOF cache, unread handoff,
Read behavior, fixed buffer capacity, manual discard and borrowed inner lifetime.
Adapt repository callers/imports if trait visibility requires it.

## Verification and real program

- First native protocol admission: a BufRead-only custom provider through a
  generic helper, then actual SliceReader and alloc::buffered::Reader.
- Direct runtime assertions for binary delimiters, short fills, both actual
  byte strides, resumption, EOF, exact limits and zero/no-provider paths.
- Independent bounded state-model cases for chunking, fill interruption/error,
  consume error/malformed returns, exact call budgets, progress and sentinels.
- Provider failures must be reached; do not replace real success with fabricated
  transfer counts. Separate logical consumption from inner read-ahead.
- Selected existing buffered-reader/composition/allocation and stream gates
  protect the shared adapter changes; avoid broad unrelated GPU reruns.
- A real binary record-selection program uses both read_until and skip_until
  on buffered stdin, bounded records/input/calls/output, exact binary output,
  explicit failure/cleanup and executable independent-model/edge tests.

Root serializes all Cargo/compiler/native commands with the existing lock.
Each command is under two minutes. Other agents perform static/CPU-only work.
Preserve root README, AI_POLICY and CONTRIBUTING. Missing compiler support gets
a minimal reproduction/control and dependency record, without compiler work.

Reference: [BufRead's fill/consume and delimiter operations](https://doc.rust-lang.org/std/io/trait.BufRead.html).
Lanius adds checked consume acknowledgements, caller buffers, byte/call limits,
explicit ending reasons and separate copied/consumed failure progress.
