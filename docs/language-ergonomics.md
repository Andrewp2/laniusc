# Language ergonomics: item imports, `?`, local inference

Three features shorten ordinary Lanius code without adding hidden behavior.
Each section states what the feature does, what it refuses, and the
decision behind it. Tests: `tests/language_ergonomics_execution.rs`, fixtures
in `tests/fixtures/language/`.

## Item imports

`import a::b::item;` makes the one declaration `item` of module `a::b`
visible by its short name. `import a::b;` still imports every public item of
module `a::b`.

- An import path names a module if one exists with that whole path. Only when
  no module has that path is the last segment read as an item of the prefix
  module. So a module wins over an item of the same name.
- An item import beats module imports for its name. If two module imports
  both supply a name and no item import picks one, using the name is the
  error `LNC0005 ambiguous imported name`. The diagnostic names one
  `import` line that would settle it.
- The item import makes only that item visible. Other items of its module
  stay unresolved until imported.

Decision: no aliases (`as`), no globs, no re-exports. A short name always
means one declaration that the reader can find from the import lines.

## `?`: early return from `Result` and `Option`

`value?` takes a `core::result::Result<T, E>` or `core::option::Option<T>`.

- On `Ok(t)` or `Some(t)`, the expression's value is `t`.
- On `Err(e)`, the function returns `Err(e)`. On `None`, it returns `None`.

The function's result must be the same enum: a `Result<U, E>` with exactly the
same `E`, or an `Option<U>`. The success types `T` and `U` may differ.

`?` never converts. There is no `From`. An `i64` error does not leave a
function whose error type is `i32`, and an `Option` does not become a
`Result`. Both are type errors (`LNC0006`), labeled at the `?`:

- "`?` needs a `core::result::Result` or `core::option::Option` value" when
  the operand is any other type.
- "`?` returns this error from a function whose result type differs" when the
  enum or the exact error type does not match.

Decision: README "Honesty" forbids implicit conversions, so an error type
change is written out, e.g. with `map_err`.

Implementation:
- The parser has a postfix `?` production (HIR kind 36).
- `type_checker/calls/03f_infer_return_bindings` gives the expression the
  operand's payload type and checks it against the enclosing function's
  result type.
- Codegen lowers it to 13 rows in `codegen/lir/semantic/try_rows`: test the
  tag, build the function's `Err(e)` or `None` and return it, else load the
  payload. Each `?` takes one aggregate element from its own segment in
  `aggregate_elements`.

## Local type inference

A `let` without an annotation takes the type of its initializer, including
a `?` expression or a generic call (`let h = half(x)?;`).

A generic function's type arguments are inferred from its value arguments
and from the type the call's result must have, so calls need no turbofish.
Inference is local to one call and its direct context. It does not flow
forward from later uses. A `let` whose type only a later statement could
decide needs an annotation, e.g. `let v: Vec<i32> = Vec::new();`.

Decision: inference stays local so that each binding's type can be read from
its own line and its callee's signature.
