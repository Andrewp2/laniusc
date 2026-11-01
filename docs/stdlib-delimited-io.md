# Bounded delimiter I/O

`core::io::BufRead` exposes borrowed unread bytes for binary delimiter reads
and skips. The helpers require only `B: BufRead`; there is no Read supertrait,
text decoding or allocation requirement. All selected library, model,
application and regression gates pass. This [increment](library-delimited-io-plan.md)
is accepted on the finite native profile below; the full library goal stays open.

## API and provider contract

```text
trait BufRead {
    fill_buf(&self) -> Result<View<u8>, Error>
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

`Error` is the existing `core::io::Error`, and View is `core::slice::View`.
`fill_buf` returns unread bytes, filling when necessary. Filling may advance
an inner stream through read-ahead, but does not logically consume bytes.
An empty valid View means EOF for that observation, without a permanent EOF
cache. The provider guarantees its physical backing, native stride and lifetime.

`consume(n)` acknowledges exactly n bytes from that unread range, including
zero; it never refills. Negative/excessive n gives InvalidInput without
consumption. Err acknowledges none and must preserve unread bytes. Success
must return exactly n. Provider state/activity/fault checks still apply.

## Byte limits, calls and endings

- The delimiter is any byte, including NUL. It is included in successful
  progress; bytes after it remain unread. No delimiter or newline is stripped.
- Read admits its complete `valid_range(offset,count)` and both helpers
  reject negative max_calls before provider calls or backing access.
- A zero byte bound gives `Ok({completed:0, ending:Limit})` without provider
  access, even at zero call budget. A nonempty request at zero calls fails
  `LimitExceeded`.
- Reaching the byte cap succeeds with Limit and performs no extra peek.
  A delimiter in the final admitted byte wins over Limit. A valid empty
  provider View gives Eof, retaining earlier completed bytes.
- Every direct fill and consume attempt spends one call, including
  Interrupted. This bounds protocol calls, not inner host attempts or time.
  A fill can read ahead even when no budget remains to consume its bytes.
- Validate all returned View start/length/end metadata before EOF or the
  consume-budget check. Invalid metadata gives InvalidCount without copy or
  consume. After a valid nonempty fill, require consume budget before scanning.
- Retry only Interrupted from fill, against the same budget. Propagate other
  fill errors and every consume error, including Interrupted. No polling,
  implicit flush/close or consumption retry occurs.

Read and skip share one engine. It scans only the remaining admitted prefix,
copies it for read, then consumes it once. Checked i32/u64 range arithmetic
prevents count overflow before additions; skip never requires destination
storage. Actual byte strides and destination sentinels are preserved.

## Progress on failure

Success.completed counts exact consume acknowledgements. Failure.copied is
the actual destination prefix copied, or zero for skip. Failure.consumed
counts only earlier exact acknowledgements; neither field promises rollback.

Copy occurs before consume. For example, copying three bytes followed by an
ordinary consume error returns copied=3 and consumed=0; those provider bytes
remain unread. Callers must account for the visible destination prefix before
deciding how to resume. A nonexact successful consume result gives InvalidCount
and adds no acknowledgement; that nonconforming provider's actual state is
unspecified, so the counts cannot establish safe replay.

## Borrowing and implementations

Treat filled bytes as read-only. End the View borrow before another mutating
operation on the same reader, including consume/refill/read/seek. Keep backing
live and avoid concurrent/reentrant access. Read's destination and provider
storage must be disjoint, valid and exclusively writable/readable as required.
Logical checks cannot prove physical backing; overclaims can trap.

`SliceReader` implements BufRead over its original remaining native-stride
slice, with checked cursor consumption and no allocation.
`alloc::buffered::Reader<R>` implements BufRead under `R: Read`: its existing
fill/consume members now have one canonical trait implementation, with no
inherent aliases. Import `core::io` for the protocol and generic bounds.
Inactive/faulted checks, no EOF cache, Read behavior, unread handoff, fixed
capacity and manual discard remain in the [buffered contract](stdlib-buffered.md).
The inner endpoint and its backing must outlive the borrowed adapter.

## Evidence and target

One native admission test passes in 7.24s:
`target/stdlib-work/delimited-io-admission-first.log`. It executes a BufRead-only
custom provider through generic helpers, plus actual SliceReader and buffered
Reader read-ahead/cleanup. Its separate driver build took 1.78s. Selected
regressions have distinct receipts:

| Scope | Receipt under `target/stdlib-work/` |
| --- | --- |
| Six pure direct scenarios and two missing-BufRead bound rejections | Two tests/7.56s, admission filtered; `delimited-io-contracts-first.log` |
| Independent model: 18,000 cases, two helpers, four stride combinations, two invocations/case | One test/5.64s; `delimited-io-model-amended.log` |
| [Binary record selection](stdlib-select-records.md): model33/limits8/CLI33/I/O17 cases | Four tests/8.51s; `delimited-io-select-records-first.log` |
| Buffered reader/handoff/faults, nested copy, four reached constructor OOM failures, real binary-copy sample | Four tests/9.81s, one writer-only test filtered; `delimited-io-buffered-regressions.log` |
| Existing core_io/alloc_io native fixtures | One test/11.59s, three filtered; `delimited-io-stream-regression.log` |

Direct trace is empty for mmap/mremap/munmap/brk/read/write/close; it does not
trace all host services. The [model](../tests/fixtures/stdlib_foundation/delimited_io_model/README.md)
uses seed `0xde11a0261031`; its initial fixture-only else-if syntax stop
preceded native execution and required no library/compiler repair. The real
program's 91 cases include five reached allocation denials, reader release
before stdout, required-EOF failure without output and a genuine output prefix.
The buffered regression actually ran the sample; it was not filtered.
Earlier receipts retain their scope. [Direct fixtures](../tests/fixtures/stdlib_foundation/delimited_io/README.md)
own exact source identities; current production is core I/O `d2d4d869…` and
buffered `02539487…`.

The accepted profile is Linux x86_64 CPU output from the GPU compiler.
No direct-device, other-target, formal or automatic-lifetime claim follows.
No compiler, ABI or host service is added. The core helpers allocate nothing;
providers retain their own effects, blocking and ownership policies.

Design reference: [Rust BufRead](https://doc.rust-lang.org/std/io/trait.BufRead.html).
Lanius explicitly uses a standalone bound, fallible exact consume
acknowledgements, caller buffers, byte/call caps and separate failure progress.
