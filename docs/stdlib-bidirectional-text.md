# Borrowed lines and bidirectional text traversal

This guide records the [bidirectional text increment](library-bidirectional-text-plan.md):
`Text.lines()` and backward pulls for the existing scalar and ASCII-word
cursors. All seven new library gates pass: six native tests and one group of
three ExactSize capability rejections. The canonical Unicode-report stdin
regression and all four line-summary groups/102 native cases also pass, as do
the standalone build and documented examples. This finite native Linux x86_64
increment is accepted. Earlier Text/iterator receipts retain their original
API/source scope. The full standard/extended library goal remains open.

## Interface and shared state

| Text factory | Cursor | Item | Shared capabilities |
| --- | --- | --- | --- |
| `lines()` | `Lines` | `Text` | `Iterator<Text>`, `DoubleEndedIterator<Text>` |
| `scalars()` | `Scalars` | `Scalar { byte_index, value }` | `Iterator<Scalar>`, `DoubleEndedIterator<Scalar>` |
| `split_ascii_whitespace()` | `SplitAsciiWhitespace` | `Text` | `Iterator<Text>`, `DoubleEndedIterator<Text>` |

Each cursor provides `borrow()`. Its `next()` and `next_back()` belong to the
canonical [iterator traits](stdlib-iterators.md#double-ended-traversal);
there is no second inherent implementation or separate reverse cursor type.
Generic callers require both `Iterator<T>` and `DoubleEndedIterator<T>` when
they use both directions. `core::iter::Rev` swaps those directions, and `Take`
can bound forward pulls from a Rev. The existing generic adapters and consumers
use the same cursor state as direct method calls.

Front and back consume one common remaining sequence. Interleaving them never
returns an item twice or crosses the opposite frontier. None from either end
permanently exhausts both ends. Copying a leaf cursor forks its position over
the same immutable bytes. Copying a borrowed adapter preserves its reference
to the original cursor; it does not fork that source's remaining sequence.

These three cursor families do **not** implement `ExactSizeIterator`. Counting
remaining lines, words or Unicode scalars requires scanning bytes. A byte count
does not establish an item count. Existing byte iteration has its own contract.
The arbitrary-separator `Split` cursor keeps its forward partition and is
outside this reverse increment.

## Lines

`Lines` partitions at LF (`0A`) and CRLF (`0D 0A`) and excludes the consumed
terminator from each returned Text. A CR is removed only immediately before
that LF. A lone CR remains content, as do NUL, NBSP, Unicode line/paragraph
separators, BOM and noncharacters. There is no Unicode line-breaking policy.
This profile follows the [Rust `str::lines` contract](https://doc.rust-lang.org/std/primitive.str.html#method.lines).

| Input bytes, with escapes | Forward items |
| --- | --- |
| `""` | `[]` |
| `"\n"` | `[""]` |
| `"\r\n"` | `[""]` |
| `"A\n"` | `["A"]` |
| `"A\n\n"` | `["A", ""]` |
| `"\nA"` | `["", "A"]` |
| `"A\rB\r\nC\r"` | `["A\rB", "C\r"]` |

Empty text has no line. Leading and repeated terminators create empty lines;
a final LF creates no extra trailing item. Backward pulls consume this exact
forward-defined partition in reverse. For example, `A\n\nB\n` permits front
`A`, back `B`, then an empty line from either end, followed by permanent None.
Changing pull direction cannot reintroduce a trailing phantom line or strip
a lone CR.

## Scalar indices

`Scalars` yields the existing Scalar record. Its `value` is a Unicode scalar;
its `byte_index` is relative to the **original selected Text**, regardless of
pull direction. An offset into a larger backing array does not alter that
origin. Returned indices do not become relative to a shrinking remainder.

For `Aé🦀Z`, the original scalar byte indices are `0, 1, 3, 7`. A back/front/
back/front schedule yields `(7, Z)`, `(0, A)`, `(3, 🦀)`, `(1, é)`, then None
from either end. Combining marks are separate scalars; this is not grapheme
reversal. Reverse traversal finds a valid UTF-8 lead boundary and uses the
existing core UTF-8 helpers. It adds no second codec or validation pass.
[RFC 3629](https://www.rfc-editor.org/rfc/rfc3629) describes the byte structure
that keeps ASCII delimiter bytes outside multibyte scalar interiors.

## ASCII words

`SplitAsciiWhitespace` keeps the existing six separators:

| Byte | Name |
| --- | --- |
| `09` | Horizontal tab |
| `0A` | Line feed |
| `0B` | Vertical tab |
| `0C` | Form feed |
| `0D` | Carriage return |
| `20` | Space |

It yields maximal nonempty words. Empty text and text containing only those
six bytes have no words. NUL and non-ASCII whitespace remain inside words.
Backward traversal uses the same predicate and partition as forward traversal;
there is no new Unicode-whitespace or host-language splitting policy.

Returned lines and words preserve the source's actual byte stride and selected
backing offsets. They are borrowed views, with no per-item copy or owner.

## Lifetime, effects and cost

Input must already be valid Text. Use the existing checked
[Text constructors](stdlib-text.md#construction-and-lifetime) for untrusted
bytes. Cursor constructors only capture descriptors and scalar positions.
They do not scan or access backing, including for empty valid views. Traversal does not
allocate, call host services, write backing, normalize text, revalidate UTF-8,
clone owners or destroy them.

Keep the backing alive and unchanged while any cursor, adapter or yielded Text
remains in use. Keep a cursor object alive while an adapter borrows it. Copying
one of these values extends neither backing lifetime nor cleanup authority.
Do not mutate, reallocate or destroy an owning String under a live borrow;
make new views afterward. These are caller obligations, not language-enforced
immutable borrows. Forged Text/cursor fields do not gain checked validity from
a traversal method, and physical traps have no rollback promise.

Cursor storage is constant. A complete traversal in any mixed-end schedule is
linear in input bytes: scanning advances the corresponding frontier instead
of rescanning earlier prefixes. An individual word or line pull can inspect
the full remaining text. Scalar decoding examines at most one UTF-8 scalar
per successful pull. These bounds describe traversal work, not host time or
effects introduced by a caller's separate callback.

## Programs and executable evidence

The migrated [Unicode report](../sample_programs/unicode_text_report.lani)
uses backward borrowed scalar traversal and core UTF-8 encoding into bounded
stack output staging. Its existing byte/scalar-count header, scalar-reversed
output and input/error profile remain the contract. The input String remains
unchanged; no temporary reversed String or destructive pop loop is needed.

The new [line_summary program](stdlib-line-summary.md) reads bounded UTF-8 stdin
and emits one TSV record per line in source order. It combines line traversal, a backward word
pull followed by forward word counting, and a backward scalar pull. Its five
columns are one-based line number, bytes, word count, last-word bytes and final
Unicode scalar value (`-1` for an empty line). One input owner and fixed output
scratch replace per-line/per-word owned copies.

The frozen application profile admits 1 MiB input, 65,536 lines, 16,384 read
attempts, 131,072 payload-write attempts and 64 diagnostic attempts. Complete
UTF-8 and line-count validation precedes the header; a real extra-byte/EOF
probe distinguishes exact byte-cap input from excess input. Interrupted calls
spend an attempt. Exit status is 0 for success, 2 for argument/UTF-8/input/line/
call limits, 3 for I/O including signal/diagnostic failure, and 4 for allocation.
If establishing SIGPIPE-ignore policy fails, the program returns 3 immediately
without attempting a diagnostic. Other errors after successful signal setup
use the application guide's bounded diagnostics.
Once output starts, an I/O failure or payload write-call exhaustion may leave
a confirmed stdout prefix. Exhausting that call budget selects status 2,
unless diagnostic failure overrides it with 3.

Source `7c25a62d18fff3521473968e731f00d3d7d6249a6a63665f518f1dbf6a4bf446`
passes all seven new library gates below. They check exact items and original
indices under mixed pulls and copies, both actual backing layouts, unchanged
guards, repeated exhaustion, generic Rev/Take composition and an independent
partition model. Three direct native fixtures pass full-syscall observation.
Owned-backing gates check live owners, early stops and explicit final release.
Borrowed traversal has no allocation site to fault. The four line-summary
groups separately check 102 native cases, including 11 reached allocation
failures. These make 11 new registered gates in total. The two selected older
Text groups and canonical Unicode-report stdin regression add three separate
current regressions. Standalone build/examples add no test or case count.
Earlier text, scalar and split receipts keep their original API/source scope.

| Receipt under `target/stdlib-work` | Accepted scope |
| --- | --- |
| `text-bidirectional-admission.log` | 1 native test / 5.59s, after a separate 2.08s Rust build: all three cursors, mixed ends, CRLF, offset scalar indices and a full trace with no intervening host effects |
| `text-bidirectional-direct-final.log` | 1 accepted capability-rejection group: Lines, Scalars and SplitAsciiWhitespace each reject an ExactSize requirement with LNC0008; the 7.59s combined run also had two fixture compilation failures and is not a three-test pass |
| `text-bidirectional-direct-revised.log` | 2 native tests / 7.99s: exact partitions/indices/strides, 720 literal cursor traversals, full backing/guards, Rev/Take and bounded generic composition, copies and exhaustion; both full traces have no intervening host effects |
| `text-bidirectional-model.log` | 1 independent native model / 5.87s: 4,878 cases, three cursor families, two actual layouts, 276,732 pulls, 129,686 items and 77,262 cursor copies |
| `text-bidirectional-existing-model.log` | 1 selected existing forward Text test / 8.23s: validation, search, splitting and scalar reference models against the revised source; the rest of that old suite was not rerun by this receipt |
| `text-bidirectional-existing-words.log` | 1 selected existing composition test / 10.10s: join, repeat and six-separator word models; the rest of that old suite was not rerun by this receipt |
| `text-bidirectional-resources.log` | 2 native tests / 12.07s: 4,096/262,144-byte live owners, eight pure traversal phases and exact two mappings/releases; the migrated report checks complete scalar reversal, four input-preservation phases, fixed 4,096-byte staging, no report allocation/release and reached write-6 EIO with same-process recovery |
| `text-bidirectional-report-stdin.log` | 1 selected canonical Unicode-report stdin test / 6.64s: existing input validation and scalar-reversed output profile on the migrated source |
| `text-line-summary-model.log` | 1 application group / 7.73s: 44 complete-output model cases |
| `text-line-summary-admission.log` | 1 application group / 7.27s: 20 admission cases |
| `text-line-summary-limits.log` | 1 application group / 11.84s: eight limit cases |
| `text-line-summary-io-revised.log` | 1 application group / 17.11s: 30 I/O cases, including 11 reached allocation failures, cleanup, exact fault prefixes and bounded output/diagnostic attempts |
| `text-line-summary-cli.log` | Documented standalone compiler command exits 0 |
| `text-line-summary-examples.log` | Both documented examples produce the exact 83/56-byte stdout, exit 0 and leave stderr empty |

The report resource gate invokes the canonical report function over live owned
input; its allocation ledger excludes the caller's two setup mappings from
the allocation-free reporting phase. Each resource process matches its two
setup mappings with exact releases. The separate stdin receipt above checks
input capture and the existing error profile. Borrowed-owner coverage is not
an allocation-failure campaign for traversal, which acquires no owner.

The first application I/O attempt stopped because strace rejected its finite
ordinal syntax; the revised test uses supported continuous injection without
changing production source. Continuous payload faults observe all 131,072
stdout attempts, followed by all 64 denied diagnostic attempts and the exact
requested output-limit message. They establish selection of the payload-limit
branch, optionally after a retained header, with final status 3. They do not
directly exercise successful status-2 output-limit reporting. Application source
and test details belong to the separate [program guide](stdlib-line-summary.md).

The first remaining-direct run rejected chained generic
`cursor.next().is_none()` and `next_back().is_none()` expressions with LNC0027.
Those fixtures never reached native execution. Explicitly typed Option locals
and direct pattern matches retain the same traversal/pull assertions and pass
in the revised run. Production Text and compiler sources did not change for
that test correction. The [reduced compiler pair](../tests/fixtures/stdlib_compiler_state/text_option_chain/README.md)
executes its typed-match control with a complete pure trace, then rejects the
chained `next().is_none()` at line 7 with LNC0027. Its positive-expected ignored
probe correctly remains failing: 0 passed / 1 failed in 4.79s, logged in
`target/stdlib-work/text-option-chain-dependency.log`. That diagnostic run is
separate from the seven accepted library gates. It establishes this expression
dependency without claiming a general Option/iterator failure or a compiler
root cause.

The initial execution target is native Linux x86_64 CPU output from the GPU
compiler. Other hosts, user-program GPU execution, automatic lifetime/owner
enforcement and formal verification remain separate. Generic predicate-based
slice segmentation is an ordinary main-library gap outside this increment.
