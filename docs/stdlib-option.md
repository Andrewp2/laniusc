# `core::option::Option<T>`

`Option<T>` is either `Some(T)` or `None`. Presence is the enum's tag, not a
property of the payload: `Some(false)`, `Some(0)` and `Some("")` are present.
`None()` constructs absence and `None` is the match pattern. An option does
not allocate, and it does not own storage that its payload borrows.

```lanius
import core::option;

struct Pair { first: i32, second: i32 }

fn pair_or(value: core::option::Option<Pair>, fallback: Pair) -> Pair {
    return match (value) {
        core::option::Some(inner) -> inner,
        core::option::None -> fallback,
    };
}
```

Every operation takes the option by value, so the caller's copy is never
changed. Each exists as a free function, `core::option::is_some(value)`, and
as a method, `value.is_some()`, except `flatten`, `ok` and `err`, which are
free functions only.

## Operations

| Operation | Behavior |
| --- | --- |
| `Some(value)`, `None()` | Construct an option. `None()` takes its payload type from context: a typed `let`, a parameter or a return type. |
| `is_some`, `is_none` | Inspect the tag only. |
| `contains(value, expected)` | True when present and equal to `expected`. Needs `T: core::cmp::PartialEq<T>`. |
| `unwrap(value)` | The payload; panics (SIGILL) on `None`. |
| `unwrap_or(value, fallback)` | The payload, or `fallback` on `None`. Never panics. |
| `or(value, fallback)` | `value` when present, otherwise `fallback`. |
| `and(value, next)` | `next` when `value` is present, otherwise `None`. |
| `xor(value, right)` | The only present input; `None` when both or neither are present. |
| `flatten(value)` | `Some(Some(v))` gives `Some(v)`; `Some(None)` and `None` give `None`. |
| `ok_or(value, error)` | `Ok(payload)`, or `Err(error)` on `None`, as a `core::result::Result<T, E>`. |
| `ok(result)`, `err(result)` | The success value or the error of a `Result<T, E>` as an option. |

`core::cmp` implements `PartialEq` for every integer width, `bool`, `char`, `f32`, `f64`,
`ptr`, and the wide integers in `core::wide_i64` and `core::wide_u64`. A user
type gets `contains` by implementing `core::cmp::PartialEq` for itself. `f32`
equality is IEEE: `Some(NaN)` contains nothing, and `0.0` matches `-0.0`.

## Targets and limits

- x86_64 Linux runs every operation for every payload type above, user
  records, and nested options.
- Wasm: a function whose result type is `Option<T>` compiles to an invalid
  module (generics backlog b16). Locals and calls into the stdlib run.
- Calling the `unwrap` method on an `Option<T>` from a generic body where T
  is a record segfaults (backlog b17). The free `core::option::unwrap` runs
  there, and the method runs outside generic bodies.
- Borrowed payloads (slices, strings) keep pointing at the caller's storage,
  which must outlive the option.

## Verification

- `tests/fixtures/stdlib_foundation/core_option_result.lani` runs every free
  function and method through one generic checker for i8, i16, i32, i64,
  isize, u8, u16, u32, u64, usize, bool, char, f32, ptr, both wide integers
  and a user record. `tests/stdlib_foundation_execution.rs` runs it and checks
  that it calls every public function and method of `core::option`.
- `tests/stdlib_option_scalar_execution.rs` checks every state pair of the
  combinators for scalar payloads, NaN membership and negative zero.
- `tests/stdlib_option_bool_execution.rs`, `stdlib_option_slice_execution.rs`
  and `stdlib_generic_predicates_execution.rs` cover bool payloads, slice
  payloads (aliasing, empty views, bounds traps) and multiword payloads.
- [`first_valid_reading.lani`](../sample_programs/first_valid_reading.lani),
  [`optional_reading_summary.lani`](../sample_programs/optional_reading_summary.lani)
  and [`optional_slice_window.lani`](../sample_programs/optional_slice_window.lani)
  are sample programs built on `Option`.
