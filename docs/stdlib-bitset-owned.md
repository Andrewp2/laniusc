# Owned bitsets and counted views

`alloc::bitset::BitSet` owns a growable sequence of bits. `core::bitset::BitView`
borrows a counted `core::slice::View<u32>` plus a logical bit length. Bit zero
is the least significant bit of word zero. These implementations execute on the
native Linux x86_64 target and use Lanius library code throughout.

```lani
import alloc::bitset;
import core::bitset;
import core::option;
import core::result;

let bits: alloc::bitset::BitSet = core::result::unwrap(alloc::bitset::with_len(65, false));
core::result::unwrap(bits.set(32));
core::result::unwrap(bits.try_push(true));
let ones: core::bitset::Ones = bits.iter_ones();
assert(core::option::unwrap(ones.next()) == 32);
assert(core::option::unwrap(ones.next()) == 65);
assert(core::option::is_none(ones.next()));
bits.destroy();
```

## Ownership and backing

Keep one active owner. Copying a `BitSet` record aliases its allocation and does
not clone it. Methods borrow and update that owner. `try_clone` creates an
independent allocation, and `destroy` frees the owner's allocation and resets
its fields. Calling `destroy` again on that reset owner is harmless. Copies of
the old owner and its borrowed views remain invalid. The compiler does not
enforce these ownership rules or field encapsulation; clients must treat the
representation fields as opaque.

`as_view` borrows initialized words. Keep the owner alive. A successful operation
that moves or replaces storage invalidates every previous view and iterator.
In particular, nonempty algebra operations replace storage even when there is
spare capacity. A failure preserves previous views. Logical mutations through a
live view affect its owner's bits without changing its length or capacity.

Construct a caller backed view with
`core::bitset::BitView::from_words(words, bit_len)`. The constructor rejects a
negative bit length, malformed start/count metadata, or a logical word count
larger than the supplied counted view. It cannot discover the original slice's
physical length: the caller must supply live, initialized storage for every
claimed word. An overclaim can trap when native slice indexing reaches it.
Do not forge a `BitView` record or change its metadata after construction.

The API indexes typed words and respects the slice's actual stride. Raw `u32`
storage on the current native target uses descending eight byte cells; it is
not a packed C array of four byte words. Use `core::mem::size_of<u32>()` and
`typed_slice_from_storage<u32>` to size and address an allocation. Every view of
that storage must use the allocation's word capacity when computing its base;
use a prefix or counted subview for a smaller logical range. Native arrays keep
their own slice layout. Neither the owner nor a view accepts arbitrary packed
external `u32` bytes as native typed storage.

## Construction and capacity

| API | Contract |
| --- | --- |
| `new()` | Empty owner without allocation. |
| `with_len(length, fill)` | Fallibly allocate and initialize exactly the logical length. |
| `with_capacity(bits)` | Fallibly reserve capacity, leaving length zero. |
| `from_view(view)` / `try_clone()` | Independent copy of logical bits, with zero padding. |
| `len()`, `is_empty()`, `capacity()` | Logical bit length and available bit capacity. |
| `borrow()` / `as_view()` | Borrow the owner or its initialized bits. |
| `try_reserve(additional)` | Reserve `len + additional` bits, rounded to whole words. |
| `try_resize(length, fill)` | Keep the prefix, initialize growth to `fill`, retain capacity on shrink. |
| `try_push(bit)` / `pop()` | Append fallibly, or remove the final bit as `Option<bool>`. |
| `try_shrink_to_fit()` | Reduce capacity to the words needed for length; release empty storage. |
| `destroy()` | Release and reset the one active owner. |

Lengths are nonnegative `i32`, up to `MAX_BITS = 2147483647`. Capacity rounds up
to a whole 32 bit word and is capped at `MAX_BITS`. Reserve requests are exact
at word granularity; repeated pushes use geometric growth. Shrinking does not
allocate unless `try_shrink_to_fit` moves nonempty storage.

Allocation operations return `Result<_, alloc::bitset::Error>`. Errors identify
`Bounds`, `InvalidCapacity`, `CapacityOverflow`, `AllocationFailed`, and
`SizeMismatch`. Negative resize lengths are `Bounds`; negative reserve requests
are `InvalidCapacity`; a reserve request whose sum exceeds `MAX_BITS` is
`CapacityOverflow`. Every allocation or validation error preserves the original
allocation, capacity, length, bits, and borrowed views. Successful reserve and
shrink return bit capacity; successful resize, push, and algebra return bit
length. Constructors and clones return their new owner.

## Bit operations

Both owners and views provide these methods:

| API | Contract |
| --- | --- |
| `get(index)` | `Option<bool>`; out of range is absent. |
| `set(index)`, `clear(index)`, `assign(index, value)`, `toggle(index)` | Checked mutation returning the previous bit. |
| `set_range(start, end)`, `clear_range(start, end)`, `toggle_range(start, end)` | Checked half open range, returning the number of bits visited. |
| `fill(value)` | Set every logical bit; return logical length. |
| `count_ones()`, `any()`, `all()` | Logical bit queries; `all()` is true for an empty view. |
| `first_set()`, `last_set()` | `Option<i32>` for the matching logical index. |
| `next_set(start)`, `next_clear(start)` | Inclusive search returning `Result<Option<i32>, ViewError>`. |
| `iter_ones()` | Borrowed ascending cursor of set indices. |
| `copy_within(start, end, destination)` | Checked overlap safe copy within one view, returning copied count. |
| `shift_left(count)`, `shift_right(count)` | Shift toward higher or lower indices, discarding bits and inserting zeros; return length. |
| `equal(other)`, `hash()` | Equality and stable hash of logical length and bits. |
| `is_subset(other)`, `is_disjoint(other)` | Checked relations requiring equal logical lengths. |

`BitView` also exposes `len`, `is_empty`, `word(index)` and `assign_range`.
`word` returns a copied logical word with padding removed, or `None` when the
word index is out of range. Mutations and relations use
`core::bitset::ViewError`: `Bounds`, `InvalidLength`, `InsufficientWords`, and
`SizeMismatch`. Invalid indices, ranges, destinations, and negative shift counts
fail before writing. Search starts in `[0, len]`; `start == len` has no match,
and other invalid starts are `Bounds`. Shift counts at least `len` clear all
logical bits. Empty valid ranges and zero shifts succeed explicitly.

A `Ones` cursor reads the current backing words. It observes mutations ahead of
its current position. Once exhausted, it stays exhausted even if bits are later
set. Copying a cursor forks its position. Moving or destroying its storage
invalidates both copies.

## Set algebra, aliases, padding and hashing

Owners provide `try_union(other)`, `try_intersection(other)`,
`try_difference(other)`, and `try_xor(other)`, each accepting a `BitView`.
All four require equal logical lengths and return `SizeMismatch` without
mutation otherwise. A nonempty operation allocates independent destination
storage, computes all words while the old owner and input remain alive, then
replaces the owner. Exact and displaced input aliases are supported. A separate
input owner remains unchanged. Empty algebra succeeds without allocation.

A `BitSet` always zeros unused high bits in its final initialized word. Shrink
clears discarded bits, so later growth cannot reveal old contents. Borrowed
views preserve padding and extra backing words on every logical mutation;
queries, equality and hashing ignore padding. The four allocating algebra
operations also ignore input padding and produce zero destination padding.

Equality returns false for different lengths. Subset and disjoint queries use
`SizeMismatch` for different lengths. Hashing uses 32 bit FNV-1a over the logical
length followed by the masked logical words, each serialized in little endian
byte order. Equal values have equal hashes even when backing padding differs.
The hash is noncryptographic.

The original fourteen explicit free functions in `core::bitset` retain their
fallback and Boolean contracts. Their scalar operations delegate to the same
counted backend. Their caller supplied physical backing requirements and
existing union/intersection behavior remain in place. New owners and counted
views do not infer failures by comparing lengths or requiring a fallback value.

## Cost and executable evidence

Bit access is constant time. Fill, counts, searches, equality, hashing, shifts,
and algebra scan words. Set and clear ranges visit touched words. Toggle ranges
and `copy_within` currently visit individual bits. Owner clone and algebra copy
words; algebra temporarily requires a second allocation of the reserved word
capacity. Iteration scans between successive set bits and performs no allocation.

Run `cargo test --test stdlib_bitset_owned_execution` for:

- 4,500 deterministic mixed edits compared after every step with an independent
  Rust Boolean array model, including complete logical words, count and ends;
- exhaustive lengths 0 through 130, word boundaries, canonical padding, failed
  bounds edits, mismatched sizes, clone independence, exact and displaced aliases;
- counted native arrays and raw storage, malformed metadata, ignored and
  preserved padding, inclusive searches, fused iteration, and physical overclaims;
- every observed allocation denied once and persistently from that point onward,
  with owner/view and independent input preservation and mmap/munmap leak checks;
- a 1,048,577 bit sparse and dense workload with word shifts, iteration, clone,
  algebra and complete allocation cleanup.

`cargo test --test stdlib_bitset_execution` also checks the original free
function behavior and its caller backed sieve example. These native tests do
not claim compiler enforced borrowing, physical length discovery, or support
for other target layouts.
