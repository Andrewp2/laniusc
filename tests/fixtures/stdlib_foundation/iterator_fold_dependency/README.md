# Generic method result inside an error record

The bounded iterator-fold implementation exposed an inference failure while
constructing `FoldFailure<E>` with `error:step.unwrap_err()` inside an outer
`Result::Err`. The original compiler diagnostic was `LNC0006`: expected the
generic error parameter, found `void`. This identifies an expression-context
inference dependency; it does not establish a failure of generic iteration,
generic records or `Result` payload storage as a whole.

`inline.lani` removes all iterator and callback machinery. Its generic helper
accepts `Result<A,E>` and returns `Result<A,Failure<E>>`, nesting
`step.unwrap_err()` directly in the record field. `typed_local.lani` changes
only that expression into an explicitly typed `let error:E` before the same
record construction. Neither fixture imports `core::iter`.

Both forms are valid source. Their `main` functions have the same executable
assertions: preserve an error value greater than signed `i64::MAX`, its progress
field and a separate successful `i32` payload. The explicit local is the
library workaround; it introduces no type-specific API or payload restriction.

## Verification status

Both focused driver tests passed in 4.39 seconds. The receipt is
`target/stdlib-work/iterator-fold-dependency-corrected.log`.

- `inline.lani` independently rejects with `LNC0006` on line 10 at
  `error:step.unwrap_err()`: expected generic parameter 1, found an unknown
  type. The larger library expression reported `void` instead; these are
  separate observed diagnostics at the same nested-expression boundary.
- `typed_local.lani` compiles and executes successfully. Its assertions
  preserve the wide error value, progress field and separate successful
  payload. This is the executable workaround control.

The two passing Rust tests therefore establish one reproduced diagnostic and
one native positive control, not two successfully executed source forms.
The earlier driver build attempt failed because its Rust helper passed a
`String` where `&str` was required; that harness argument was corrected before
either fixture ran. Its distinct log is
`target/stdlib-work/iterator-fold-dependency-first.log`.

Accepted source identities are:

| File | SHA-256 |
| --- | --- |
| `inline.lani` | `5d84ed704ee0b23279ce03172abba358d86bdfbf8c588bfa4810b448b808f5d6` |
| `typed_local.lani` | `0a121aac960802533e978c2c09a09612673a85711f362f65aea1825dcbac8f55` |
| `tests/stdlib_iterator_fold_dependency_execution.rs` | `e6fcf47bf9d96f296616e9f031cb64a89495a87bd833707f3682d280c57a1b4f` |

The driver received whitespace-only `rustfmt` formatting after the recorded
receipt; its executed pre-format SHA-256 was
`6e6ac530149315847c40ea4b9ac53fa80092f68954f4b46b0f2cdefc693d76fe`.
The fixture sources and executable assertions are unchanged.

`tests/stdlib_iterator_fold_dependency_execution.rs` always requires the
typed-local control to compile and execute. For the inline form, it accepts
the documented source-local `LNC0006` or, after a compiler repair, requires the
unchanged source to compile and execute its assertions. No test requires valid
source to remain rejected. No compiler production code is changed here.
