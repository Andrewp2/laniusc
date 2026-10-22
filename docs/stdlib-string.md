# Owned UTF-8 strings

`alloc::string::String` stores valid UTF-8 in a generic vector of packed `u8`
bytes. NUL and U+10FFFF are valid. It does not normalize text. Scalar operations
do not operate on grapheme clusters.

## Construction and ownership

`alloc::string::new()` creates an empty string without allocation.
`alloc::string::from_utf8(bytes, count)` validates and copies a byte slice,
returning `Result<String, Error>`. The slice must physically back `count` bytes;
negative counts return `Bounds`, while an overclaimed physical view traps.
Construction from native `str` awaits the length projection listed in
[library-dependencies.md](library-dependencies.md).

Methods borrow and mutate the owning String. A plain copy aliases its storage;
it is not a clone. Keep one active owner. `try_clone()` creates independent
storage. `destroy()` releases storage and resets that owner to an empty string;
copies of the previous owner and borrowed views become invalid.

`as_bytes()` borrows initialized bytes. Treat them as read-only. The language
does not enforce immutable slices; writing this view can violate String's UTF-8
invariant. Mutating methods may invalidate borrowed views.

## Operations

| Operation | Behavior |
| --- | --- |
| `byte_len`, `capacity`, `is_empty` | Query initialized bytes and reserved storage |
| `byte_at` | Optional byte; negative/outside indices give None |
| `is_char_boundary` | Whether an offset is a scalar boundary; the end is a boundary |
| `scalar_count` | Count Unicode scalars in linear time |
| `scalar_at_byte` | Decode at an offset; interior/outside offsets give None |
| `try_reserve` | Reserve a total byte capacity; return the resulting capacity |
| `try_push_scalar` | Append a Unicode scalar; return the new byte length |
| `try_append_utf8`, `try_append` | Append bytes or a String; return the new byte length |
| `try_truncate` | Truncate at a scalar boundary; return the resulting byte length |
| `pop_scalar` | Remove and return the last scalar; empty gives None |
| `clear` | Empty the string while retaining capacity |
| `try_clone` | Independent owned copy or AllocationFailed |
| `equals`, `find` | Byte equality or first matching byte offset; empty needle matches zero |
| `destroy` | Release the allocation and reset this owner |

Fallible edits return `Result`. Invalid UTF-8 records the first malformed or
truncated sequence's starting offset. Other errors distinguish invalid scalars,
bounds, interior byte positions, capacity overflow and allocation failure.
These failures preserve the original contents and owner.

Appending a view into the same string works with spare capacity and with growth.
Growth keeps the old allocation alive until both source copies finish. Capacity
grows geometrically. `find` uses a direct scan with worst-case time proportional
to haystack length times needle length.

## Execution evidence

On 2026-10-22, all three tests in `tests/stdlib_string_execution.rs` passed
against compiler source `441e66f9` plus this library work, on x86_64 Linux with
an RTX 3090 running the GPU compiler. Combined test runtime: 10.22 seconds.

- `alloc_string.lani`: empty and NUL-containing text; 1/2/3/4-byte scalars;
  boundaries, growth, cloning, self-append, reserve, search, truncation,
  clearing, destruction and reuse.
- `alloc_string_invalid.lani`: continuation bytes, overlong encodings,
  surrogates, out-of-range values, bad tails, truncated sequences, negative
  counts and overflow rejected before source access.
- Allocation fixtures use `strace` to fail `mmap`, covering initial allocation,
  growth, reserve, clone and self-append. They verify preserved bytes and
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

Wasm and user-program GPU execution are not established. Insertion/replacement,
splitting/joining, formatting, native `str` interoperation and immutable views
remain on the full [library roadmap](library-roadmap.md).
