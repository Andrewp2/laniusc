# Required trait method return context

These test-only imported modules exercise local trait declarations in a loaded
source closure. `Produce<T,E>` returns `Result<T,E>` and `Nested<T,E>` returns
`Result<Option<T>,E>`. Their required methods use `E` only in the return type.
The caller must preserve the admitted bound's `E`; receiving context cannot
replace it. The generic helpers deliberately declare their parameters as
`<E,T>`, reversing the trait's order.

`native.lani` executes success and failure paths with a user record containing
`u64` and `i32`, an error enum containing negative `i32` and high `u64` payloads,
and nested `Some`, `None`, and `Err` values. It also executes ordinary generic
receiving-type inference as a control. No fixture allocates or performs host IO.

The separate rejection fixtures preserve these boundaries:

| Source | Rejected contract | Diagnostic |
| --- | --- | --- |
| `symbolic_conflict.lani` | Bound error parameter `E` returned as unrelated `F` | `LNC0006` |
| `closed_conflict.lani` | Bound error `Fault` returned as `i64` | `LNC0006` |
| `wrong_source.lani` | `i32` argument supplied where the bound requires `T` | `LNC0006` |
| `missing_bound.lani` | Generic receiver has no required-method bound | `LNC0027` |

The Rust driver compiles and executes `native.lani`, compiles all rejection
fixtures, executes a different ordinary generic program, and compiles and
executes `native.lani` again in the same process. This also checks reuse of GPU
metadata across compilation jobs. Every executable passes the common strict x86
control-transfer checker before execution. Successful runs must exit zero and
produce no output.

Run the focused target with:

```sh
cargo test --test compiler_trait_return_context_execution -- --test-threads=1
```

This evidence covers GPU-compiled x86-64 Linux execution. It does not claim
arbitrary generic implementation forwarding, external binary trait interfaces,
or GPU kernel execution.
