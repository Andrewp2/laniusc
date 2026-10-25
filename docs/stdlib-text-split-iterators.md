# Text split cursors

`core::text::Split` and `core::text::SplitAsciiWhitespace` implement
`core::iter::Iterator<core::text::Text>`. Both provide `borrow()` for the
existing generic consumers and borrowed adapters. Their constructors remain
`Text.split(separator)` and `Text.split_ascii_whitespace()`.

```lanius
let fields: core::text::Split = text.split(separator);
let prefix: core::iter::Take<core::text::Split, core::text::Text> =
    core::iter::take<core::text::Split, core::text::Text>(fields.borrow(), 2);
let first: core::option::Option<core::text::Text> = prefix.next();
```

Each cursor has one `next()` implementation, through the shared trait. Direct
`cursor.next()` calls and generic functions bounded by `Iterator<Text>` use
the same state and splitting behavior. The integration moves the existing
method bodies without changing their algorithms. See the
[shared iterator contract](stdlib-iterators.md),
[borrowed adapters](stdlib-iterator-adapters.md), and
[Text validity rules](stdlib-text.md).

## Fields and words

`Split` consumes nonoverlapping occurrences of a valid UTF-8 separator and
retains leading, interior and trailing empty fields. Empty input with a
nonempty separator yields one empty field. An empty separator yields a leading
empty field, one field per Unicode scalar, then a trailing empty field. Empty
input with an empty separator therefore yields two empty fields. Scalar fields
are not grapheme clusters; combining marks remain separate scalars.

`SplitAsciiWhitespace` skips exactly HT, LF, VT, FF, CR and space: byte values
9, 10, 11, 12, 13 and 32. It yields maximal nonempty words. Empty input and
input consisting only of these six bytes yield no words. NUL, non-ASCII
whitespace, BOM and other valid UTF-8 bytes remain in their fields. There is
no normalization or Unicode whitespace policy.

Both cursors return `Option<Text>` and are fused: after `None`, later calls
remain `None`. A returned Text is a borrowed subview with its original byte
stride and absolute backing offset. Ordinary Lanius byte arrays and packed
byte views work, including selected ranges that start inside the backing.

## Generic consumption and copies

`Take`, `Chain`, `Map` and bounded consumers accept either cursor. A chain can
combine the two different cursor types because both yield Text. A
`Mapper<Text, i32>` can transform fields into byte counts; the mapper is called
once for each yielded field and is not called for exhaustion. Empty fields
still count as items and invoke the mapper with byte length zero.

`Take` with quota zero makes no source call. Reaching its quota consumes no
extra field, so the next direct source pull returns the first field beyond
that quota. Exhaustion latching and adapter copy rules remain those of
`core::iter`.

Copying a split cursor copies its position and flags, giving independent
traversal over the same borrowed bytes. Copying an adapter retains its borrowed
source reference: the copies have separate local adapter state while pulling
from one shared cursor. Reassigning the original Text descriptor does not
change a cursor's captured view.

Keep each cursor object alive through every adapter that borrows it, and keep
the input backing alive and unchanged through the cursors and all yielded
fields. `Split` also borrows its separator's backing. An owning String must
not be mutated, reallocated or destroyed while these borrows are in use; create
fresh views and cursors after such an operation. Copying a cursor or yielded
Text neither copies the bytes nor extends their lifetime. Lanius does not yet
enforce these borrow rules. Cursor state and Text metadata must retain their
constructor-established invariants.

Splitting, cursor copying and the adapters allocate no storage and invoke no
host services themselves. A caller's mapping function can add its own effects.
There is no automatic owner destruction or ownership transfer for yielded
items.

## Verification

`tests/stdlib_text_split_iterator_execution.rs` defines two native gates, each
with the existing strict ELF/jump check. The contract fixture exercises generic
pulls, Take quotas, independent leaf copies, shared adapter copies, mixed-type
Chain/Map composition, mapper call counts, repeated exhaustion, Unicode scalar
splitting and all six whitespace bytes. It also checks returned view offsets
and strides over packed and ordinary arrays with invalid sentinel bytes outside
the selected UTF-8 ranges. Its `mmap`, `mremap`, `munmap` and `brk` syscall trace
was empty.

The model fixture batches 1042 records from 148 deterministic input/separator
configurations, both backing layouts, and zero, partial, exact and overlong
quotas into one native execution. Its driver compares complete returned field
bytes, bounded source consumption, remaining mapped lengths, mapper call
counts and an independent copied cursor. Rust's `str::split` supplies the
explicit-separator oracle; the whitespace oracle uses the six-byte predicate
above, including VT. The source
fixtures are under `tests/fixtures/stdlib_foundation/text_split_iterators/`.

Both focused groups passed on 2026-10-24 in 8.53 seconds: two strict ELF/jump
checks, two native executions and all 1042 model commands. A combined Rust
build of this driver and the slice probe took 1.23 seconds. Logs are
`target/stdlib-work/cursor-integration-admission/text-splits.log` and
`target/stdlib-work/cursor-integration-admission/build-probes-and-text.log`.
The gate used compiler `0519160c2a8cd934d36fe0f513e2f2b26bb02283` with the
uncommitted standard-library cursor integration; this milestone made no
compiler changes. Independent source review also checked that both moved
`next()` bodies remained unchanged.

The recorded invocation from the repository root was:

```sh
timeout --kill-after=2s 100s \
  flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s \
  env RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
  target/stdlib-build/debug/deps/stdlib_text_split_iterator_execution-c9f2fa3bc8fe40f8 \
  --test-threads=1 --nocapture \
  >target/stdlib-work/cursor-integration-admission/text-splits.log 2>&1
```

This evidence covers the existing x86_64 Linux native CPU target, compiled by
the GPU compiler. It makes no claim about user-program GPU execution or
performance.
