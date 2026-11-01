# Inline ring buffer and inline string

Two inline fixed-capacity containers join `core::vec::Vec<T, N>` (the
ArrayVec-style vector described in [inline collections](stdlib-fixed-capacity.md)):
`core::ring::Ring<T, N>` and `core::inline_string::InlineString<N>`. Both store
an array of N elements inside the owner, so construction, copying and every
operation make no heap allocation, free nothing and destroy no element. By-value
copies own independent arrays (shallow copies of T). Lengths and indices are
`i32`; constructors panic for N above `2147483647`. `N = 0` is valid.

Like `core::vec`, operations are free functions over a borrowed owner
(`owner.borrow()`), generic in `T` and `const N`. Every rejected mutation checks
all its preconditions first and changes nothing.

The vector gains two operations in this increment:

| Operation | Behavior |
| --- | --- |
| `core::vec::try_swap_remove(index)` | O(1) removal: the last element moves into the hole, so order changes. Bounds when the index is not in `0..len`. |
| `core::vec::try_extend_from_view(view)` | Append all of a `View<T>` or nothing; Full is checked before any write. The view may be the vector's own `as_view()` prefix. |

## Ring buffer

`Ring<T, N>` holds a logical sequence that wraps around the end of its array.
Logical index 0 is the front.

| Operation | Behavior |
| --- | --- |
| `from_storage([T; N])`, `from_array([T; N])` | Empty ring over filler / full ring in array order |
| `len`, `capacity`, `spare`, `is_empty`, `is_full` | Counts and predicates; capacity 0 is both empty and full |
| `get(index)`, `front`, `back` | `Option<T>` copies |
| `try_set(index, item)` | Return the displaced value, or Bounds |
| `try_push_back(item)`, `try_push_front(item)` | Return the new length, or Full unchanged |
| `push_back_overwrite(item)` | When full, evict and return the **front** first; capacity 0 returns the item itself |
| `push_front_overwrite(item)` | When full, evict and return the **back** first |
| `pop_front`, `pop_back` | `Option<T>` |
| `discard_front(count)`, `discard_back(count)` | Drop `count` items in O(1) and return the new length; counts outside `0..=len` give Bounds |
| `clear` | Return the number discarded |
| `as_views` | `Pair<View<T>, View<T>>`: the run from the front to the array end, then the wrapped run from slot 0 (empty unless the sequence wraps) |
| `make_contiguous` | Rotate the array in place (three reversals, O(N) moves, no extra storage) so the sequence occupies slots `0..len`; return one view |
| `iter` | Borrowed `Iter<T>` in logical order: `Iterator`, `DoubleEndedIterator` (one shared non-crossing remainder) and `ExactSizeIterator` |
| `TrySink<T, Error>` | `try_accept` pushes at the back; a full ring rejects with Full |

All operations except `make_contiguous` are O(1). Whenever a ring becomes
empty, its next element is stored at slot 0, so `as_views` of a ring filled
from empty with back pushes is one run. Views and cursors borrow the owner's
array: end them before mutating or moving the owner.

## Inline string

`InlineString<N>` holds up to N bytes that are always valid UTF-8. Lengths are
bytes.

| Operation | Behavior |
| --- | --- |
| `from_storage([u8; N])` | Empty string; filler bytes are never read as text |
| `try_from_text(storage, text)` | Copy of a Text, or Full |
| `len`, `capacity`, `spare`, `is_empty`, `is_full` | Byte counts and predicates |
| `as_text` | Borrowed `core::text::Text` over the current bytes |
| `try_push_text(text)` | Append all of text or nothing; Full |
| `push_text_truncating(text)` | Append the longest prefix that fits and ends on a scalar boundary; return the bytes taken (possibly 0) |
| `try_push_scalar(u32)` | Append one scalar; InvalidScalar (surrogate or above U+10FFFF) is checked before Full |
| `pop` | Remove and return the last scalar value |
| `truncate(new_len)` | Keep the first new_len bytes; Bounds outside `0..=len`, NotCharBoundary inside a scalar |
| `clear` | Return the bytes discarded |
| `equals(text)`, `compare(text)` | Exact unsigned-byte comparison of the current text (-1, 0 or 1) |

Text inputs are already valid UTF-8, and every edit appends whole scalars or
truncates at a boundary, so the stored bytes stay valid without revalidation.

## Evidence

`tests/fixtures/stdlib_fixed_capacity_lru/model` drives rings of capacity 0,
1, 5 and 8, inline strings of capacity 0, 5 and 12, a `Vec<u64, 6>` and the
[LRU cache](stdlib-lru-cache.md) from one command stream, checked word for
word against a Python reference (a list with a tracked head slot, a bytearray
with Python's UTF-8 codec, and a list). See the [LRU guide](stdlib-lru-cache.md#evidence)
for the full receipt; the inline-container part covers 2,133 ring operations
(306 Full rejections, 87 overwrites, 313 snapshots including 77 wrapped
two-run views, 556 two-ended pulls), 1,718 string operations (356 Full, 40
invalid scalars, 20 non-boundary truncations, 166 truncating pushes cut at a
boundary) and 1,390 vector operations (98 Full extensions, 26 self-aliasing
extensions).
