# Borrowed slice splitting and adjacent groups

The [slice-segmentation increment](library-slice-segmentation-plan.md) adds
three generic borrowed cursors: separator-excluding Split, separator-including
SplitInclusive and adjacent-predicate ChunkBy. All eight new library gates and
all four record-summary application groups pass on the finite native Linux
x86_64 profile. The standalone application build and both guide examples pass.
Existing slice/iterator receipts retain their original API/source scope. The
full standard/extended-library goal remains open.

## Factories and iteration capabilities

The checked free functions and cursor types belong to `core::slice`:

```text
split<T,P>(values:View<T>, predicate:&P)
    -> Result<Split<T,P>,ViewError>
split_inclusive<T,P>(values:View<T>, predicate:&P)
    -> Result<SplitInclusive<T,P>,ViewError>
chunk_by<T,P>(values:View<T>, predicate:&P)
    -> Result<ChunkBy<T,P>,ViewError>
```

Each cursor has `borrow()`. Import `core::iter` to use its single canonical
`Iterator<View<T>>` implementation and existing adapters/consumers:

| Cursor | Capability needed to iterate |
| --- | --- |
| `Split<T,P>` | `P: core::iter::Mapper<T,bool>` |
| `SplitInclusive<T,P>` | `P: core::iter::Mapper<T,bool>` |
| `ChunkBy<T,P>` | `P: core::iter::Mapper<core::pair::Pair<T,T>,bool>` |

Factories do not require these Mapper bounds because they invoke no callback.
A descriptor with a non-Mapper predicate type can be constructed, but it cannot
be iterated, even if its range is empty. The iteration implementation supplies
that capability boundary. There is no View forwarding method, duplicate
inherent `next`, new predicate trait or reverse wrapper. None of these cursors
implements `DoubleEndedIterator` or `ExactSizeIterator`; arbitrary stateful
predicate outcomes cannot be inferred from a descriptor's element count.

Every factory validates the complete logical descriptor before reading backing
or calling the predicate. Negative start/length or a mathematical end above
`i32::MAX` returns `ViewError::Bounds`. A valid empty View at start
`i32::MAX` is admitted without backing access. Success captures the descriptor,
cursor position and predicate reference, with no scan or allocation.

This validates logical metadata only. Physical capacity, initialized elements
and live backing remain caller obligations. A later native bounds trap does
not become a factory error. Cursor fields must preserve their constructed
invariants; pulls do not revalidate forged cursor state.

## Partitions

Split omits elements for which the unary predicate returns true. Leading,
adjacent and final separators preserve empty segments. SplitInclusive instead
keeps a matching element at the end of its segment and produces no phantom
segment after a terminal match.

For a predicate matching zero:

| Input | Split items | SplitInclusive items |
| --- | --- | --- |
| `[]` | `[[]]` | `[]` |
| `[0]` | `[[], []]` | `[[0]]` |
| `[1]` | `[[1]]` | `[[1]]` |
| `[0, 1, 0, 0, 2, 0]` | `[[], [1], [], [2], []]` | `[[0], [1, 0], [0], [2, 0]]` |

An empty segment is `Some(empty View)`, not None. A final empty Split item
retains the original end offset. No cursor computes `length + 1` in i32 to
count possible segments.

ChunkBy joins neighboring elements while the pair predicate returns true.
False begins another nonempty group. An equality predicate partitions
`[1, 1, 2, 2, 1]` into `[[1, 1], [2, 2], [1]]`. Empty input yields no group;
a singleton yields itself without a callback. No equivalence, symmetry or
transitivity law is required: the predicate governs only each adjacent pair.

The Rust
[split](https://doc.rust-lang.org/std/primitive.slice.html#method.split),
[inclusive split](https://doc.rust-lang.org/std/primitive.slice.html#method.split_inclusive)
and [adjacent grouping](https://doc.rust-lang.org/std/primitive.slice.html#method.chunk_by)
interfaces are references for partition meanings only. Lanius's callback, alias and lifetime
rules are defined below, using its borrowed Mapper and shallow values.
Every result preserves the original absolute backing offset and actual stride;
the elements remain in place.

## Lazy reads and callback order

Each `next()` scans only as far as the boundary needed for its result and
returns immediately. Split variants call the unary predicate once on each
visited element, in increasing index order. ChunkBy calls the pair predicate
on consecutive left/right indices in that order, including the false boundary
pair. That false pair is not repeated by the next pull.

Completing one cursor over `n` elements makes exactly `n` unary calls or
`max(n - 1, 0)` adjacent-pair calls. Early stopping makes only the calls needed
for the returned prefix. Repeated None performs no reads or callbacks.
Constructors, cursor copies and `borrow()` do not prefetch items or invoke P.
`Take` can limit returned segments, but one segment can still require scanning
the entire remaining range; an item quota does not bound callback work.

The segmentation implementation makes no backing writes, allocation, clone,
destruction or host calls. **Callbacks have their own effects.** A Mapper may
update its own live context or perform allowed host work, so an arbitrary
callback does not make the complete traversal pure or bounded in wall time.
Callbacks receive shallow T values, or a shallow Pair, without cleanup
authority over resources held by the backing.

During a pull, a callback must keep operands/backing alive, leave backing
unchanged and avoid reentering or modifying the cursor. There is no fallible
callback protocol, trap recovery or rollback guarantee in this family.
Storage used by traversal is constant. Complete traversal costs linear work
in visited elements plus the actual callback work.

## Aliases, copies and lifetimes

Between pulls, valid caller writes through aliases and changes to predicate
context are observed by later reads/calls. Already selected boundaries do not
change. Yielded Views retain those boundaries, not a snapshot of their element
values: later permitted writes are visible through already-yielded Views too.

ChunkBy reads both neighboring operands for each callback and retains no T
between pulls. For equality over `[1, 1, 2, 2]`, the first pull reads pairs
`(0,1)` and `(1,2)`, returning the first two elements. If the caller then changes
element 2 to 9, the next pair `(2,3)` observes `(9,2)`. The previous boundary
pair is not rerun, and the next group contains only the new 9.

Copying a leaf cursor forks its position while sharing backing and the same
predicate/context. Stateful callbacks can therefore give the copies different
later partitions. Copying an adapter still shares the cursor reference it
borrows. Keep the predicate and its context at stable addresses while any
cursor can invoke them, and keep backing alive while any cursor or yielded View
is in use. Copies extend neither lifetime nor cleanup authority. Reallocation
or destruction invalidates outstanding views. These rules are caller
conventions, not an enforced borrow checker.

## Binary record-summary program

The [record_summary program](stdlib-record-summary.md) reads bounded binary stdin, splits records inclusively at LF,
removes only that final LF, splits comma fields preserving empties, and uses
ChunkBy to find the longest equal-byte run. CR, NUL, non-UTF-8 bytes and quotes
remain ordinary bytes; this is not a quoted CSV parser. Its TSV header is:

```text
record\tbytes\tfields\tempty_fields\tlongest_run\n
```

Rows contain a one-based record number, content byte count, field count, empty
field count and longest run. Empty stdin emits only the header. An empty record
has one empty field and longest run zero; a final LF adds no phantom record.
One input byte owner and fixed 64-byte row scratch replace per-record/field
copies or an owned record array.

The profile accepts no arguments and admits at most 1 MiB input and 65,536
records before publishing the header. A real extra-byte/EOF read distinguishes
an exact byte-cap fit from excess input. Read attempts are capped at 16,384,
global payload-write attempts at 131,072 and diagnostics at 64; Interrupted
spends an attempt. Status is 0 for success, 2 for arguments/byte/record/call
limits, 3 for I/O or diagnostic failure, and 4 for allocation failure.
Failed SIGPIPE-ignore setup returns 3 without a diagnostic. After output
starts, I/O failure or write-budget exhaustion can leave a confirmed prefix;
diagnostic failure overrides the selected primary status with 3.

## Evidence and supported scope

The frozen source pair is `core::slice`
`cae8804c3348c8a7f52d1a369155d7ed32bcbae2a386500cdbc0bced93076416`
and `core::iter`
`64b673195c1b225d4656331b0b30d6efbfeca479752080a72d54a26b61b3ff50`.
All eight new library gates pass across separate invocations: six native tests
and two capability-rejection groups covering 12 negative fixtures. The
[direct fixtures](../tests/fixtures/stdlib_slice_segmentation/direct/README.md)
execute generic compound/zero-sized elements, exact partitions and callback
traces, invalid/maximum metadata, alias edits and adapter composition. Their
positive fixtures use pure callbacks and full no-host-effects traces.
The [independent model](../tests/fixtures/stdlib_slice_segmentation/model/README.md)
checks 5,496 cases across three families and two actual byte layouts, including
shared stateful predicates, cursor copies, backing edits and saved live Views.
The [resource gates](../tests/fixtures/stdlib_slice_segmentation/resources/README.md)
check scalar backing at two sizes and actual nested owners, complete payloads,
pure traversal phases and exact explicit cleanup. Callback effects remain
separate from library effects; no allocation failure is invented for these
allocation-free cursors.

The record-summary application passes four groups with 94 native process
cases, including 11 reached allocation failures. Its standalone build and both
exact guide examples pass without adding cases to that count. Three selected
old regression tests pass separately and retain their original API scope.

| Receipt under `target/stdlib-work` | Accepted scope |
| --- | --- |
| `slice-segmentation-admission.log` | 1 native test / 5.05s, after a separate 4.37s Rust build: all three cursors over compound `Item { key, Option<bool> }`, generic Iterator helpers, exact partitions/callback totals and a full pure trace |
| `slice-segmentation-direct.log` | 4 gates / 11.76s: two native contract/composition tests and two capability-rejection groups covering 12 negative fixtures; combined with tiny admission, all five direct gates pass |
| `slice-segmentation-model-revised.log` | 1 native test / 8.75s, separate Rust build 0.18s: 5,496 cases, 183,248 pulls, 98,114 items, 313,978 callbacks, 79,326 copies, 26,924 backing edits, 25,464 context edits and 25,152 saved-View observations; seed `0x5e6a0261109` |
| `slice-segmentation-resources.log` | Scalar gate accepted within a 1-pass/1-failure run lasting 6.86s, separate Rust build 1.71s: 4,096/65,536 selected elements, ten pure phases and two exact allocations/releases; the first nested ledger check failed |
| `slice-segmentation-resources-handles-revised.log` | Corrected nested resource gate, 1/1 / 6.62s, separate Rust build 1.78s: 16 selected handles plus seven guards, all 184 payload bytes, five pure phases and 24 exact allocations/releases, inner owners before outer |
| `slice-segmentation-existing-ordering.log` | 1 selected existing ordering contract / 6.59s: metadata rejection and compound payload preservation after sharing the logical validator; separate Rust build 1.22s |
| `slice-segmentation-existing-integration.log` | 2 selected existing slice/iterator tests / 10.75s: 126 chunk/window model commands plus generic, stride and fixed-container composition; separate Rust build 1.66s |
| `slice-record-summary-model.log` | 1 application group / 7.44s: 48 complete-output native model cases on record-summary source `c9f83694` |
| `slice-record-summary-admission.log` | 1 application group / 7.23s: eight admission cases |
| `slice-record-summary-limits.log` | 1 application group / 13.80s: eight limit cases |
| `slice-record-summary-io.log` | 1 application group / 18.49s: 30 I/O cases, including 11 reached allocation failures; all four application groups total 94 native cases |
| `slice-record-summary-build.log`, `slice-record-summary-examples.log` | Documented standalone CLI compile exits 0 with no diagnostics; both exact guide examples exit 0 with 75/56 stdout bytes and empty stderr, separate from the 94-case corpus |

The application's continuous payload-budget fault cases also deny all 64
diagnostic attempts. They observe exactly 131,072 stdout attempts and the full
45-byte limit-message requests, with final status 3 and either no output or the
already-published header. They do not separately establish successful status-2
reporting for that limit. The read-budget case does exercise its successful
status-2 diagnostic. See the [application fixture evidence](../tests/fixtures/stdlib_execution/record_summary/README.md)
for the syscall scope and other exclusions.

The first independent-model attempt stopped at compilation: one receiver type
implemented both unary and Pair Mapper applications and triggered `LNC0027`
at `model.lani:83:12`. Its `slice-segmentation-model.log` records 0 passed /
1 failed in 3.94s, after a separate 1.78s Rust build; it establishes no native
model result. The [existing same-receiver dependency](../tests/fixtures/stdlib_foundation/slice_ordering_dependency/README.md)
has a reduced diagnostic and an executable split-receiver control. The accepted
model uses distinct borrowed wrapper receivers sharing one Context, preserving
all callback and alias observations. Its producer hash starts `511fcff4`;
the public generic factories and production sources remain unchanged.

The first nested resource process exited successfully, but its ledger assumed
a 16-byte Vec handle. The canonical three-word handle is 24 bytes, so the
correct outer reservation is `23 * 24 = 552` bytes. The narrow accepted retry
corrected only that exact reservation check and preserved full payload,
address/extent and cleanup checks. The first process exit alone was not counted
as resource acceptance.

The initial target is native Linux x86_64 CPU output from the GPU compiler.
Other hosts, user-program device execution, automatic lifetime/destruction,
formal verification and additional slice families remain separate. The known
[generic chained Option query limitation](../tests/fixtures/stdlib_compiler_state/text_option_chain/README.md)
has an executing typed-match control; it does not justify specializing the
public segmentation APIs or claiming a general generic failure. The full
library goal remains open.
