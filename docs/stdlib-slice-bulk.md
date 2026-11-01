# Bulk slice and vector operations

`core::slice` copies, fills, swaps, searches and compares packed byte views
eight bytes at a time. `alloc::vec` routes its own bulk moves through the
same functions. Per-byte loops cost about 1.8 to 6.2 ns per byte with the
current x86_64 backend (see
[`slice_byte_copy_cost.lani`](../tests/fixtures/compiler_defects/slice_byte_copy_cost.lani)).
On these paths that drops to 0.2 to 0.4 ns per byte.

## API

| Function | Contract |
| --- | --- |
| `core::slice::copy_from_slice(destination, destination_len, source, source_len)` | Copy every source element; lengths must be equal and nonnegative, else false without writing. The views must not overlap in memory |
| `core::slice::swap_with_slice(left, left_len, right, right_len)` | Exchange every element of two equal-length views that do not overlap; else false without writing |
| `core::slice::fill_range(values, len, start, end, value)` | Write `value` to `[start, end)`; false without writing unless `0 <= start <= end <= len` |
| `core::slice::memchr(values, len, needle)` | First index below `len` holding the byte `needle`, or -1; a nonpositive length returns -1 |
| `core::slice::memcmp(left, right, count)` | Compare the first `count` bytes as unsigned: -1 or 1 at the first difference, 0 if none; a nonpositive count returns 0 |
| `Vec::try_extend_from_slice(values, count)` | Append the first `count` elements of a backed slice; atomic, self-aliases allowed, as for `try_extend`. A negative count is `Bounds` |
| `Vec::copy_from_slice(values, count)` | Overwrite every element; `count != len()` is `Bounds` and writes nothing |
| `Vec::swap_with_slice(values, count)` | Exchange every element with a separate slice; `count != len()` is `Bounds` |
| `Vec::fill(value)` | Overwrite every element; nothing is destroyed |
| `Vec::swap(left, right)` | Exchange two elements; an index outside `0..len()` is `Bounds` and writes nothing |

The existing `fill`, `copy_within`, `copy_nonoverlapping_prefix`,
`copy_nonoverlapping_range`, `insert` and `remove_at` keep their contracts and
use the same engine. So do the stable merge sort's run copies. In
`alloc::vec`, relocation, `try_extend` (and through it `try_append` and
`from_view`), `try_extract_range`, `try_split_off`, `try_insert`, `remove`,
`try_resize` and `try_clone` copy through it as well.

## Layouts

A view's runtime stride says how its elements are stored:

- Packed views (stride +1 for `u8`, +4 for `i32`) hold a run of elements in
  one ascending byte range from the view's data pointer. Raw views from
  `core::mem` and `Vec<u8>`/`Vec<i32>` storage are packed.
- Word views (stride -8 per native word) hold each element in descending
  eight-byte words. Native arrays such as `[u8; 4096]` use one word per byte,
  and `u64`, records and every other type use words in raw storage too.

When both views are packed with the same stride, the run spans at least 64
bytes, and this target's raw `[u64]` and `[u8]` views have strides -8 and +1,
the engine moves the run's bytes through raw `[u64]` views. Each step loads a
word before it stores one, and the order follows the move direction, so
`copy_within` stays correct for any overlap. A byte tail follows. Fill writes
the run's first word through the caller's view and repeats it. `memchr` tests
eight bytes per step with the zero-byte test
`(x - 0x01..01) & !x & 0x80..80` on `x = word ^ needle * 0x01..01`, whose
lowest marked byte is the first match. `memcmp` skips equal words, then
compares bytes inside the first unequal word.

Everything else copies elements: short runs, mixed layouts (a packed `[u8]`
against a native byte array) and word views. For word views the element copy
already moves whole words, and a raw word loop measured no faster. A
three-word record copied as words took 4.2 µs per 512 elements against
3.5 µs for element copies.

Before any raw access the engine indexes each run's first and last element
through the caller's view. A length that overstates the backing still exits
101, as native indexing does.

The data pointer comes from `core::mem::i32_slice_data_ptr`, which accepts a
view of any element type.

## Performance

[`bench.lani`](../tests/fixtures/stdlib_slice_bulk/bench.lani) moves 64 MiB
per phase in 4 KiB rounds, the workload of the byte-copy defect fixture.
[`bench.cpp`](../tests/fixtures/stdlib_slice_bulk/bench.cpp) runs the same
phases with the C library at g++ -O2. These are the best of four interleaved
runs on 2026-11-01 on the development laptop, in milliseconds, at load
average 11-14:

| Phase | element loop | now | C++ |
| --- | ---: | ---: | ---: |
| u8 copy | 117.8 | 23.0 | 2.4 |
| u8 fill | 412.8 | 10.9 | 0.8 |
| u8 swap | - | 41.6 | 76.6 |
| u8 memchr (match at 4000) | 83.4 | 23.9 | 0.4 |
| u8 memcmp (difference at 4090) | 138.3 | 14.2 | 0.8 |
| u8 append 4 KiB × 16,384 (`try_push` loop / `try_extend_from_slice`) | 3,272.9 | 142.6 | 79.0 |
| u64 copy, 512 per round (element path) | 10.8 | 16.3 | 2.3 |
| u64 fill (element path) | 8.3 | 10.5 | 1.4 |
| native `[u8; 4096]` copy (element path) | 93.8 | 153.8 | - |

The word-view rows take the element path, so their gaps are code placement,
not algorithm. The old library loop measured on the same native-array
workload swung from 30% faster to 60% slower than the benchmark's own loop
between runs. The word path has a fixed cost of about 100 ns, so packed runs
under 64 bytes stay on the element path. At 32 bytes the word path took
103 ns against 63 ns for the loop, at 64 bytes 120 ns against 151 ns, and at
4 KiB 1.5 µs against 9.8 µs.

The remaining gap to C is per-word code: every raw `[u64]` index copies its
descriptor, checks bounds and multiplies by the stride (see the defect
README).

## Verification

- [`model.lani`](../tests/fixtures/stdlib_slice_bulk/model.lani) runs 17,880
  checked operations. Random `copy_within`, `copy_nonoverlapping_range`,
  `fill_range`, `swap_with_slice`, `copy_from_slice`, `remove_at` and
  `insert` calls run through the library on one pair of views and through
  plain loops on an identical pair, and both pairs must agree after every
  call. The views cover `Vec<u8>`, `Vec<i32>`, `Vec<u64>` and a three-word
  record (lengths 1, 9, 40 and 97), native `[u8; 97]` and `[u64; 97]`
  arrays, and packed bytes against a native byte array. `memchr` and
  `memcmp` are checked at every position for lengths 0 to 80 on packed and
  native layouts, and the new Vec methods have direct checks, including a
  self-aliased `try_extend_from_slice`. It exits 0.
- Eight engine mutations are each caught, with exit 28, 101 or 104: skipping
  the last word in either direction, skipping a tail byte, a wrong base
  address, a reversed move direction, a wrong fill tail start, an off-by-8
  `memchr` index, a 7-byte `memcmp` word window, and a short swap.
- [`overstated.lani`](../tests/fixtures/stdlib_slice_bulk/overstated.lani)
  overstates a 64-byte packed view as 72 bytes for each bulk function; all
  six exit 101.
- 87 fixtures that call the changed functions (vec edit and transfer models,
  sort algorithms, slice segmentation, string, text replacement and
  collection fixtures) give the same results as the previous stdlib, except
  that four now pass that trapped before. They trapped on a nonnull
  `storage` from `alloc::vec::new`, caused by a 32-bit store of
  `let p: ptr = 0;`
  ([`ptr_literal_store_width.lani`](../tests/fixtures/compiler_defects/ptr_literal_store_width.lani)),
  which the compiler now fixes.
