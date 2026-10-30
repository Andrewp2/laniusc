# Owned UTF-8 strings

`alloc::string::String` stores valid UTF-8 in a generic vector of packed `u8`
bytes. NUL and U+10FFFF are valid. It does not normalize text. Scalar operations
do not operate on grapheme clusters.

## Construction and ownership

`alloc::string::new()` creates an empty string without allocation.
`alloc::string::from_utf8(bytes, count)` validates and copies a byte slice,
returning `Result<String, Error>`. The slice must physically back `count` bytes;
negative counts return `Bounds`, while an overclaimed physical view traps.
`alloc::string::from_text(view)` copies a borrowed Text into independent storage.
`join(View<Text>, separator)` and `repeat(Text, count)` construct checked,
independent results; see [text composition](stdlib-text-composition.md).
`from_i64(number)` and `from_u64(number)` create canonical decimal text for the
full signed/unsigned native domains. Smaller integer types can widen explicitly.
Construction from native `str` awaits the length projection listed in
[library-dependencies.md](library-dependencies.md).

Methods borrow and mutate the owning String. A plain copy aliases its storage;
it is not a clone. Keep one active owner. `try_clone()` creates independent
storage. `destroy()` releases storage and resets that owner to an empty string;
copies of the previous owner and borrowed views become invalid.

`as_bytes()` borrows initialized bytes. Treat them as read-only. The language
does not enforce immutable slices; writing this view can violate String's UTF-8
invariant. Mutating methods may invalidate borrowed views. `as_text()` borrows a validated,
length-bearing [Text](stdlib-text.md) in constant time; its subviews and iterators
allocate nothing.

## Operations

| Operation | Behavior |
| --- | --- |
| `as_text` | Borrow a length-bearing Text view without copying or validation |
| `byte_len`, `capacity`, `is_empty` | Query initialized bytes and reserved storage |
| `byte_at` | Optional byte; negative/outside indices give None |
| `is_char_boundary` | Whether an offset is a scalar boundary; the end is a boundary |
| `scalar_count` | Count Unicode scalars in linear time |
| `scalar_at_byte` | Decode at an offset; interior/outside offsets give None |
| `try_reserve` | Reserve a total byte capacity; return the resulting capacity |
| `try_push_scalar` | Append a Unicode scalar; return the new byte length |
| `try_append_utf8`, `try_append`, `try_append_text` | Append bytes, a String or borrowed Text; return the new byte length |
| `try_append_i64`, `try_append_u64` | Append canonical decimal integer text atomically; return the new byte length |
| `try_append_joined`, `try_append_repeated` | Append a complete joined/repeated sequence atomically, including aliased Text views |
| `try_truncate` | Truncate at a scalar boundary; return the resulting byte length |
| `pop_scalar` | Remove and return the last scalar; empty gives None |
| `clear` | Empty the string while retaining capacity |
| `try_clone` | Independent owned copy or AllocationFailed |
| `equals`, `find` | Byte equality or first matching byte offset; empty needle matches zero |
| `compare`, `starts_with`, `ends_with` | Total lexicographic byte order and prefix/suffix tests |
| `try_substring` | Independent copy of a range with scalar-boundary endpoints |
| `try_replace_range`, `try_insert`, `try_remove_range` | Checked byte-range edits; return the new length |
| `trim_ascii` | Remove leading/trailing HT, LF, VT, FF, CR and space in place and return the length |
| `destroy` | Release the allocation and reset this owner |

Fallible edits return `Result`. Invalid UTF-8 records the first malformed or
truncated sequence's starting offset. Other errors distinguish invalid scalars,
bounds, interior byte positions, capacity overflow and allocation failure.
These failures preserve the original contents and owner.

Appending a view into the same string works with spare capacity and with growth.
Growth keeps the old allocation alive until both source copies finish. Capacity
grows geometrically. `find` uses a direct scan with worst-case time proportional
to haystack length times needle length.

Nonempty replacement builds fresh storage before releasing the old buffer, so
replacement may alias the owner. It takes linear time and can fail allocation
even when the existing capacity would fit the result. Removing a range allocates
nothing. Empty substrings also require no allocation.

String implements `core::cmp::Eq<String>` and `Ord<String>`. Ordering compares
UTF-8 bytes, which preserves Unicode scalar order. Generic maps and sorting can
use these traits. Existing containers copy handles rather than automatically
cloning or destroying nested String allocations; keep each key's owner alive
until the container is destroyed, or manage transferred owners explicitly.

## Borrowed collection queries

`alloc::string::TextKey {}` is a zero-sized policy with `borrow()`. It implements
`core::function::Mapper<Pair<String,Text>,bool>` and
`core::ordering::Comparator<String,Text>` for the
[borrowed map/set point methods](stdlib-borrowed-lookup.md). Stored String is
the first operand and borrowed Text the second. Both use exact UTF-8 byte
identity, including NUL, and the same existing FNV-1a hash; ordering is byte
lexicographic. The policy neither owns text nor normalizes it. Keep both
operands' backing live and unchanged during the call. No independent String
query allocation is needed. Actual String/Text owner tests pass for both map
families, including distinct query backing and transferred-owner cleanup;
the linked guide records all nine accepted library groups and their finite scope.
Earlier String receipts below keep their original source/API scope.

## Execution evidence

The native integer constructors and append methods also pass
`tests/stdlib_integer_text_execution.rs`, including signed minima, unsigned
maxima, reuse of reserved capacity and every observed allocation failure.
Failed growth preserves existing borrowed views; syscall traces check cleanup.

On 2026-10-22, all three tests in `tests/stdlib_string_execution.rs` passed
against compiler source `441e66f9` plus this library work, on x86_64 Linux with
an RTX 3090 running the GPU compiler. The follow-up with range edits and generic
collection integration passed all three test groups in 14.42 seconds.

- `alloc_string.lani`: empty and NUL-containing text; 1/2/3/4-byte scalars;
  boundaries, growth, cloning, self-append, reserve, search, truncation,
  clearing, destruction and reuse.
- `alloc_string_invalid.lani`: continuation bytes, overlong encodings,
  surrogates, out-of-range values, bad tails, truncated sequences, negative
  counts and overflow rejected before source access.
- `alloc_string_edits.lani`: independent and empty substrings, malformed
  endpoints, aliasing replacement/insertion, allocation-free removal, ASCII
  trimming, every comparison trait member, generic sorting and string-keyed maps.
- Allocation fixtures use `strace` to fail `mmap`, covering initial allocation,
  growth, reserve, clone, self-append, replacement and substring copying. They verify preserved bytes and
  continued use of the original owner after failure.
- `sample_programs/unicode_text_report.lani` reads stdin, validates UTF-8,
  reports byte/scalar counts and reverses scalars. Tests check exact output
  and status for empty, ASCII, multibyte/NUL and malformed inputs.

Run from the repository root, with `strace` installed:

```sh
timeout --kill-after=2s 100s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" \
  CARGO_INCREMENTAL=0 CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --locked --test stdlib_string_execution -- --nocapture
```

The borrowed-text integration passed this suite again in 12.56 seconds, and
`stdlib_text_execution` tests subview appends and copies under allocation failure.

Wasm and user-program GPU execution are not established. General
formatting, native `str` interoperation and enforced immutable views
remain on the full [library roadmap](library-roadmap.md).
