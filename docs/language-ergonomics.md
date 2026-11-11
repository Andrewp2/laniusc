# Language ergonomics: item imports, `?`, local inference, block arms, match exhaustiveness, path calls, C callbacks, `else if`, trap messages, closures

Ten features shorten ordinary Lanius code without adding hidden behavior.
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

## Match exhaustiveness

A `match` must cover every value of its scrutinee. A match that leaves a
value without an arm is rejected with `LNC0077`. Before this check such a
match compiled, and the program ended with SIGILL when the value arrived.

```lanius
enum Color { Red, Green, Blue }

fn rank(color: Color) -> i32 {
    return match (color) {
        Color::Red -> 1,
        Color::Green -> 2,
    };
}
```

```text
error[LNC0077]: match is not exhaustive
  |     return match (color) {
  |            ^^^^^ at least one value has no arm
```

The rules:

- A pattern is a name or `_`, a variant, or an integer literal. A name and
  `_` match every value. `true` and `false` are the two variants of bool.
- A variant pattern is simple when each payload pattern is a name or `_`. It
  is single when exactly one payload pattern is a variant or a literal.
- A set of patterns at one position is covered when one of them is `_`, or
  when every variant of the enum has a simple pattern, or has single
  patterns whose payload patterns in that one column are covered in turn.
- The match is exhaustive when its arm patterns are covered. This holds for
  local enums and for imported ones such as `Option` and `Result`.
- An integer literal covers nothing. A match on literals needs a `_` arm.
- An arm pattern that is none of an enum variant, a literal or `_` is
  rejected: "this is not an enum variant". Before, a constant or a
  misspelled variant in that position failed in code generation (`LNC0057`).

So these arms are exhaustive, and removing any one of them is an error:

```lanius
fn total(value: Result<Option<Option<i32>>, i32>) -> i32 {
    return match (value) {
        Ok(Some(Some(inner))) -> inner,
        Ok(Some(None)) -> 1,
        Ok(None) -> 2,
        Err(code) -> code,
    };
}
```

Decision: the check follows one payload column of a variant. The arms
`Pair(Bit::Zero, Bit::Zero)`, `Pair(Bit::Zero, Bit::One)` and
`Pair(Bit::One, _)` list every pair, but the first two split both payloads,
so they cover nothing and the match needs a `_` arm. For one variant only
the column of its first single arm counts. Patterns nested more than six
levels deep cover nothing. The rule never accepts a match that misses a
value. The general check compares whole pattern trees across arms; it can
replace this rule later without rejecting any program the rule accepts.

Implementation:
- `type_checker/modules/10o_validate_match_exhaustive` runs one thread for
  each pattern: an arm row or a payload row. A group is the set of patterns
  at one position below the same variants. A group fails at a leaf when a
  variant of its enum has no simple and no single member.
- A thread looks for that in its own group, for the variant after its own.
  The members of a group together visit every variant, so no thread loops
  over the variants of the enum.
- The thread then walks to the arm group. At each level the walk stops when
  another member covers the variant above the failing group. A walk that
  reaches the arm group reports the `match` token.
- The variants of a local enum are consecutive rows of the variant family in
  ordinal order, so the thread tests whether an ordinal exists without a
  count. For an imported enum, `dependencies/11_project_types` stores the
  variant count in word 3 of the resolved value metadata.
- Every report for one match carries the `match` token and the same detail,
  so the result does not depend on thread order.


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

## Trap messages

A trap ends the program. On x86_64 Linux the program first writes one line to
standard error that names the reason:

| Cause | Line on standard error | How the process ends |
| --- | --- | --- |
| Array or slice index outside the length | `lanius: index out of range` | exit status 101 |
| Shift amount negative or not less than the bit width | `lanius: shift amount out of range` | exit status 102 |
| Integer division or remainder by zero | `lanius: division by zero` | exit status 103 |
| Signed division of the minimum value by -1 | `lanius: division overflow` | exit status 104 |
| `assert(false)`, `core::panic::panic()`, `unreachable()` | `lanius: assertion failed` | signal SIGILL |

- Output written before the trap stays on standard output. The exit statuses
  and the signal are the ones these traps had before they wrote a message.
- The line does not name a source file or line number.
- The write is one `write(2)` system call to descriptor 2. A closed or full
  descriptor does not change how the process ends.
- Wasm modules trap without a message.

The stubs follow the print helpers in the runtime block
(`shaders/codegen/lir/x86/runtime_abi.slang`, `trap_bytes`). Their assembly
source is `shaders/codegen/lir/x86/runtime_traps.s`. Each guard jumps to its
stub, so a guard is no longer than before. Fixtures:
`tests/fixtures/language/trap_*.lani`.

## Closures

A closure is a callback written where it is used:

```lanius
let step: i32 = 3;
let mapped: Option<i32> = some.map(|x: i32| x + step);
let total: i32 = twice(|x: i32| { let y: i32 = x * x; return y + step; }, 2);
let made: i32 = make(|| -> i32 { return step * 2; });
```

- `|name: Type| body` takes one parameter and implements
  `core::function::Mapper<Type, R>`. `|| body` takes none and implements
  `core::function::Producer<R>`. The value is a borrowed callback, the form
  the library's `mapper: &M` parameters take.
- The body is an expression, or a block in braces that ends with `return`.
  An expression body ends at the first `,` or `;` outside its own brackets,
  or at the bracket that closes around the closure. An expression with a
  comma between explicit type arguments needs braces.
- `-> Type` before a block body gives the result type. Without it the place
  that receives the closure fixes the result type: a bound such as
  `Mapper<i32, i32>`, or the declared type of the `let` that takes the
  call's result.
- A closure captures by value. Each local or parameter of the enclosing
  function that the body names is copied when the closure is created. A
  later assignment to the local does not change the closure.
- A captured local needs a declared type, `let step: i32 = 3;` or a
  parameter. The closure's own parameter and the locals its body declares
  shadow outer names.

Rejected with `LNC0078` (invalid closure):

| Source | Message |
| --- | --- |
| `\|x\| x + 1` | a closure parameter needs a type |
| `\|x: i32, y: i32\| x + y` | a closure takes one parameter with a type, or none |
| `\|x: i32\| -> i32 x + 1` | a closure with a result type needs a body in braces |
| `\|x: i32\| x + offset` with `let offset = 3;` | a closure captures this local, which has no declared type |
| `\|x: i32\| x + self.step` | a closure cannot use `self` |
| `\|x: i32\| twice(\|y: i32\| y, x)` | a closure cannot contain another closure |

Other limits:

- A closure has no type a program can name, so it cannot be a field or a
  declared parameter type. A function takes one through a bound.
- A name bound by a `match` arm or a `for` loop is not captured. The body
  then reports an unresolved identifier (`LNC0005`) for a `match` binding,
  or `LNC0078` for a `for` variable. Copy the value to a `let` with a
  declared type first.
- A closure in a generic function cannot capture a value whose type names
  the function's type parameters. The generated struct does not have them,
  so the compiler reports an unknown type.
- On Wasm a closure that captures fails with `LNC0036`. The Wasm backend
  does not yet lower a borrowed struct whose field comes from a local. The
  same program without a closure fails the same way.

Decision: a closure is rewritten to ordinary Lanius before the frontend
reads the file. `|x: T| body` with captures `a` and `b` becomes the site
`__lanius_closure_N{a:a,b:b,}.borrow()` and, at the end of the file, a
struct with one field per capture, a `borrow` method and an impl of the
trait whose method starts with `let a: A = self.a;` and then holds the body
unchanged. `N` is the byte offset of the closure in its file. The site
evaluates each captured name where the closure stands, and the type checker
checks the generated struct, so the rewrite can produce a type error and
never a wrong value. Parameter and capture types are written out because a
generic impl body cannot call methods or read fields of a generic value;
that is why the parameter type is required.

Implementation: the rewrite runs on the GPU over the raw lexer tokens of
all files of one load (`shaders/closures/`). `mark` flags closure starts
and binder roles; `scan` computes bracket depth and closure counts by a
doubling prefix sum; `records` finds each closure's parameter, result type
and body; `captures` resolves each name in a body to the nearest typed
binder before the closure; `layout`, `files` and `pieces` compute the list
of output pieces, where each piece is a span of source bytes, a constant
string or a closure number; `emit` writes each output byte from the piece
that covers it. The host (`compiler/machine_elaboration/closures.rs`)
records the commands and sizes buffers from the counts the kernels publish:
four submissions when a file has a closure and one when none has. The piece
table becomes the segment map, so a diagnostic in a closure body points at
the source (`closure_body_error.lani`). Import discovery loads
`core::function` for every file that contains a `|`, because the rewrite
adds that import to a file with a closure. Fixtures:
`tests/fixtures/language/closure*.lani` and `closure_modules/`.

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
