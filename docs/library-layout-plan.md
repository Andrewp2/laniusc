# Checked storage layouts

This increment supplies one arithmetic contract for byte storage. It belongs
to `core::layout`, below allocation and host services. It does not infer the
compiler's native record layout, construct pointers or allocate memory.

## Values and invariants

```text
MAX_SIZE: usize = 9223372036854775807
Layout { size: usize, alignment: usize }
ArrayLayout { layout: Layout, stride: usize }
ExtendedLayout { layout: Layout, offset: usize }
Error = InvalidAlignment | SizeOverflow
```

The current pointer-width profile is 64 bits, matching `core::usize` and
`core::isize`. An alignment must be a nonzero power of two. A layout is valid
exactly when its size rounded up to its alignment is at most MAX_SIZE. Zero
size is valid, including alignment 2^63. This is arithmetic validity; the
current native allocator separately accepts only alignments 1, 2, 4 and 8,
and rejects zero-size requests.

Fields can be constructed or mutated directly in current Lanius. Every
operation therefore validates its input values before arithmetic. Alignment
errors precede size errors within each Layout; binary operations validate
the left Layout before the right. No unchecked public constructor is needed.

## Functions

All functions are free functions; no duplicate method facade is required.

| Function | Contract |
| --- | --- |
| `from_size_align(size, alignment) -> Result<Layout,Error>` | Check the complete invariant and retain the unpadded size. |
| `validate(layout) -> Result<Layout,Error>` | Recheck the same invariant on a supplied value. |
| `is_valid(layout) -> bool` | The boolean form of validation. |
| `padding_for(offset, alignment) -> Result<usize,Error>` | Minimum padding to a multiple of alignment; reject invalid alignment or a rounded offset above MAX_SIZE. Offset need not already be aligned. |
| `pad_to_align(layout) -> Result<Layout,Error>` | Add trailing padding, retaining alignment. |
| `align_to(layout, alignment) -> Result<Layout,Error>` | Raise alignment to the greater requirement without changing size; revalidate the result. Validate the input Layout first, then requested alignment. |
| `array(element, count) -> Result<ArrayLayout,Error>` | Stride is the padded element size. Total size is stride times count, including the last element's padding. Count zero retains alignment and stride. Zero stride permits every usize count. Validate the element even for count zero. |
| `extend(left, right) -> Result<ExtendedLayout,Error>` | Place right at the first multiple of its alignment at or after left.size. Result alignment is the maximum; result size is offset + right.size, with no automatic trailing padding. Validate the complete resulting Layout before publication. |

Padding, addition and multiplication must be checked before executing an
overflowing expression. Invalid inputs return an error without mutation,
allocation, host calls, pointer access or traps. A valid huge layout is not
evidence that its backing storage can be obtained.

`alloc::arena` uses the checked padding function for its existing relative
chunk offset calculation. Its live-state, 1/2/4/8 alignment admission, chunk
limits, zero-size policy and native typed-storage contract stay explicit.
This is a concrete consumer of the shared arithmetic; it does not change
the allocator, native layout or protected `std::vec` contracts.

## Verification

- Direct executable examples cover every function, forged/mutated values,
  precedence, zero sizes/counts, high alignment and full-width boundaries.
- A deterministic arbitrary-precision Python model checks the Lanius output
  over boundary-heavy and generated inputs; Python remains test-only.
- Selected existing arena runtime tests check relative alignment, content,
  failure preservation and typed storage after migration.
- A small real record-storage program uses layouts with arena allocation,
  byte views and endian codecs, checks actual written/read values and releases
  its arena explicitly.
- Root serializes compiler/native commands under the existing lock. Each
  command is below two minutes. No compiler, ABI, proof or runtime changes.

Reference: [Rust Layout's size/alignment and record-composition contracts](https://doc.rust-lang.org/alloc/alloc/struct.Layout.html).
The array contract above always includes trailing stride padding; it is
specified here independently of that reference's repeat variants. The module
also revalidates public fields and reports rounded-offset overflow explicitly.
