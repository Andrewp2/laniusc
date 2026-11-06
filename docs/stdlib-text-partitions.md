# Literal text partitions

`core::text::Text` can split once, split from either direction, limit the number
of fields, and report rightmost match indices. These operations borrow valid
UTF-8 and allocate no storage. The accepted execution target is Linux x86_64,
with native programs compiled by the GPU compiler.

## Public API

All arguments named `separator` or `needle` have type `Text`. Indices and
lengths count bytes. `max_fields` has type `u64`.

| Method on `Text` | Return type | Behavior |
| --- | --- | --- |
| `split_once(separator)` | `Option<Pair<Text,Text>>` | Split at the leftmost match |
| `rsplit_once(separator)` | `Option<Pair<Text,Text>>` | Split at the rightmost match |
| `rmatch_indices(needle)` | `RMatchIndices` | Rightmost nonoverlapping matches, each a `Pair<i32,Text>` |
| `rsplit(separator)` | `RSplit` | Rightmost nonoverlapping fields, yielded from right to left |
| `splitn(separator, max_fields)` | `SplitN` | At most `max_fields` fields, selected from left to right |
| `rsplitn(separator, max_fields)` | `RSplitN` | At most `max_fields` fields, selected from right to left |

The existing `split(separator)` and `match_indices(needle)` choose matches
from left to right. `find(needle)` and `rfind(needle)` return optional offsets
relative to the selected Text, even when that Text begins inside a larger
backing slice.

Matching compares literal UTF-8 bytes. It performs no normalization, case
folding, locale comparison, or grapheme segmentation. NUL, BOM, combining
marks, and noncharacters remain ordinary valid text. Both the source and the
separator must satisfy the [Text validity rules](stdlib-text.md).

## Direction, overlaps, and one split

`split_once` and `rsplit_once` return `None` when the separator is absent.
Otherwise, `Pair.first` is the source prefix and `Pair.second` is its suffix.
The selected separator is excluded from both views. The pair remains in
source left/right order for both methods.

For source `"ababa"` and separator `"aba"`:

| Operation | Result |
| --- | --- |
| `split_once` | `Some(Pair { first: "", second: "ba" })` |
| `rsplit_once` | `Some(Pair { first: "ab", second: "" })` |
| `match_indices` | Match at byte 0 |
| `rmatch_indices` | Match at byte 2 |
| `split` | `"", "ba"` |
| `rsplit` | `"", "ab"` |

After choosing a nonempty match, a reverse cursor restricts further searches
to the prefix before that match. This defines a rightmost nonoverlapping
partition. Reversing a leftmost match list can produce a different partition
when possible matches overlap.

Each `rmatch_indices` item contains the relative byte offset in `Pair.first`
and a borrowed view of the matched source bytes in `Pair.second`. Its indices
decrease. The matched view borrows the source, regardless of the needle's
storage layout or whether the needle aliases the source.

Unbounded splitting retains leading, interior, and trailing empty fields.
If a nonempty separator is absent, splitting yields the whole source once;
for empty input this is one empty field.

## Empty separators and field limits

An empty needle matches every Unicode scalar boundary, including both ends.
For `"Aé界😀"`, the reverse match offsets are `10, 6, 3, 1, 0`.
They are byte offsets, not scalar ordinals. The matched views are empty.

An empty separator gives `split_once` the pair `("", source)` and
`rsplit_once` the pair `(source, "")`. `rsplit` yields a trailing empty field,
each scalar in reverse order, then a leading empty field. Thus `"Aé界😀"`
produces `"", "😀", "界", "é", "A", ""`. Empty input with an empty
separator produces two empty fields. Combining marks and ZWJ sequences may
span several scalar fields.

`splitn` and `rsplitn` limit fields, rather than separator matches:

- Zero yields no fields. Construction and `next()` do not read backing bytes.
- One yields the entire source once, without searching for a separator.
- For larger limits, each selected separator consumes one field slot. The last
  allowed field is the unsplit remainder, including any separators within it.
- If the ordinary split ends sooner, the bounded cursor ends with it. It does
  not add fields to reach the limit.

For source `"key::value::tail"`, separator `"::"`, and limit 2, `splitn`
yields `"key", "value::tail"`; `rsplitn` yields `"tail", "key::value"`.
With an empty separator and limit 2, the results are `"", source` and
`"", source` respectively: the first empty field belongs to the chosen end,
and the second field contains all source bytes. Their view offsets still
distinguish the leading and trailing empties.

Every `u64` limit is accepted, including `u64::MAX`. There is no signed
conversion of the quota. Zero and one still require valid Text descriptors
and backing lifetimes; they do not make invalid or expired views safe.

## Iterator capabilities and lifetime

`RSplit`, `SplitN`, and `RSplitN` implement `Iterator<Text>`.
`RMatchIndices` implements `Iterator<Pair<i32,Text>>`. Each exposes `borrow()`
for the [shared adapters and consumers](stdlib-iterators.md). Direct `next()`
and generic iteration use the same implementation.

All four cursor types are fused: after `None`, every later `next()` returns
`None`. None of these cursors supplies `DoubleEndedIterator` or `ExactSizeIterator`.
Directional overlap choices prevent treating rightmost partitioning as the
back end of an ordinary leftmost cursor, and determining a field count can
require searching bytes. A field limit is an upper bound, not an exact count.

Copying a cursor copies its current position and flags. The copies traverse
independently over the same borrowed bytes. Reassigning the original Text
variable does not retarget an existing cursor. `Take` with quota zero does not
pull its source; reaching a positive quota leaves the next field available
through the original cursor. Copies of a borrowed adapter still refer to the
same source cursor, under the [adapter rules](stdlib-iterator-adapters.md).

Returned Text views preserve the source byte slice, signed stride, and absolute
backing offset. They do not own storage. Keep source and separator backing
alive and unchanged through cursor use, and keep source backing alive and
unchanged through every yielded view. A borrowed adapter also requires its
cursor object to remain alive. Do not mutate, reallocate, or destroy an owning
String while its views are in use. Cursor or Text copies neither copy bytes nor
extend their lifetime. Lanius does not yet enforce these rules.

Use the constructors and preserve their metadata and cursor invariants.
Partition methods do not revalidate UTF-8 or return a new validation error.
Malformed descriptors, expired backing, or mutation during traversal violate
their preconditions. Validate external bytes with `from_utf8` or
`from_utf8_range`; an integer range error returns `Bounds`, malformed encoding
returns `InvalidUtf8`, and a physical backing overclaim can trap. See the
[construction contract](stdlib-text.md#construction-and-lifetime).

## Search storage and effects

`Text.find` and `Text.rfind` both use `core::search`. Its byte scanners now
select word-at-a-time search only for byte stride `+1`. Other strides use
logical indexed bytes in the requested direction. This correction belongs in
the shared byte scanners: `find`, `rfind`, and `count` use them, so Text does
not need a separate storage-layout workaround. Needle comparisons already use
indexed bytes.

The packed search path retains its existing word scanning, rare-byte
prefilter, and Two-Way fallback. This increment records correctness evidence;
it does not add a throughput benchmark or a performance claim. The accepted
storage layouts are packed ascending bytes (`+1`) and native descending byte
array slots (`-8`) on the tested x86_64 target. The fallback is written in terms
of indexed slices, but a positive stride greater than one has no public byte
slice constructor in this test scope and was not executed.

At the lower-level `core::search` API, ranges remain logical `[from, to)` byte
indices, and callers must provide physical backing for the source and needle
ranges. Empty byte needles match all byte boundaries; empty Text needles match
scalar boundaries. This distinction matters for multibyte UTF-8.

These partition methods store only descriptors and cursor state. They allocate
and release no source storage, perform no I/O, and transfer no cleanup
authority. The returned views need no destruction. Caller callbacks or owning
collections composed with the cursors can have their own effects.

## Accepted execution evidence

The integration driver is
[`tests/stdlib_text_partitions_execution.rs`](../tests/stdlib_text_partitions_execution.rs).
Its [fixtures](../tests/fixtures/stdlib_text_partitions/README.md) contain the
direct contracts, independent Unicode model, allocation observer, and eight
negative capability cases.

| Gate | Accepted result | Test time | Log |
| --- | --- | --- | --- |
| Direct contracts and search regressions | 1 passed; zero source allocations/releases | 7.07 s | `target/stdlib-work/text-partitions-direct.log` |
| Independent Unicode model | 1 passed; 873 cases and 57,204 pulls | 4.95 s | `target/stdlib-work/text-partitions-model.log` |
| Capability boundaries | All 8 rejection cases passed | 6.45 s | `target/stdlib-work/text-partitions-capabilities.log` |

The direct fixture covers split pairs, overlap direction, scalar byte offsets,
empty fields, zero/one/full-width limits, captured descriptors, cursor copies,
`Take`, exhaustion, and unchanged backing. Its byte-search reference uses
indexed comparisons over ranges through 37 bytes, crossing the packed scanner's
eight-byte threshold. Source and needle independently use both accepted
layouts, including nonzero source ranges and needle origins.

The independent model uses Unicode regular expressions. For reverse results
it reverses scalar strings, matches there, and maps the spans back through UTF-8
prefix offsets. It does not copy the library's byte scanner or reverse a
leftmost match list. The 873 cases include exhaustive short strings, overlap
witnesses, all UTF-8 scalar widths, combining marks, NUL, ZWJ, noncharacters,
periodic strings, missing patterns, source aliases, and seeded varied strings.
The accepted output contains 28,934 fields, 13,968 cursor-state copies, and
1,820 reverse matches. Every returned view's bytes, start, length, and stride
is checked, along with both backing buffers after traversal.

The direct executable uses the existing exact native/runtime syscall
classifier with `LANIUS_ALLOC=mmap`. Its observer rejects source allocations
and releases while accounting separately for loader and CRT bootstrap
mappings. It also rejects unknown executable-image syscall sites. The host
reference controls passed 17 checks; the allocation observer controls passed
10. The final integration-driver build took 9.90 s.

These receipts execute native CPU programs produced by the GPU compiler.
User-program execution as GPU compute kernels, other targets, arbitrary
positive byte strides, enforced lifetimes, and formal verification remain
outside this evidence. This increment changes no compiler IR, extractor,
formal proof, or ABI.
