# Language ergonomics: item imports, `?`, local inference, block arms

Four features shorten ordinary Lanius code without adding hidden behavior.
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

Decision: no implicit conversions. An error type change is written out,
e.g. with `map_err`, so the reader sees each conversion at its site.

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

A generic call's type arguments come from three sources, so most calls need
no turbofish:
- its value arguments;
- the type its result must have (a `let` annotation, a parameter, a return);
- its bounds. If a type parameter `P: Tr<A>` is bound to a closed type and
  exactly one implementation of `Tr` matches that type, the implementation's
  trait arguments bind `A`. So `core::iter::map(it.borrow(), m.borrow())`
  infers its item types from the iterator and mapper impls. Zero or several matching
  impls infer nothing. The rule and its limits (imported free functions only)
  are in `docs/compiler-generic-types.md`, "Bound-directed generic call
  inference".

Every source must agree. A binding that contradicts an explicit turbofish or
annotation is `LNC0008`.

Inference is local to one call and its direct context. It does not flow
forward from later uses. A `let` whose type only a later statement could
decide needs an annotation, e.g. `let v: Vec<i32> = Vec::new();`.

Decision: inference stays local so that each binding's type can be read from
its own line and its callee's signature.

## Block arms

A match arm can run statements: `pattern -> { statements }`. Its block must
not complete. Every path through it ends in `return` or a call of a `-> !`
function, so the arm has the never type and the match takes the type of its
other arms. A `match` whose every arm is a returning block ends a function
body the way a `return` does.

```lanius
fn step(&mut self, event: Input) -> Reply {
    match (event) {
        Input::Open -> {
            if (self.locked) { return Reply::Ignored; }
            self.opens += 1;
            return Reply::Done;
        },
        Input::Lock(code) -> { self.stored = code; return Reply::Done; },
        Input::Close -> { return Reply::Done; },
        Input::Unlock(_) -> { return Reply::Ignored; },
    };
}
```

A block arm that can reach its end is a type error (`LNC0006`): "the end of
this block arm can be reached". `break` and `continue` inside the block do
not count as leaving it.

Decision: only diverging blocks for now. A block arm that falls through
would need a unit-typed match, with joins of unit arms and arms that branch
to the match's end. The diverging form is what state machines need (each
arm ends in a transition, docs/state-machines-design.md) and what early
returns from one case need. Unit arms can be added later without changing
these programs.

Implementation:
- A `{` right after a match arm's `->` takes the `if` block's brace kinds
  (`tokens/delimiters/04_owner_apply`), and the production
  `primary [arm_block] -> if_block` makes the block a primary. The arm's
  result is the HIR block (`hir/expr/fields`), so its statements are ordinary
  statements.
- `type_checker/modules/10n_type_match_exprs` types a block result as never.
- `type_checker/returns/01_mark` treats a match as a counting latch over its
  block arms: a fact that every path through an arm block returns sets that
  block's flag once, and the arm that completes the count carries the fact to
  the match's own context. `03_validate` rejects a block arm whose flag is
  unset.
- Codegen needs no change: rows are scheduled by token position, so the
  block's statements fall between the arm's test and its end.

