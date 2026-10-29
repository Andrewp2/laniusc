# Eager Option and Result composition

`core::option` and `core::result` provide type-changing eager selection,
one-level flattening and both optional/fallible transpose directions. The
[fixed plan](library-outcome-composition-plan.md) defines this increment.
All five new library tests and four application groups pass on the finite
native Linux x86_64 profile below. Three selected old regressions and static
inventory have separate receipts. This selected increment is accepted;
earlier Option/Result receipts retain their source and API scope. The full
library goal remains open.

## Type-changing eager selection

```text
option::and<T,U>(Option<T>, Option<U>) -> Option<U>
result::and<T,E,U>(Result<T,E>, Result<U,E>) -> Result<U,E>
result::or<T,E,F>(Result<T,E>, Result<T,F>) -> Result<T,F>
```

| Operation | Left state | Output |
| --- | --- | --- |
| Option `and` | `Some(_)` | The right option, with payload type `U` |
| Option `and` | `None` | `None` of type `Option<U>` |
| Result `and` | `Ok(_)` | The right result, with success type `U` |
| Result `and` | `Err(e)` | The left error `e` |
| Result `or` | `Ok(v)` | The left success `v` |
| Result `or` | `Err(_)` | The right result, with error type `F` |

The matching methods are `Option<T>.and<U>`, `Result<T,E>.and<U>` and
`Result<T,E>.or<F>`. Result `and` requires one shared error type `E`; Result
`or` requires one shared success type `T`. Same-type selection is the case
`U = T` or `F = E`. Option `or` and `xor` continue to require one common
payload type. Presence and success depend on tags: `Some(false)` and `Ok(0)`
are ordinary present/success values.

The widened free functions have additional generic parameters. Explicit
full generic argument lists must supply their new arity; the old explicit
argument lists are not a compatibility contract.

All arguments are evaluated before the call, including an input that
selection discards. No argument evaluation order is promised. These APIs
introduce no lazy callbacks or short-circuit evaluation of operands.

## Flatten and transpose

```text
option::flatten<T>(Option<Option<T>>) -> Option<T>
result::flatten<T,E>(Result<Result<T,E>,E>) -> Result<T,E>
option::transpose_to_result<T,E>(Option<Result<T,E>>) -> Result<Option<T>,E>
option::transpose_to_option<T,E>(Result<Option<T>,E>) -> Option<Result<T,E>>
```

Option flatten keeps the inner option for `Some(inner)` and gives `None`
for outer `None`. Result flatten keeps the inner result for `Ok(inner)` and
keeps the outer error for `Err(e)`. Both Result error layers must have the
same type `E`; flatten does not convert errors.

The transpose functions are inverses on their three-state domains:

| `Option<Result<T,E>>` | `Result<Option<T>,E>` |
| --- | --- |
| `None` | `Ok(None)` |
| `Some(Ok(v))` | `Ok(Some(v))` |
| `Some(Err(e))` | `Err(e)` |

Thus absence remains distinct from a present error. Transpose neither
validates payload contents nor changes a success or error value.

### Specialized methods and module home

| Receiver | Method result | Implementation home |
| --- | --- | --- |
| `Option<Option<T>>` | `.flatten() -> Option<T>` | `core::option` |
| `Result<Result<T,E>,E>` | `.flatten() -> Result<T,E>` | `core::result` |
| `Option<Result<T,E>>` | `.transpose() -> Result<Option<T>,E>` | `core::option` |
| `Result<Option<T>,E>` | `.transpose() -> Option<Result<T,E>>` | `core::option` |

Import `core::option` to include the Result-of-Option receiver extension.
Both transpose free functions live there alongside the existing `ok_or`,
`ok` and `err` conversions. Option imports Result; Result does not import
Option. This preserves the existing import direction and avoids a module
cycle. There is no duplicate transpose entry point in `core::result`.

The selection/shape semantics follow the official Rust
[Option operations](https://doc.rust-lang.org/std/option/enum.Option.html#method.and)
and [Result operations](https://doc.rust-lang.org/std/result/enum.Result.html#method.transpose).
Lanius specifies eager shallow copies and manual ownership separately from
Rust's move/drop behavior.

## Payload, ownership and effects

These operations select or wrap shallow payload copies and leave caller
copies unchanged. They perform no allocation, clone, destruction, callback,
host service, numeric conversion or float arithmetic. Their contract
preserves full-width integer and IEEE payload bits. They introduce no panic
or ordinary error: an output `Err` preserves an input error.

A copied owner does not gain a second cleanup authority. Callers retain
responsibility for owners in both selected and discarded inputs and must
release each actual owner exactly once under its existing policy. A return
value can share the original backing; use of that backing must finish before
its actual owner is released. The calls do not free discarded resources.
Borrowed slices and strings retain their original lifetime and alias rules.
No automatic ownership, arbitrary generic-composition or formal claim follows.

## Optional-field application

The real [optional-sum program](stdlib-optional-sum.md) uses both public
transpose directions to distinguish missing, valid and invalid signed-i64
records. It reuses the decimal parser and checked addition, validates through
EOF and computes the total in input order before publishing CSV. Its input
owner and output-prefix failure policy are separate from these pure APIs.
All four application groups pass 98 native cases: model 33 in 7.26s, then
CLI 17, rejection 30 and I/O 18 in 8.02s. Receipts are
`target/stdlib-work/outcome-composition-app-model-first.log` and
`target/stdlib-work/outcome-composition-app-boundaries-first.log`.
Five selected allocation denials reach actual owner setup/growth; required-EOF
failure leaves stdout empty. A genuine file-size limit produces a ten-byte
output prefix followed by EFBIG, with no fabricated successful write counts.
Finite 8,192-attempt controls and cleanup observations have their precise
scopes in the [application guide](stdlib-optional-sum.md).

## Verification and target

One registered specialized-method admission test passes in 4.87 seconds:
`target/stdlib-work/outcome-composition-admission-first.log`. The small
native executable calls all four specialized methods, including imported
`Result<Option<T>,E>.transpose`. The
[contract fixture guide](../tests/fixtures/stdlib_foundation/outcome_composition/README.md)
records the producer and selected command. This establishes those literal
method calls, with no missing compiler dependency observed in that fixture.

The broader contract test passes in 6.81 seconds, recorded in
`target/stdlib-work/outcome-composition-contracts-first.log`. It covers eager
cross-type selection, all flatten/transpose states, inverse compositions,
preserved originals, compound/nested payloads, full-width integers, exact
IEEE encodings and borrowed strided slices, without selected memory or host
I/O services. This is separate from the small admission.

The [independent tagged-value model](../tests/fixtures/stdlib_foundation/outcome_composition_model/README.md)
passes one test in 6.94 seconds:
`target/stdlib-work/outcome-composition-model-first.log`. Its 2,180 cases
cover nine operations through free functions and methods with seed
`0xa7c20261031`. Every case checks output tags/payloads and original input
copies; inverse cases also check their intermediate shape. Float observations
use integer bits rather than Python floating values.

The [owner/memory gate](../tests/fixtures/stdlib_foundation/outcome_composition_memory/README.md)
passes one test in 7.28 seconds:
`target/stdlib-work/outcome-composition-memory-final.log`. Six real records
have twelve backing allocations; seven pure conversion phases make zero host
calls and all twelve actual backings are explicitly released once. These are
finite observed owner paths, not a general lifetime or failure proof. The
initial fixture assumed capacity three; its corrected check uses the actual
capacity and requires it to cover the length. Production did not change.
The instrumented whole native lifecycle took 12ms; this is not an isolated
conversion benchmark.

The focused negative-shape test passes in 7.71 seconds:
`target/stdlib-work/outcome-composition-negative-shapes-first.log`. Six
separate typed calls reject with `LNC0006`: mismatched Result `and` error
types, mismatched Result `or` success types, and wrong flatten/transpose input
shapes. These are diagnostic checks, separate from runtime evidence.

Three selected existing regressions pass separately:

| Regression | Scope | Receipt under `target/stdlib-work/` |
| --- | --- | --- |
| Result methods | One test, nine payload combinations, 9.64s | `outcome-composition-result-method-regression.log` |
| Option | One test, three scalar/string free-function and method fixtures, 6.86s | `outcome-composition-option-regression.log` |
| Result negative types | One test, eight rejected calls/receiving types, 6.72s | `outcome-composition-result-negative-regression.log` |

The CPU-only source inventory passes one test in 0.01s with four runtime
tests filtered: `target/stdlib-work/outcome-composition-static-inventory-final.log`.
It recognizes explicit generic calls and checks the current Option/Result
surface against the old and new executing fixtures. This is bookkeeping,
not an extra native execution. Its initial failure came from the preceding
endian increment's missing inventory fixture; adding that existing fixture
corrected the global inventory without a production change.

Executed production sources:

| Module | SHA-256 |
| --- | --- |
| [core::option](../stdlib/core/option.lani) | `8b3cf42862f2c6c0203281d5b2b120124c0df74d1b0c664418f5a6e9f57938ee` |
| [core::result](../stdlib/core/result.lani) | `1a036786910bdcb2f637a1d5e89d08881c2a2dea758beadc488065f8b23e748b` |

These selected receipts do not establish general generic completeness or
freshly revalidate every historical compiler boundary. No new compiler
dependency was found for this increment's selected surface.

The accepted target is native Linux x86_64 CPU output produced by the GPU
compiler. GPU-device execution and other backends are unverified for this
increment. Source/reference inventory is separate from runtime acceptance.
This increment adds no compiler, ABI, host-service or proof changes.
