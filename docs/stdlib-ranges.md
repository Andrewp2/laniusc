# Ranges

`core::range` stores bounds and answers comparison questions. Its five value
types, 20 free functions and 15 methods allocate nothing. `Range<i32>` uses
the same generic implementation as other element types; there is no separate
i32 range API.

```lani
import core::range;

let positions: core::range::Range<i32> = core::range::range(2, 6);
let first: i32 = positions.start();                 // 2
let past_last: i32 = core::range::end(positions);    // 6
let inside: bool = positions.contains(5);           // true
let excluded: bool = positions.contains(6);         // false
let touching: bool = positions.overlaps(core::range::range(6, 8)); // false
let closed: core::range::RangeInclusive<i32> = core::range::range_inclusive(2, 6);
let included: bool = closed.contains(6);            // true
```

## Types and complete API

The table lists every public function and method. Constructors preserve the
supplied bounds, including reversed bounds and floating NaNs. They do not
normalize, sort or reject them. Accessors return the stored value unchanged.

| Type and represented bounds | Constructor | Free accessors and predicates | Methods |
| --- | --- | --- | --- |
| `Range<T>`: [start, end) | `range(start, end)` | `start(value)`, `end(value)`, `is_empty(value)`, `contains(value, item)`, `overlaps(left, right)` | `start()`, `end()`, `is_empty()`, `contains(item)`, `overlaps(other)` |
| `RangeInclusive<T>`: [start, end] | `range_inclusive(start, end)` | `start_inclusive(value)`, `end_inclusive(value)`, `is_empty_inclusive(value)`, `contains_inclusive(value, item)`, `overlaps_inclusive(left, right)` | `start()`, `end()`, `is_empty()`, `contains(item)`, `overlaps(other)` |
| `RangeFrom<T>`: [start, ...) | `range_from(start)` | `start_from(value)`, `contains_from(value, item)` | `start()`, `contains(item)` |
| `RangeTo<T>`: (..., end) | `range_to(end)` | `end_to(value)`, `contains_to(value, item)` | `end()`, `contains(item)` |
| `RangeFull`: every value | `range_full()` | `contains_full(value, item)` | `contains(item)` |

Constructors and accessors need no comparison trait. Bounded membership and
emptiness predicates require `T: core::cmp::PartialOrd<T>`. The four overlap
APIs require `T: core::cmp::Ord<T>`, a lawful total order.
`RangeFull` has no element type parameter; each `contains` call can accept a
different type and needs no trait bound. The one-sided/full types have no
`is_empty` or `overlaps` API. There is no `RangeToInclusive` value type.

Functions take range values by value; methods take `self` by value. Neither
changes the stored range. Copies, including returned endpoint values, are
shallow: reference-bearing endpoints keep their existing aliases and lifetime
requirements. No endpoint is cloned or destroyed by these operations. Keep
one active owner if an endpoint contains manually owned storage.

## Inclusion, emptiness and overlap

In the overlap rows below, `<` and `<=` mean `T::lt` and `T::le` from `Ord`.
In every other row they mean `T::partial_lt` and `T::partial_le` from
`PartialOrd`. These are the exact predicates used by the library:

| Operation | Predicate |
| --- | --- |
| `Range::is_empty` | `!(start < end)` |
| `Range::contains(x)` | `start <= x && x < end` |
| `Range::overlaps(other)` | `start < end && other.start < other.end && start < other.end && other.start < end` |
| `RangeInclusive::is_empty` | `!(start <= end)` |
| `RangeInclusive::contains(x)` | `start <= x && x <= end` |
| `RangeInclusive::overlaps(other)` | `start <= end && other.start <= other.end && start <= other.end && other.start <= end` |
| `RangeFrom::contains(x)` | `start <= x` |
| `RangeTo::contains(x)` | `x < end` |
| `RangeFull::contains(x)` | `true`, with no comparison |

For an ordinary total order, equal or reversed half-open bounds are empty.
Equal inclusive bounds contain that one value; only reversed inclusive bounds
are empty. Touching half-open intervals do not overlap, whereas inclusive
intervals sharing an endpoint do. Empty intervals never overlap. The unbounded
notation means the rest of the element domain: `range_from(i32::MAX)` contains
`i32::MAX`, while `range_to(i32::MIN)` contains no i32 value.

`overlaps` returns a Boolean, not an intersection range. For total orders, an
intersection can use the greater start and lesser end, then apply the matching
emptiness predicate. Mixed inclusive/exclusive or unbounded intersections need
caller-defined endpoint handling; the library supplies no intersection,
range-containment, union, length or cardinality operation.

### Partial orders and floats

Caller-defined comparisons must obey the [comparison contracts](stdlib-comparison.md).
`PartialOrd` predicates agree with `partial_cmp`, reverse consistently and are
transitive. `Ord` supplies a total order consistent with `Eq`; it does not need
a `partial_cmp` implementation to call overlap. When a type supplies both total
and partial comparisons, they must agree. Implement `PartialOrd` explicitly
where needed; supplying `Ord` alone does not supply that trait through an
automatic blanket implementation.

Membership and emptiness accept lawful partial orders. Overlap requires a total
order so that a true result establishes a shared member. An older API accepted
`PartialOrd` for overlap, which allowed a false positive. Consider
four values `a`, `c`, `b`, `d`, with each of `a` and `c` below each of `b` and
`d`, but with `a` incomparable to `c` and `b` incomparable to `d`. Then [a, b)
contains only `a` and [c, d) contains only `c`, yet all four old overlap
comparisons are true. This partial-only type is now rejected by all four
overlap APIs; its membership and emptiness operations still work. The retained
[reproduction](../tests/fixtures/stdlib_compiler_state/range_partial_overlap/README.md)
records the old semantic defect and the focused acceptance tests below enforce
the repaired bound. No alias preserves the old predicate.

Native `f32`/`f64` use IEEE partial comparisons:

- A NaN bound makes a two-sided range empty. A NaN item never belongs to a
  two-sided or one-sided range; a NaN one-sided bound admits no item.
- Signed zeros compare equal: [-0, +0) is empty, while [-0, +0] contains both.
- Infinite endpoints are allowed. [-infinity, +infinity) excludes positive
  infinity; [+infinity, +infinity] contains positive infinity.
- `RangeFull` contains NaN, both signed zeros and every other supplied value.

Raw float ranges cannot call `overlaps`: native floats implement no `Ord`.
Choose an explicit total-order policy first. `core::float_order::TotalF32` or
`TotalF64` endpoints use encoding order. Those wrappers distinguish signed zeros
and retain NaN signs and payloads; NaNs then have ordered positions. Negative
NaNs precede negative infinity, negative zero precedes positive zero, and
positive NaNs follow positive infinity. Inclusive ranges can overlap at the
same NaN encoding, while distinct zero encodings need not share a member.
This policy also changes membership to encoding-order membership, rather than
filtering NaNs as raw float ranges do.

```lani
import core::float_order;

let negative: core::float_order::TotalF64 = core::float_order::from_f64(-0.0);
let positive: core::float_order::TotalF64 = core::float_order::from_f64(0.0);
let left = core::range::range_inclusive(negative, negative);
let right = core::range::range_inclusive(positive, positive);
let shared: bool = left.overlaps(right); // false: distinct zero encodings
```

## Integer stepping and overflow

The range module only stores and compares values. It never subtracts bounds,
adds a step, or converts an inclusive end to `end + 1`, so its own helpers do
not overflow at integer minima or maxima. This does not validate arithmetic
used to compute arguments before the call. A user-defined comparator also
retains responsibility for its own arithmetic and failures.

A cardinality can exceed the endpoint type: [i32::MIN, i32::MAX) contains
4294967295 integers, and [i32::MIN, i32::MAX] contains 4294967296. Widen each
endpoint before subtraction, or use checked integer arithmetic. Do not infer
an i32 count from an i32 bound pair.

Integer `for` loops use built-in compiler lowering, independent of the
membership methods. For example:

```lani
let count: i32 = 0;
for value in 2147483646..=2147483647 {
    count += 1; // visits both values; finishes without incrementing MAX
}
```

The supported integer lowering advances by one. Half-open loops exclude the
end, inclusive loops visit it once, and equal half-open or reversed bounds
execute no body. Inclusive loops check terminal exhaustion before incrementing,
including after `continue`. Direct `start..` loops stop after the type's
maximum instead of wrapping. A missing start in `..end`, `..=end` or `..`
starts at zero; the fully omitted form uses i32. Consequently `for value in ..`
does not enumerate negative i32 members even though `RangeFull::contains`
accepts them.

Bounds are captured once before iteration. Changing the original bound or a
named range's fields inside the body does not change that iteration's captured
limits. Each later loop starts from the range's then-current bounds; the range
value itself has no advancing position.

Named `Range<T>` and `RangeInclusive<T>` values support integer loop lowering;
scalar-width fixtures cover narrow integers and native 64-bit bounds. This
does not provide generic stepping for every `PartialOrd` type. Float, char,
wide-integer-record and arbitrary record membership support does not imply
`for` iteration support for those types. Named `RangeFrom`, `RangeTo` and
`RangeFull` values have no corresponding loop-lowering recipe; the direct
syntax forms above are separate. Range values themselves have no advancing
position. For i32, the existing [RangeI32 cursor](stdlib-iterators.md) captures
bounds through range_i32/range_i32_inclusive and implements shared forward,
reverse and exact-size iteration; borrowed rev and step_by adapters compose
with it. Other scalar widths do not yet have corresponding range cursor
factories. Generic range stepping over user-defined types remains future work.
Use an explicit checked loop for unsupported custom-step/descending cases, with a caller-chosen
overflow rule and termination bound.

## Logical bounds and physical storage

A numeric range is not a slice descriptor and proves no storage is backed.
For example, `range(0, 100).contains(4)` says nothing about whether a particular
array has element 4. `range_inclusive(0, length)` also admits `length`, which is
an invalid element index for a length-element buffer. Validate nonnegative
indices and the actual backing separately.

[Borrowed slice views](stdlib-slice-views.md) combine backing with a logical
count. Their constructors and subviews check integer bounds, but initial
physical counts and storage lifetimes remain caller preconditions. Native
indexing can trap on a physical overclaim even if range membership succeeds.
View cursors belong to `core::slice`, have their own advancing state and alias
rules, and do not turn these range values into cursors.

## Compiler limits and existing evidence

All library functions return bounds or Booleans directly; they have no
`Result`, fallback or allocation-failure path. Invalid ordering inputs follow
the predicates above. Compilation and custom comparison implementations can
still fail independently of that source-level contract.

The retained reproducer
`tests/fixtures/generics_backlog/b17_imported_impl_method_record_result_in_generic_body.lani`
records an x86 failure when an imported generic accessor such as
`Range<T>::start()` returns a record `T` inside another generic function.
The free `core::range::start(value)` works in that context; concrete record
method calls also have execution coverage. The comprehensive fixture therefore
uses free accessors in its generic checker and tests accessor methods at
concrete call sites. This documentation audit did not revalidate that older
failure. [Shared iterator dispatch and RangeI32](stdlib-iterators.md) have
executable support; remaining [composition dependencies](library-dependencies.md)
retain their documented narrow scopes.

Focused x86_64 Linux acceptance passed 88114 bound quadruples through all four
overlap APIs, the migrated comprehensive caller, and native partial-order
membership. All twelve isolated overlap calls on a partial-only record or raw
f32/f64 rejected with the bound diagnostic `LNC0008`. These are separate
positive execution and negative compilation checks. Tests map to contracts as
follows:

| Test and fixture | Evidence covered |
| --- | --- |
| `tests/stdlib_range_overlap_execution.rs::total_order_overlap_matches_enumerated_common_members_and_migrated_caller`; `range_overlap/model.lani` | All four overlap APIs against independent common-member enumeration for signed/unsigned extrema, explicit TotalF32/TotalF64 zero/NaN encoding order and an Ord-only record; also executes the migrated comprehensive `core_range.lani` caller |
| `tests/stdlib_range_overlap_execution.rs::partial_order_membership_executes_and_all_overlap_forms_reject`; `range_overlap/partial-membership.lani` | Native membership/emptiness on the four-element partial order; separate compile rejection of each free/method half-open/inclusive overlap call |
| `tests/stdlib_range_overlap_execution.rs::native_f32_overlap_requires_an_explicit_total_order` and `native_f64_overlap_requires_an_explicit_total_order` | Compile rejection of every overlap call form for both raw float widths; no native program is published for these rejected inputs |
| `tests/stdlib_comparison_execution.rs::migrated_generic_range_slice_option_and_float_program_execute`; `tests/fixtures/stdlib_foundation/core_range.lani` | All 20 functions and 15 methods; every integer width, char, TotalF32, both wide integer records and a user record with explicit comparisons; raw f32 NaN membership/emptiness, infinities and signed zero; generic free and concrete record method accessors |
| `tests/stdlib_foundation_execution.rs::portable_stdlib_helpers_execute_on_x86` | Registers `core_range`, `core_range_methods`, `core_unbounded_ranges`, `core_u32_ranges`, `core_range_{u8,i8,u16,i16}_aggregate` and `range_slice` fixtures; i32 inclusivity/overlap and extrema, unsigned high bits, narrow aggregate returns and one-sided bounds |
| `tests/stdlib_foundation_execution.rs::executable_core_function_surface_has_runtime_cases` | Source-call inventory requires calls to all 20 range free functions and 15 methods; this scan supplements the executable assertions |
| `tests/stdlib_range_full_method_execution.rs::imported_range_full_methods_cover_signed_and_unsigned_domains` | Imported `RangeFull::contains` on signed i32 extrema and high unsigned values |
| `tests/stdlib_range_f32_methods_execution.rs::floating_window_program_uses_imported_range_method`; `sample_programs/floating_window_total.lani` | Real float total validation through imported `RangeInclusive<f32>::contains` |
| `tests/compiler_generic_types_execution.rs::native_range_width_{direct_wide,narrow,bound_snapshot,postfix_endpoints,open_ended,named,repeated_empty_inclusive}` and adjacent `native_range_width/` fixtures | Integer endpoint widths, inclusive terminal maxima, reversed/empty loops, captured endpoints, once-only endpoint evaluation, open-ended i32 exhaustion and named integer ranges |
| `tests/stdlib_range.rs::core_range_overlap_helpers_type_check_through_stdlib_root` | Stdlib import and overlap type admission only; this test does not execute the program |

The named-range width tests use a deliberately small isolated `core::range`
declaration root; the module and sample tests above exercise the production
source. Historical range-loop control-flow limits and the exact accepted
checkpoint are retained in
`tests/fixtures/stdlib_compiler_state/range-executable-owners/README.md`.
That checkpoint leaves full-range break dominance and combined postfix endpoint
contexts unresolved; it is not a claim that every nested loop shape executes.

The raw-float membership/emptiness fixture covers f32 special values, not a
separate raw-f64 range grid. The new overlap model covers both TotalF32 and
TotalF64 encodings. Both widths' comparison primitives also have independent
execution models in `tests/stdlib_comparison_execution.rs`. None of these tests
establishes arbitrary partial-order intersection semantics or a shared range
iterator protocol. The focused overlap repair tests distinguish positive native
execution/model evidence from negative compilation evidence; the other rows
map existing tests rather than claiming a fresh broad-suite run.
