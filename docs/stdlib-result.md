# `core::result::Result<T, E>`

`Result<T, E>` is either `Ok(T)` or `Err(E)`. The tag decides which payload
is active, so `Ok(0)`, `Ok(false)` and an `Err` holding zero are all ordinary
values. A result does not allocate, and it does not own storage that its
payloads borrow.

Every operation takes the result by value, so the caller's copy is never
changed. Each exists as a free function, `core::result::is_ok(value)`, and as
a method, `value.is_ok()`.

## Operations

| Operation | Behavior |
| --- | --- |
| `Ok(value)`, `Err(error)` | Construct a result. The other payload type comes from context: a typed `let`, a parameter or a return type. |
| `is_ok`, `is_err` | Inspect the tag only. |
| `contains(value, expected)` | True for `Ok` equal to `expected`. Needs `T: core::cmp::PartialEq<T>`. |
| `contains_err(value, expected)` | True for `Err` equal to `expected`. Needs `E: core::cmp::PartialEq<E>`. |
| `unwrap(value)`, `unwrap_err(value)` | The success value or the error; each panics (SIGILL) on the other variant. |
| `unwrap_or(value, fallback)` | The success value, or `fallback` for an error. Never panics. |
| `unwrap_err_or(value, fallback)` | The error, or `fallback` for a success. Never panics. |
| `or(value, fallback)` | `value` when it is `Ok`, otherwise `fallback`; two errors give the fallback's error. |
| `and(value, next)` | `next` when `value` is `Ok`, otherwise `value`'s error. |

Conversions to and from `Option` are in `core::option`: `ok_or`, `ok` and
`err`. `core::result` does not import `core::option`.

The `PartialEq` impls in `core::cmp` cover every integer width, `bool`, `char`,
`f32` and `f64` (IEEE equality), `ptr` and the wide integers; a user type implements
`core::cmp::PartialEq` for itself.

## Targets and limits

- x86_64 Linux runs every operation for every payload type above, user
  records, slices, strings and fixed arrays.
- Wasm: a function whose result type is a `Result<T, E>` compiles to an
  invalid module (generics backlog b16).
- Calling the `unwrap` or `unwrap_err` method from a generic body where the
  payload is a record segfaults (backlog b17); the free functions run there.
- Borrowed payloads keep pointing at the caller's storage, which must outlive
  the result.

## Verification

- `tests/fixtures/stdlib_foundation/core_option_result.lani` runs every free
  function and method through one generic checker for every payload type
  above, a user record, and a result whose two payload types differ.
  `tests/stdlib_foundation_execution.rs` checks that it calls every public
  function and method of `core::result`.
- `tests/stdlib_result_generic_execution.rs` and
  `tests/stdlib_result_methods_execution.rs` cover every state pair of the
  combinators, NaN and negative zero, string, slice and array payloads, bounds
  traps through recovered views, and rejected payload types.
- [`result_reading_total.lani`](../sample_programs/result_reading_total.lani)
  validates readings into a `Result` and prints `20` and `-2`.
