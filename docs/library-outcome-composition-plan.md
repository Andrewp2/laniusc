# Eager Option and Result composition

The next foundation increment completes type-changing eager selection and
nested optional/fallible shape conversions. At its start, Option.and fixes
both payloads to T; Result.and fixes both success types, and Result.or fixes
both error types. Neither transpose direction nor Result flatten exists.
Option flatten and optional pairing already exist and must be reused.

## Public contracts

Widen these existing free functions and their methods:

```text
option::and<T,U>(Option<T>, Option<U>) -> Option<U>
result::and<T,E,U>(Result<T,E>, Result<U,E>) -> Result<U,E>
result::or<T,E,F>(Result<T,E>, Result<T,F>) -> Result<T,F>
```

Option.and selects the right option for a present left option, otherwise
returns None of the output type. Result.and selects the right result for
left success, otherwise preserves the left error. Result.or preserves left
success, otherwise selects the right result, including its new error type.
Option.or and xor retain one common payload type.

Add these free functions:

```text
result::flatten<T,E>(Result<Result<T,E>,E>) -> Result<T,E>
option::transpose_to_result<T,E>(Option<Result<T,E>>) -> Result<Option<T>,E>
option::transpose_to_option<T,E>(Result<Option<T>,E>) -> Option<Result<T,E>>
```

Flatten returns the inner result for outer success and the outer error for
outer failure. Transpose-to-result maps None to Ok(None), Some(Ok(v)) to
Ok(Some(v)), and Some(Err(e)) to Err(e). The opposite transpose maps Ok(None)
to None, Ok(Some(v)) to Some(Ok(v)), and Err(e) to Some(Err(e)). These
transposes are inverse for their respective three-state domains.

Provide specialized `.flatten()` on nested Option and nested Result and
`.transpose()` on the two transpose receiver shapes. Keep the existing
Option free flatten function. Both transpose definitions and their receiver
extensions live in core::option, the existing conversion home: Option already
imports Result, while a reverse import creates a module cycle rejected by
the current compiler tests. Do not change compiler cycle policy or nominal
type identities. Admit specialized imported-enum methods with a small native
fixture first; if unsupported, retain a minimal reproduction and report the
specific compiler dependency before deciding the library surface.

These operations take eagerly evaluated values. They select shallow payload
copies, leave caller copies unchanged and neither allocate, clone, destroy
nor create a second cleanup authority. Callers remain responsible for owners
in both selected and discarded input copies. They perform no callback, host
service, checked numeric conversion or float arithmetic. Preserve every
payload bit, including full-width integers and IEEE encodings. No panic or
ordinary error is introduced by a shape conversion.

Semantic references are the official Rust
[Option operations](https://doc.rust-lang.org/std/option/enum.Option.html#method.and)
and [Result operations](https://doc.rust-lang.org/std/result/enum.Result.html#method.transpose).
Lanius's eager shallow-copy/manual-ownership policy is explicit and separate
from Rust's move/drop behavior.

## Evidence and boundaries

- Native admission of specialized methods, then all variant tables through
  free functions and methods, cross-type payloads/errors and same-type callers.
- Independent model checking selection, flatten and both transpose directions
  and inverse compositions, with reproducible payload variation.
- Records, nested enums/arrays, borrowed strided slices, full-width integers
  and exact float payload transfer; check output values and caller copies.
- Real String/Vec owners: stable backing identity, no host calls within pure
  conversion phases and exactly one explicit release per actual owner.
- Focused negative bounds/type cases distinguish the retained shared error
  or success requirements from the newly allowed changing type.
- A bounded optional-field validation program uses transpose to distinguish
  missing, valid and invalid input, with executable CLI/input/output/error
  evidence. It must call the public operations rather than reimplement them.
- Select existing Option/Result runtime regressions for changed signatures.
  Static reference generation is inventory evidence, never runtime acceptance.

Source and tests remain libraries/examples owned by this branch. No compiler,
IR, extractor, formal, ABI, root README or human policy changes. Root alone
runs compiler/native/Cargo commands serially under the existing lock; every
command stays below two minutes. Other agents may run static/CPU oracle
checks. The supported target is claimed only after runtime acceptance; GPU
device execution is separate. The complete library goal remains open.

## Real program: optional_sum

`optional_sum` reads stdin as LF-delimited records. Each nonempty record is
exactly `-` for missing, or a signed decimal i64 accepted by the existing
core::decimal parser. No whitespace trimming or CR removal. A final nonempty
record without LF is accepted; a terminating LF adds no empty record. Empty
input has zero records. Interior empty records are invalid. Record length is
at most 64 bytes excluding LF, at most 65,536 records and 1,048,576 input
bytes. Sum present values with checked i64 arithmetic in input order; an
intermediate overflow is an error even if later values would cancel it.

Output is exactly one CSV header and one data row:

```text
present,missing,sum
2,1,4
```

Missing contributes no sum. Distinguish missing/success/error with the public
transpose operations; reuse the existing numeric parser and checked addition.
The program may use the widened eager operations to preserve successful
payloads while selecting its application error category. Do not invent a new
parser or private replacement for transpose. Full EOF, input validation and
sum computation precede stdout. Stage the small output in caller storage.
Input has one explicitly released bounded buffer owner; argv capture has its
own owner. Each input/output phase permits at most 8,192 stream calls,
including EINTR; help permits 64 writes and diagnostics eight. Reuse existing
descriptor I/O with explicit prefix failure; these are attempt budgets rather
than blocking-I/O deadlines.

The only option is sole `--help` or `-h`, bypassing input; no operands.
Capture at most one argument/64 bytes. Status 0 is success/help; 2 is CLI,
syntax/range/count/byte/line/attempt-bound or sum overflow; 3 is input/argv
host error; 4 is allocation failure; 5 is output or SIGPIPE-policy failure;
6 is an unexpected internal formatting/buffer contract failure. Diagnostic
is `optional_sum: operation failed\n`; preserve primary status if it fails.
Ignore SIGPIPE before I/O. App author freezes help text before oracle
acceptance. App faults must cover prepublication input/EOF errors, output
prefix behavior where feasible and reached owner cleanup without claiming
general leak freedom.
