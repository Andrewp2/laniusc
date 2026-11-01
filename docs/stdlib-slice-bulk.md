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
| `core::slice::memchr_from(values, start, len, needle)` | First index in `[start, len)` holding `needle`, or -1; a negative start or an empty range returns -1 |
| `core::slice::memcmp_range(left, left_start, right, right_start, count)` | `memcmp` over `count` bytes from each start; a negative start or nonpositive count returns 0 |
| `core::slice::ascii_run_end(values, start, end)` | First index in `[start, end)` holding a byte of 128 or above, or `end`; an empty or negative range returns `start` |
| `std::io_byte::write_byte_view(handle, values, len)` | Write `len` bytes to stdout (1) or stderr (2), retrying short writes; false on another handle, a negative length or a host error |
| `std::io_byte::write_code_view(handle, values, len)` | The same for an `[i32]` of byte codes; any code outside `0..=255` returns false before anything is written |
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

## Callers

The library's per-byte copy, search and compare loops now call these
functions:

- `alloc::string`: `equals`, `compare`, `starts_with` and `ends_with` use
  `memcmp`/`memcmp_range`; `try_substring` and `try_replace_range` append
  views with `try_extend`; removals and `trim_ascii` shift with `copy_within`.
- `alloc::io` and `core::io`: delimiter searches use `memchr_from`, and record
  bytes are appended or copied as one run. `SliceReader` and `SliceWriter`
  copy with `copy_nonoverlapping_range`, as do `core::buffered` `Reader::read`
  and `Writer::write`. `alloc::io::Buffer::write` already used `try_extend`.
- `core::utf8_view`: insert, remove and replace shift the tail with
  `copy_within`.
- `core::utf8` byte validation (used by `Utf8View`) and `core::text::from_utf8`
  (used by every `String` construction from bytes) skip ASCII runs of 16 bytes
  or more with `ascii_run_end`, which tests eight bytes per step against
  `0x80..80` on packed views.
- `std::io_utf8::write_codes`/`write_bytes` and the `std::io_line` writers
  validate as before, then write through `write_code_view`/`write_byte_view`
  instead of one host call per byte.

`std::stream` keeps its loops: they move between packed buffers and native
word arrays, a mixed layout the engine copies element by element anyway.

[`stdlib_bulk_callers/bench.lani`](../tests/fixtures/stdlib_bulk_callers/bench.lani)
runs each path over 1 MiB of ASCII text in lines of 1,000 bytes, 64 MiB per
phase (4 MiB for `std::io_utf8`). Best of two interleaved runs on
2026-11-01 on the development laptop at load average 15-19, in milliseconds;
"before" is the same benchmark compiled against the stdlib from before this
change:

| Phase | before | now | speedup |
| --- | ---: | ---: | ---: |
| `String::try_substring` (whole 1 MiB) | 3,555.0 | 62.7 | 57x |
| `String::equals` | 207.6 | 29.8 | 7x |
| `String::compare` | 512.1 | 18.1 | 28x |
| `String::ends_with` (512 KiB suffix) | 207.1 | 27.1 | 8x |
| `String::try_replace_range(0, 1, "")` | 216.5 | 28.1 | 8x |
| `String::try_replace_range(0, 1, "a")` | 3,524.2 | 72.5 | 49x |
| `alloc::io::read_line` | 1,411.8 | 864.4 | 1.6x |
| `core::io::read_until` (1 KiB window) | 860.4 | 109.5 | 8x |
| `core::buffered` `Reader::read` (4 KiB) | 446.3 | 54.9 | 8x |
| `core::buffered` `Writer::write` (100 B) | 431.9 | 166.3 | 2.6x |
| `Utf8View` insert and remove at the front of 64 KiB | 2,027.5 | 54.7 | 37x |
| `std::io_utf8::write_bytes` (4 MiB) | 2,019.0 | 1.3 | 1,500x |

`read_line` allocates a fresh owner per record. With the old allocator
(one `mmap` per allocation), allocating and freeing a 1,000-byte `Vec<u8>`
cost about 6.4 µs, against 3.2 µs per line for the reusable `read_line_into`.
The [pooling runtime allocator](runtime-allocator.md) brings the pair down to
0.19 µs, and the `read_line` row above to 187–193 ms.

## Verification

- [`model.lani`](../tests/fixtures/stdlib_slice_bulk/model.lani) runs 20,880
  checked operations. Random `copy_within`, `copy_nonoverlapping_range`,
  `fill_range`, `swap_with_slice`, `copy_from_slice`, `remove_at` and
  `insert` calls run through the library on one pair of views and through
  plain loops on an identical pair, and both pairs must agree after every
  call. The views cover `Vec<u8>`, `Vec<i32>`, `Vec<u64>` and a three-word
  record (lengths 1, 9, 40 and 97), native `[u8; 97]` and `[u64; 97]`
  arrays, and packed bytes against a native byte array. `memchr` and
  `memcmp` are checked at every position for lengths 0 to 80 on packed and
  native layouts. `memchr_from`, `memcmp_range` and `ascii_run_end` run 1,500
  random ranges each on packed and native 81-byte views. The new Vec methods
  have direct checks, including a self-aliased `try_extend_from_slice`. It
  exits 0.
- Eight engine mutations are each caught, with exit 28, 101 or 104: skipping
  the last word in either direction, skipping a tail byte, a wrong base
  address, a reversed move direction, a wrong fill tail start, an off-by-8
  `memchr` index, a 7-byte `memcmp` word window, and a short swap.
  Testing only the low byte of each word in `ascii_run_end` exits 124.
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
- 106 fixtures that use `core::utf8`, `core::utf8_view`, `alloc::io`,
  `core::buffered`, `std::io_utf8`, `std::io_line`, `std::io_byte`, or the
  string and text fixtures of `alloc::string` and `core::text`, give the same
  exit codes and output sizes with the old and new stdlib.
