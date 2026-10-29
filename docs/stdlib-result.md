# `core::result::Result<T, E>`

`Result<T, E>` is either `Ok(T)` or `Err(E)`. The tag decides which payload
is active, so `Ok(0)`, `Ok(false)` and an `Err` holding zero are all ordinary
values. A result does not allocate, and it does not own storage that its
payloads borrow.

Every operation takes the result by value, so the caller's copy is never
changed. Each exists as a free function, `core::result::is_ok(value)`, and as
a method, `value.is_ok()`.
The specialized Result-of-Option `transpose` method is defined in
`core::option`; import that module to include the extension.

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
| `or<T,E,F>(value, fallback)` | Left `Ok(T)` wins; left `Err(E)` selects the eager `Result<T,F>` fallback, including its error. Both inputs share `T`. |
| `and<T,E,U>(value, next)` | Left `Ok(T)` selects the eager `Result<U,E>` next value; left `Err(E)` preserves that error. Both inputs share `E`. |
| `flatten<T,E>(value)` | `Ok(inner)` gives the inner `Result<T,E>`; outer `Err(e)` keeps `e`. Both error layers share `E`. |

Conversions to and from `Option` are in `core::option`: `ok_or`, `ok`, `err`,
`transpose_to_result` and `transpose_to_option`. `core::result` does not
import `core::option`.

The `PartialEq` impls in `core::cmp` cover every integer width, `bool`, `char`,
`f32` and `f64` (IEEE equality), `ptr` and the wide integers; a user type implements
`core::cmp::PartialEq` for itself.

## Eager composition and nested methods

`Result<Result<T,E>,E>.flatten()` removes one result layer; both nested error
types must match. `Result<Option<T>,E>.transpose()` uses the extension in
`core::option` to preserve absence, success and error as distinct states.
The [outcome-composition guide](stdlib-outcome-composition.md) gives both
transpose tables and the widened selection signatures.

All arguments are evaluated before selection, with no promised evaluation
order. Operations copy shallow values and do no allocation, clone or cleanup;
owners in selected and discarded inputs retain the caller's cleanup policy.
All four specialized Option/Result methods pass small native admission;
broader composition contracts, the independent model and owner/memory
observations also pass. All four real optional-sum application groups pass
98 cases, and six focused type rejections pass separately. This selected
composition increment is accepted on native Linux x86_64; the new guide
records selected regressions and CPU inventory separately. The earlier
receipts below retain their original scope.

## Targets and limits

The scope and reported boundaries below predate the composition increment;
they are not fresh reproductions or evidence for its added signatures. The
new guide records current selected checks separately.

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
