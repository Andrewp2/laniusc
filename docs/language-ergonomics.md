# Language ergonomics: item imports, `?`, local inference, block arms, path calls, C callbacks, `else if`

Seven features shorten ordinary Lanius code without adding hidden behavior.
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

Inside a loop, an arm may also end in `break` or `continue` of that loop
(a state machine's `run` loops use this). Such an arm leaves the match but
not the function: a function whose only exit is a `break` still needs its
`return`.

A block arm that can reach its end is a type error (`LNC0006`): "the end of
this block arm can be reached". A `break` or `continue` of a loop inside the
block does not count as leaving it.

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
  the match's own context. A `break` or `continue` publishes the same fact,
  which stops at its loop and never marks the function. `03_validate`
  rejects a block arm whose flag is unset.
- Codegen needs no change: rows are scheduled by token position, so the
  block's statements fall between the arm's test and its end.


## Methods called through a type's path

`Type::method(receiver, args...)` calls any method of the type, the way
`receiver.method(args...)` does: a `self` or `&self` method takes its
receiver as the first argument. `S::get(s, 1)`, `S::peek(r, 2)` with
`r: &S`, `TotalF32::to_bits(t)` from the standard library, and `T::tw(x, 3)`
through a bound `T: Tw<T>` all work.

- The path form never adjusts the receiver. A `&self` method needs a `&S`
  argument (`S::peek(s.borrow(), 2)`; Lanius has no `&expr`), and passing
  `s` itself is `LNC0006`, as is any other wrong type. A missing argument
  is `LNC0027`.
- A bare generic type infers its parameters from the arguments and the
  result context: `let w: W<i32> = W::wrap(9);`, `W::get(w)`. A parameter
  that nothing determines is `LNC0006`; `W<i32>::make()` names it. The same
  holds for an imported generic type: `Option::is_some(o)`,
  `Option::unwrap_or(o, 7)` and `Result::unwrap(r)`.

Decision: the path form is plain function-call syntax with the receiver
spelled out, so it neither autoreferences nor dereferences. That keeps
`Type::method` usable as an unambiguous name for one method when several
types or traits share it.

Implementation: methods/07 and 07a offer self members to path calls,
methods/02b types the syntactic self parameter row from the impl root,
dependencies/07b and 08 type an imported method's receiver argument from its
impl root (behind one reference for `&self`), and calls/03d binds no
parameter from a bare generic qualifier. A bare imported generic qualifier
names its declaration's own application, an external canonical type
(dependencies/14), which only dependencies/15a matches against impl roots.
Fixtures: `tests/fixtures/compiler_defects/b14_path_self_method_*.lani`,
`b19_stdlib_path_self_method.lani`, `generic_impl_path_inference.lani`, and
`tests/fixtures/generics_matrix/p82_imported_type_path_self_method/` and
`p83_bare_imported_type_path_self_method.lani`.

## `else if`

`else` takes a block or another `if` statement. The second form needs no
braces around the nested statement:

```lanius
if (n < 0) {
    return 1;
} else if (n == 0) {
    return 2;
} else {
    return 3;
}
```

- The conditions are evaluated in order. The first true one selects its arm,
  and the conditions after it are not evaluated.
- A chain without a final `else` runs no arm when every condition is false.
- A chain in which every arm returns, including a final `else`, ends a
  function body the way a `return` does.
- Each arm is its own scope. A `let` in one arm is not visible in another.
- The condition keeps its parentheses, and `else` still needs a block or an
  `if`. `else if n > 3 {` and `else return 2;` are syntax errors (`LNC0016`).

`else if (c) { ... }` means the same as `else { if (c) { ... } }`. The grammar
production `else_if` makes the nested statement the else arm of the enclosing
one (`grammar/lanius.bnf`). Both statements end on the same `}`, so lowering
closes the statement that starts later first
(`shaders/codegen/lir/semantic/materialize.slang`). Fixture:
`tests/fixtures/language/else_if.lani`, run on x86_64 and Wasm.

Decision: `if` is still a statement. There is no `if` expression, and `match`
remains the way to compute a value from alternatives.

## C callbacks

A non-generic free function named as a value, `compare_i32` or
`app::util::compare_i32` from another module of the program, is a `ptr`:
the address of a System V entry for that function. C code can call it, so `qsort(data, 8, 4, compare_i32)`,
`bsearch(key, table, 6, 4, compare_u32)` and
`pthread_create(thread, attr, worker, arg)` work with the ordinary Lanius
functions `fn compare_i32(left: ptr, right: ptr) -> i32` and
`fn worker(arg: ptr) -> ptr`.

- The entry takes arguments in rdi, rsi, rdx, rcx, r8 and r9, preserves rbx,
  rbp and r12 to r15, keeps the stack 16-byte aligned, and zero-extends
  `i32` and `u32` arguments, whose upper halves C leaves undefined.
- It loads R15 with the process vector, so a callback on a thread that a C
  library created (pthread) can use the runtime's argument and environment
  services. `crt_entry` maps that vector at the fixed address
  `0x100000000000` with `MAP_FIXED_NOREPLACE` and unmaps it when `main`
  returns, so every thread that runs a callback must finish before then.
  A Lanius library linked into a C program without a Lanius `main` has no
  vector; its callbacks must not use those services.
- Admitted signatures: at most six parameters, each `i32`, `u32`, `i64`,
  `u64`, `isize`, `usize` or `ptr`, and a result of one of those types or
  none. Other signatures (floats, aggregates, more parameters) and the Wasm
  target are `LNC0017`. A generic function named as a value is still an
  unresolved identifier (`LNC0005`), and a method path such as `S::get` is
  `LNC0006`.
- The name is already a `ptr`: `let p: i32 = f;` is `LNC0006` and
  `f as ptr` is `LNC0072`. Lanius cannot call through a `ptr`; the address
  is for C.

Decision: no new syntax. The request suggested `extern "C" fn name(...) {
... }`, but every Lanius function already has a C-compatible register
convention for these scalar types, so a second kind of definition would
only duplicate it. Naming the function is the one new rule, and it needs no
grammar change, so the front end the verified compiler reads, its grammar
tables and their certificates stay as they are. The entry is a 58-byte
trampoline emitted at each place the name appears and jumped over; it needs
no symbol, relocation or writable data, and it calls the function's
ordinary body. Taking the address counts as two calls, so the function is
never inlined away.

Implementation: modules/10i types a resolved fn path as `ptr`; semantic
project.slang lowers the name to a CALL row with no arguments; x86 scatter
(`c_entry_call`) recognizes a CALL row from a name whose callee is a fn item
and checks the signature; analysis_index counts it twice; instruction_plan
`plan_c_entry` emits the trampoline and emit sets its zero-extension mask;
Wasm scatter rejects it. Fixtures: `tests/fixtures/native_c_callback/`
(`qsort.lani`, `bsearch.lani`, `pthread.lani`), run by
`tests/native_c_callback_execution.rs`.
