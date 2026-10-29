# Literal text matching and replacement

`core::text::Text.match_indices` supplies borrowed literal matches through the
shared iterator protocol. `alloc::string::replace` and `replacen` build an
independent String from those matches. The [frozen plan](library-text-replacement-plan.md)
defines this increment. All five library groups and four application groups/94
native cases pass on Linux x86_64 CPU output from the GPU compiler.

## API

| Operation | Result |
| --- | --- |
| `Text.match_indices(needle: Text)` | `MatchIndices` |
| `MatchIndices.borrow()` | `&MatchIndices` |
| `Iterator<Pair<i32, Text>> for MatchIndices` | `next()` returns an optional byte index and matching subview |
| `alloc::string::replace(text, needle, replacement: Text, max_output: i32)` | `Result<String, alloc::string::Error>` |
| `alloc::string::replacen(text, needle, replacement: Text, max_matches: u64, max_output: i32)` | The same result, replacing at most `max_matches` matches |

`Pair` is `core::pair::Pair`: `first` is the start byte index relative to the
selected source Text, and `second` is the matching source subview. Offsets and
stride stay attached to the original backing. The factory only captures cursor
state; each pull searches for the next match.

## Match sequence

Matches are literal, leftmost and nonoverlapping. After a nonempty match the
cursor advances by the needle's byte length. For example, `aba` in `ababa`
yields only `(0, "aba")`. The returned view borrows source bytes, even when the
needle has different backing or stride.

An empty needle matches every Unicode scalar boundary, including the initial
and final boundary. For `éx`, the byte indices are `0, 2, 3`; an empty source
has one match at zero. A terminal flag avoids incrementing the last index past
`i32::MAX`. This differs from `Text.split("")`, whose partition includes both
an initial and final empty field even for empty text.

The cursor remains exhausted after `None`. Copies have independent positions
over shared backing. It supports the forward `Iterator` protocol; reverse and
exact-size capabilities are not supplied. NUL and line endings are ordinary
content. No normalization, case folding, grapheme matching, regular-expression
syntax or replacement escapes are applied.

The Rust string reference provides the comparison for
[nonoverlapping match indices](https://doc.rust-lang.org/std/primitive.str.html#method.match_indices)
and [first-N replacement](https://doc.rust-lang.org/std/primitive.str.html#method.replacen).
Lanius uses explicit allocation errors and a caller-selected output-byte cap.

## Replacement and error order

Replacement selects matches from the original source. Inserted bytes are never
searched again. `replace` selects all matches; `replacen` stops after its u64
count, which can represent all `i32::MAX + 1` empty-pattern boundaries.
With zero matches requested, or no matches found, the result is still an
independent copy. An empty replacement deletes the selected spans.

Both constructors first measure the complete result through the public match
cursor, then use a fresh cursor to fill one exact allocation. Let `k` be the
number of selected matches. The final byte length is
`source_bytes - k * needle_bytes + k * replacement_bytes`, computed with u64
arithmetic. A large input can therefore shrink into a small admitted output.

| Condition, in precedence order | Result |
| --- | --- |
| `max_output < 0` | `Bounds`, before searching |
| Complete result exceeds `i32::MAX` | `CapacityOverflow` |
| Representable result exceeds `max_output` | `OutputLimit` |
| Exact nonempty reservation fails | `AllocationFailed` |

All length admission precedes allocation. Empty output needs no allocation.
Failure returns no partial owner and preserves every input. A nonempty success
has exactly one result allocation and one cleanup authority. The caller must
destroy that result once; it remains valid after input owners are destroyed.
The new `OutputLimit` variant belongs to `alloc::string::Error`; existing range
edits, join and repeat retain their own contracts.

## Borrowing and work

Source, needle and replacement may overlap one another. Their backing must
remain alive and immutable through cursor use or both replacement passes.
Returned match views share that backing and never own its cleanup. Copying a
cursor does not extend the backing lifetime. Physical storage and valid UTF-8
are caller obligations inherited from [Text](stdlib-text.md); forged public
descriptors receive no new checked-admission guarantee.

Matching reuses Text's existing literal search. Worst-case search work is
O(source bytes × needle bytes), with scalar-boundary traversal for an empty
needle. Replacement makes two matching passes plus output copying. Cursor and
auxiliary state are O(1); matching allocates nothing. This is no linear-search
or throughput guarantee.

The [literal-rewrite program](stdlib-literal-rewrite.md) composes checked UTF-8,
bounded input, replacement and stdout publication. Existing
[range edits](stdlib-string.md) and [join/repeat](stdlib-text-composition.md)
remain separate operations.

## Execution evidence and dependencies

All five library groups pass on Linux x86_64 CPU output from the GPU compiler,
using Text source `b8495da2…` and String source `dc9ccb76…` throughout. Receipts
are under `target/stdlib-work/`:

| Focused invocation | Accepted groups | Test time / separate Rust build | Log |
| --- | ---: | --- | --- |
| Tiny public admission | 1 | 5.35 s / 1.12 s | `text-replacement-admission.log` |
| Matcher, owned limits and owner recovery | 3 | 11.22 s / 1.20 s | `text-replacement-direct-resources.log` |
| Independent Unicode model | 1 | 6.86 s / 1.08 s | `text-replacement-model.log` |

The [direct/resource fixtures](../tests/fixtures/stdlib_text_replacement/README.md)
check actual packed and descending strides, generic composition, copied/fused
cursors, exact output reservations and complete source preservation. A real
32,768-byte source and 65,536-byte replacement produce a conceptual 2^31-byte
result, establishing `CapacityOverflow` before `OutputLimit` without forged
backing. The borrowed matcher has no host effects inside its pure phase.

Live-owner cases use 4096- and 262,144-byte selected sources and compare all
307,712 published result bytes after input owners retire. The baseline and one
reached output-allocation denial/recovery process each match six successful
allocations with exact releases. Failure preserves old views and owners; retry
uses those same inputs. These finite observations are not throughput evidence.

The [independent model](../tests/fixtures/stdlib_text_replacement_model/README.md)
accepts 440 cases across eight layouts: 13,883 pulls, 5221 items, 4974 cursor
copies and 4033 replacement operations. It observes 3182 successes, 440 Bounds
errors, 411 OutputLimit errors and all 75,478 result bytes. Seed is
`0x7e871a0261116`. Its 22 host-only corruption controls are separate from native
execution and from the reached allocation failure above.

Two selected existing regressions pass separately:
`owned_utf8_edits_aliases_and_invalid_inputs_execute` takes 11.59 seconds
(build 1.08 seconds), and
`text_validation_search_splits_and_scalars_match_reference_models` takes
6.20 seconds (build 1.14 seconds). Their logs are
`text-replacement-existing-string.log` and `text-replacement-existing-text.log`.
Earlier Text/String receipts retain their original API/source scope.

The [real program](stdlib-literal-rewrite.md) passes four groups/94 cases,
including 12 reached allocation failures. Its standalone build and two exact
examples pass separately. No compiler repair was needed. The design uses
existing Text, Iterator, Pair and Vec allocation contracts; automatic
lifetimes/destruction, other host targets, user-program GPU execution and formal
verification remain separate. The broader library goal stays open.
