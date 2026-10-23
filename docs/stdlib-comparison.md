# Comparison contracts

`core::cmp` separates partial comparisons from lawful equality and total
ordering. Native floats implement partial comparisons. Float collection keys
use `core::float_order::TotalF32` or `TotalF64`.

| Trait | Required methods | Contract |
| --- | --- | --- |
| `PartialEq<T>` | `partial_eq`, `partial_ne` | Symmetric, transitive equality; `partial_ne` is its negation. A value may differ from itself. |
| `Eq<T>` | `eq`, `ne` | Symmetric, transitive, reflexive equality; `ne` is its negation. |
| `PartialOrd<T>` | `partial_lt`, `partial_le`, `partial_gt`, `partial_ge`, `partial_cmp` | Predicates agree with the result and `PartialEq`; ordered relations are transitive and reverse when operands are exchanged. |
| `Ord<T>` | `lt`, `le`, `gt`, `ge` | Every pair is less, equal or greater, with exactly one case; order is transitive and agrees with `Eq`. |

`PartialOrdering` belongs to `core::cmp` and has `Less`, `Equal`, `Greater` and
`Unordered` variants. A partial comparison returns `Equal` exactly when
`partial_eq` is true. `partial_le` means less or equal; `partial_ge` means
greater or equal. An unordered pair makes every ordering predicate false.
Total and partial implementations on the same type must agree. These are
obligations of implementers; the compiler does not prove the laws.

The distinction follows the contracts described by Rust's
[`PartialEq`](https://doc.rust-lang.org/core/cmp/trait.PartialEq.html),
[`PartialOrd`](https://doc.rust-lang.org/core/cmp/trait.PartialOrd.html) and
[`Ord`](https://doc.rust-lang.org/core/cmp/trait.Ord.html). Lanius uses distinct
method names and explicit by-value parameters.

## Native floats

`f32` and `f64` implement only `PartialEq` and `PartialOrd`. They follow IEEE
operators: signed zeros compare equal; NaN equals nothing, including itself;
and any ordering predicate with NaN is false. `partial_cmp` returns `Unordered`
when either operand is NaN. Infinity and ordinary values compare normally.

Ranges require `PartialOrd`. A NaN bound makes a bounded range empty, and
NaN never belongs to a bounded range. The full range contains every value.
Option/result membership, slice equality searches and compaction, and vector
and deque equality lookup require `PartialEq`. They can therefore search native
floats, with NaN absent and either signed zero matching the other.

Sorting, ordered binary searches, extrema and lexicographic ordering require
`Ord`. Tree maps require `Ord`; hash maps require `Eq` and `Hash`; insertion
ordered maps and sets require `Eq`. Native floats cannot satisfy these key or
sort bounds. This prevents an unordered NaN from replacing an arbitrary tree
map key.

## Total float keys

`from_f32(value)` and `from_f64(value)` create copied, allocation-free wrappers.
Their `value()` methods recover the native float and `to_bits()` returns its
encoding. Every bit survives, including NaN sign, signaling bit and payload.

Wrapper equality compares all encoding bits. Thus negative zero differs from
positive zero, each NaN equals its own encoding, and distinct NaN encodings are
distinct keys. Hashing consumes those same bits through the existing integer
hash implementation. Equal keys always have equal hashes; hash collisions
between different keys remain permitted.

Wrapper order delegates to `core::f32::total_cmp` or `core::f64::total_cmp`.
Negative NaNs precede negative infinity; finite values retain numeric order;
negative zero precedes positive zero; positive NaNs follow positive infinity.
Signaling bits and payloads determine the order within NaNs. See the underlying
[`total_cmp` contract](https://doc.rust-lang.org/std/primitive.f64.html#method.total_cmp).

```lanius
import core::float_order;
import core::slice;
let keys: [core::float_order::TotalF32; 2] = [
    core::float_order::from_f32(0.0),
    core::float_order::from_f32(-0.0),
];
core::slice::sort(keys, 2); // negative zero, then positive zero
```

## Compiler limits and evidence

Generic blanket forwarding from `Eq` to `PartialEq`, or `Ord` to `PartialOrd`,
is not available: generic implementation member routing reports `LNC0027`.
The reduced fixture is
`tests/fixtures/stdlib_compiler_state/comparison/blanket-partial.lani`, compiled
with the adjacent `blanket-root` as its stdlib root.
Existing lawful stdlib types provide explicit forwarding implementations.
A custom type must implement each comparison trait its callers require.

A generic `T::partial_cmp` result should first be bound to a local annotated
`core::cmp::PartialOrdering`, then matched. Matching the call directly reports
`LNC0006` in `generic-partial-cmp-match.lani`, even with qualified patterns;
`generic-partial-cmp-match-control.lani` binds a typed local and executes
correctly.

Returning a float key through `Vec::at` inside another generic function compiles
but crashes on x86_64. The reduction is `generic-record-vec-at.lani` in the same
compiler-state folder; `generic-record-vec-slice-control.lani` changes only the
extraction to `as_slice()` followed by typed indexing and runs successfully.
Concrete `TotalF32` and `TotalF64` vector `at` and `get` callers execute
correctly. The generic collection fixture uses the supported extraction while still
executing the actual vector sort, binary search and partial membership APIs.
A plain record with a single `u32` field also crashes against the archived
`5bbdc70f` stdlib baseline, so this is an existing compiler dependency. The
library does not substitute a
placeholder result.

`tests/stdlib_comparison_execution.rs` compares 17,568 native float pairs with
independent Rust IEEE and total-order references, including every encoding
class, NaN signs/payloads, signed zeros and seeded arbitrary bit patterns. It
checks preserved bits, stable hashes and equality/hash agreement. Other native
fixtures exercise partial membership and ranges, total keys in collections,
and compile rejection of native float keys and sorts. The migrated generic
range, slice and comparison fixtures cover every integer width, wide integers
and user records. Execution evidence is for x86_64 Linux; GPU compilation is
not user-kernel execution.
