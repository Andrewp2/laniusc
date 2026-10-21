# `core::slice`

`core::slice` is 40 allocation-free functions over a view `[T]` of any
element type. A fixed array passes as a view directly; raw views come from
`core::mem`. Callers supply a logical element length because Lanius source
cannot yet read slice metadata. A view borrows its storage and never
allocates or frees it.

```lanius
import core::cmp;
import core::slice;

struct Version { major: i32, minor: i32 }

// With Eq and Ord impls for Version, every search and sort works on it.
fn newest(versions: [Version], len: i32, fallback: Version) -> Version {
    return core::slice::max_or(versions, len, fallback);
}
```

## Bounds

The functions need nothing from T, `core::cmp::Eq<T>` (searching),
`core::cmp::Ord<T>` (ordering) or `core::ops::SaturatingAdd<T>` (`sum`).
`core::cmp` implements `Eq` and `Ord` for every integer width, `bool`, `char`
and `f32`. `core::ops` implements `SaturatingAdd` for every integer width and
`f32`. The wide integers implement all three in `core::wide_i64` and
`core::wide_u64`. A user type implements the traits it needs for itself.

## Operations

| Needs | Functions |
| --- | --- |
| nothing | `first`, `first_or`, `last_or`, `get_or`, `set`, `swap`, `fill`, `reverse_in_place`, `rotate_left`, `rotate_right`, `copy_within`, `copy_nonoverlapping_prefix`, `copy_nonoverlapping_range`, `insert`, `push`, `remove_at` |
| `Eq` | `contains`, `count`, `index_of_or`, `last_index_of_or`, `starts_with`, `ends_with`, `equals`, `index_of_subslice`, `last_index_of_subslice`, `dedup_adjacent`, `retain_not_equal` |
| `Ord` | `compare_lexicographic`, `min_or`, `max_or`, `is_sorted`, `sort`, `lower_bound`, `upper_bound`, `binary_search_first_or`, `binary_search_last_or`, `partition_lt` |
| `SaturatingAdd` | `sum(values, len, initial)` |

## Lengths and failures

- `first` traps on an empty view. The `_or` functions return their fallback
  for an empty view, an index outside `len`, or no match.
- `set`, `swap`, the rotations, `insert`, `push`, `remove_at` and the copies
  return false without writing when a logical bound is invalid. `insert` and
  `push` need `len < capacity`, and the caller increments its length after
  success. `remove_at`, `dedup_adjacent` and `retain_not_equal` leave the tail
  past the new length unspecified.
- `copy_within` supports overlap in either direction. The
  `copy_nonoverlapping_` functions need separate backing.
- A nonpositive length is an empty view for search, fill, compaction, sort,
  the bounds and `sum`. Prefix, suffix, equality, lexicographic comparison
  and subsequence search treat a negative length as empty.
- `compare_lexicographic` returns -1, 0 or 1; the first unequal element
  decides before the lengths. Subsequence search returns -1 when absent, and
  an empty needle matches at the first or final boundary.
- `sort` is an in-place heapsort and is not stable. The binary searches and
  bounds need nondecreasing input.
- If the supplied length overstates the physical view and indexing reaches
  past it, native execution exits 101.

## Floating point

Searching uses IEEE equality: NaN matches nothing, not even itself, and
`0.0` matches `-0.0`. Ordering only calls `lt` and `le`, so NaN is never
below or above anything: `min_or` and `max_or` skip a NaN unless it comes
first, and sorting or searching a view that holds NaN gives an unspecified
order. `sum` of `f32` adds with IEEE rules, so overflow gives an infinity.

## Targets

x86_64 Linux runs every function for every element type above. Wasm does not
compile generic stdlib code yet.

## Verification

- `tests/fixtures/stdlib_foundation/core_slice.lani` runs every function
  through one generic checker for i8, i16, i32, i64, isize, u8, u16, u32,
  u64, usize, char, f32, both wide integers and a user record, then bool
  views, f32 NaN and signed zero, and `sum` past each type's limit.
  `tests/stdlib_foundation_execution.rs` runs it and checks that it calls
  every public function.
- `core_slice_record_bounds.lani` checks that an overclaimed multiword
  record view exits 101; `slice_bounds.lani` does the same for i32.
- The `slice_*.lani` fixtures cover i32 raw views in depth: subsequences,
  compaction, insertion, partitioning and exhaustive small sorts.
- Sample programs `character_inventory`, `floating_window_total`,
  `boolean_window_checksum`, `halfword_window_total` and the two wide median
  programs use the generic module on char, f32, bool, u16 and wide views.
