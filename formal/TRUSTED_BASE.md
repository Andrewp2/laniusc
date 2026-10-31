# Trusted base of the verified compiler

Roadmap step 14. This is every assumption that the two top-level theorems rest
on but do not prove:

- `Lanius.Mini.compileSource_correct` (`Lanius/Mini/SourceCorrect.lean`). If
  `compileSource sp = some binary` and Core evaluates `f(args)` to `v`, then
  the code for `f`, entered by a near call in a suitable x86 state, returns
  slots that represent `v`.
- `Lanius.Mini.compileText_correct` (`Lanius/Mini/TextCorrect.lean`, V5).
  The same from source text: if `compileText files = some binary`, the
  files' texts have exactly one reading `sp` (`TextReading`, the inductive
  relation of section 4; unique by `textReading_unique`), and
  `compileSource_correct`'s conclusion holds of `sp` and `binary`.
  `compileText_behaviour` is its counterpart for runs that stop.
- `Lanius.Mini.process_exits` and `process_behaviour`
  (`Lanius/Mini/Process.lean`, V6), with `textProcess_exits` and
  `textProcess_behaviour` from source text. `elfFile binary entry stack heap`
  wraps a binary in a Linux executable. From any state Linux leaves for it
  (`Loaded`), when Core runs `entry()` to `v` within the heap, the process
  reaches `exit` (`Exits`) with the last of `v`'s slots in rdi, or the stack
  is too small and every stopped run is at a fault; and every run that stops
  other than at a fault is at that `exit`, or Core's call reaches an
  undefined trap. Section 8 lists what is trusted about Linux.
- `Lanius.Faithful.SelfCompiler.selfCompiler_outcome`
  (`Lanius/Faithful/SelfCompiler.lean`, V7). For `B` with
  `compileSource prog = some B` (the verified compiler built by itself),
  `B`'s code for the driver `w`, given the words of source files, faults,
  or returns `compileText`'s answer for them in x86 memory. Core's run of
  `w` never traps undefinedly (`driver_safe`, V7b). That the native
  self-built compiler's bytes are `compileSource prog` is computed by
  `lake exe runAll` (section 5, the Lean build), not by the kernel.
- `Lanius.Mini.compileProgram_correct` (`Lanius/Mini/Correct.lean`). The same
  for a mini IR program against the mini big-step semantics.
- `Lanius.Mini.compileProgram_stops` (`Lanius/Mini/StopsCorrect.lean`, V2c).
  If the mini program's `f(args)` is, for every `n`, still running after `n`
  ticks or stopped at a checked fault (`Program.Stops`), then every run of
  its code that stops, stops at a fault (`Faults`): it never returns.

The list was found by reading the theorem statements, the definitions they
mention, the extractor, and the x86 model. Each item gives what it is, where
it lives, how it is checked today, and what would shrink it. Last updated
2026-10-21, at the commit that adds this file.

## 1. Lean

- **What.** The Lean 4 kernel (toolchain `leanprover/lean4:v4.33.1`, pinned in
  `lean-toolchain`; the project has no package dependencies) and three
  axioms:

  ```text
  #print axioms Lanius.Mini.compileSource_correct
  'Lanius.Mini.compileSource_correct' depends on axioms: [propext, Classical.choice, Quot.sound]
  #print axioms Lanius.Mini.compileProgram_correct
  'Lanius.Mini.compileProgram_correct' depends on axioms: [propext, Classical.choice, Quot.sound]
  ```

  The step 14 theorems `compileProgram_deterministic` and
  `compileSource_deterministic` (`Lanius/Mini/Determinism.lean`, section 7)
  depend on the same three axioms.

  These are Lean's standard axioms. There is no `sorryAx`, and there is no
  `Lean.ofReduceBool`, so nothing relies on `native_decide`, `bv_decide` or
  compiled code. Elaboration and tactics (`omega`, `bv_omega`, `simp`,
  `decide`) are not trusted, because the kernel rechecks every term they
  produce.
- **Checked by.** `lake build LaniusMini`, and `#print axioms` as above, run
  from a file that imports `Lanius.Mini.SourceCorrect`, with
  `lake env lean`.
- **To shrink it.** Recheck the exported environment with an independent
  kernel, for example lean4lean (`leanchecker`, which ships with the
  toolchain, replays the same kernel).

## 2. The statement: definitions the reader must accept

A theorem only means what its definitions say. These definitions are part of
the statement, so a reader has to agree that each one says what is intended:

| definition | file | says |
|---|---|---|
| `SrcProgram.toCore` and the `toCore` of each construct | `Mini/Source.lean` | which Core program a source program *is*: each construct is the Core construct of the same name (`Null` is Core's literal `.pointer 0`), and functions are numbered by position. A literal (`EStruct`, `LetStruct`) means `SrcType.literal`: Core's array value `.array T vs` at an array type `[T; N]` (added 10-31, F6), and a struct value otherwise |
| `FieldsHold`, `SrcType.HoldsAt` | `Mini/Source.lean` | how a Core value sits in 64-bit slots: an `i32` is zero-extended, a `bool` is 1/0, a struct is its fields in order, an enum is a tag then its payload, a pointer is its address, an array `[T; N]` is its N elements in order, as a struct of N fields of type T (`HoldsAt.array`, added 10-31) |
| `Returned`, `HeapAt`, `StackAt`, `Contract`, `Scratch`, `InHeap` | `Mini/Simulation.lean` | the calling convention and what "returns" means (below) |
| `Below`, `Binary.stackNeed`, `Binary.guard` | `Mini/Frame.lean`, `Mini/Bytes.lean` | the stack window |
| `Det`, `Live`, `Faults`, `Fault` | `Mini/StepDet.lean`, `X86/Machine/Scalar.lean` | every run agrees but for flags and does not stop early; a run that stops, stops at an architectural fault (`ud2`, `#DE`) |
| `undefinedTrap`, `Failing` | `Mini/Fails.lean` | for `compileSource_stops`: a Core run fails at a fuel when it runs out of fuel, stops at a trap that is not undefined, or completes with the heap past the mini heap's limit; the undefined traps are the raw memory errors and `typeMismatch` |
| `Stops`, `Program.Stops` | `Mini/Stops.lean`, `Mini/StopsCorrect.lean` | for `compileProgram_stops`: a mini run that, within `n` ticks (loop iterations and calls), has not finished or has stopped at an allocation past the limit from a cursor within it, or at a division by zero or of the least value by -1 |
| `CodeAt`, `Steps`, `Step` | `X86/Machine/State.lean`, `X86/Machine/Scalar.lean` | the image is loaded, and the machine runs (see section 6) |
| `linkProgram`, `Stmt.rename`, `Binary.executable`, `Executable.stackNeed` | `Mini/Compiler.lean` (extracted), `Mini/Link.lean` | for the step 9 theorems `link_eq` and `linked_correct`: which mini program a list of modules *is* (their functions in link order, each callee renamed to its program index, imports checked for owner, function and arity), and what of a binary a linked executable keeps |

`compileSource` and `compileProgram` themselves are not trusted. The theorem
is about whatever they compute. That includes the optimizer `compileSource`
runs (roadmap step 13): it is not proved, and the theorem holds because its
output is kept only when the proved validator accepts it. Nor are
`compileModule` and `linkObjects`: `link_eq` says they give what
`compileProgram` gives for `linkProgram`'s program.

## 3. Core semantics as the meaning of Lanius

- **What.** `compileSource_correct` states correctness against Core's
  fuel-indexed evaluator `Lanius.Semantics.evalExpr` (`Lanius/Semantics.lean`,
  1,896 lines) and Core's heap (`Lanius/Memory.lean`; the allocator is
  unbounded and `nextAddress` starts at 1). We assume that this evaluator is
  what Lanius programs mean. No other formal semantics exists to compare it
  with, and laniusc, the GPU compiler, is not proved against it.
- **Coverage.** The theorem covers only Core runs that finish
  (`= .done v final`) on programs that `compileSource` accepts. It does not
  cover divergence, Core traps, or programs outside the subset (`compileSource`
  returns `none` for those). Core's allocator never fails. On x86 the heap
  limit is enforced (the bump allocator executes `ud2` past it), and the
  theorem assumes that Core's run fits:
  `final.heap.nextAddress ≤ heap.limit`.
- **Raw views (changed 10-22).** `i32_slice_from_raw_parts` and the raw
  slices of structs and enums (`Heap.checkRange`) check that the range is
  nonempty, aligned, and inside one live block whose alignment is enough,
  and leave the heap as it was. Before 10-22 they asked for an exact whole
  block and marked it borrowed (`owned := false`), so a later `dealloc` of
  the block trapped. Now a view may cover any aligned range inside a block
  (a prefix, a middle), and the block stays owned: `dealloc` after a view
  succeeds, and a read through the view after that traps
  (`invalidPointer`), so use-after-free still traps. Arrays and strings
  that the language itself lends (`mapBorrowed`) still make borrowed blocks.
  This is the meaning `Vec` needs: its buffer is one block and its
  elements are a view of a prefix of it.
- **Shift amounts (changed 10-30).** A shift of a signed or unsigned
  integer may take an amount of another such type (`x << n` with `x: i64`,
  `n: u32`), as laniusc allows: typing `BinaryOpHasType.shiftLeftBy` and
  `shiftRightBy` (`ShiftTy` on both sides, the result the left operand's
  type), evaluation `Semantics.evalShiftBy`, which checks the amount's
  number against the left operand's width, as a shift by its own type does
  (`u8` by a `u32` amount of 256 traps). Before 10-30 Core typed only shifts
  by the left operand's own type and gave a mixed one `typeMismatch`;
  shifts of one type evaluate as before.
- **Floats (changed 10-30, F9).** Core's `f32` and `f64` values are their
  IEEE 754 binary32 and binary64 bit patterns (`.f32Bits`, `.f64Bits`), and
  every float operation is defined on exact integers in `Lanius/IEEE.lean`
  (234 lines; no Lean `Float` anywhere, so the kernel can evaluate and
  reason about it). Before 10-30 Core used Lean's `Float32`/`Float`, which
  the kernel cannot see into. The specification:
  - A finite pattern's value is `(-1)^s * significand * 2^unitExp`: a normal
    one has the hidden bit, a subnormal one the unit `2^(1 - bias - f)`.
  - `roundRatio` rounds an exact rational `num / den * 2^exp` to nearest,
    ties to even, with gradual underflow (no flush to zero) and overflow to
    infinity. `+ - * /` compute the exact result and round it once
    (`add`, `sub`, `mul`, `div`); an exact zero sum is `+0` unless both
    operands are `-0`; a zero product or quotient has the sign of the
    signs' xor.
  - NaN results follow x86 SSE: an operation with a NaN operand returns the
    first NaN operand with its quiet bit set (sign and payload kept); an
    invalid operation on non-NaNs (`inf - inf`, `0 * inf`, `0 / 0`,
    `inf / inf`) returns the default NaN (sign set, exponent all ones, only
    the quiet bit), and `x / 0` is a signed infinity.
  - `==`, `<`, `<=` are false when either operand is a NaN, and `-0 == +0`;
    `!=` is the negation of `==`, `>` and `>=` swap the operands.
  - Negation flips the sign bit, NaNs included (`neg`), as `xorps` does.
  - Integer to float (`ofInt`) rounds the exact integer; `f32 -> f64` is
    exact, `f64 -> f32` rounds; a NaN converts with its sign and the top bits
    of its payload, quieted (`convert`), as `cvtss2sd`/`cvtsd2ss` do.
  - Float to integer (`truncSat`, added: Core had no such cast) truncates
    toward zero and saturates to the target's range, NaN to 0, as Rust's
    and laniusc's `as` do.
  - A decimal literal `m * 10^e` is rounded once to the nearest pattern
    (`ofDecimal`, used by elaboration); past `10^400` it is infinity and
    below `10^-400` zero, only to avoid huge powers.
  This specification is also the meaning of the SSE instructions in the
  x86 model (section 6). `formal/tools/float_test.py` (gate step `float`)
  runs it, compiled (`lake exe floatTest`), against this machine's CPU:
  `addss`...`divsd`, `cmpss`/`cmpsd` with predicates 0, 1, 2, `xorps` of
  the sign bit, `cvtss2sd`, `cvtsd2ss`, `cvtsi2ss`/`cvtsi2sd` from 32 and 64
  bits, libc's `strtof`/`strtod` for decimals and Python's exact integers
  for truncation; on edge patterns (zeros, subnormals, the largest finite
  values, infinities, quiet and signalling NaNs with payloads), exact ties,
  near operands and random bits: 79,214 cases at 2,000 per operation, 0
  differ (AMD Ryzen 9 5900HX). The test assumes Linux's default MXCSR
  (round to nearest, exceptions masked, no FTZ/DAZ), which no compiled code
  changes.
- **`slice_stride` (added 10-22).** `Intrinsic.sliceStride` gives a raw
  view's signed byte stride as an `isize` (`rawSliceStride?`): 4 for `i32`
  views, and `-8 × words` for views of structs and enums. On these views
  laniusc gives the same values; the oracle difftest checks them. Core gives
  a view of a language array no stride (it traps), while laniusc gives that
  array's own layout. Programs that ask for one are outside the theorem.
- **Native layout (changed 10-22).** Core reads and writes values in memory
  with laniusc's layout (`docs/wasm-memory-layout.md`). A value's address is
  its word 0, its highest word; word k is 8k bytes below it. A struct's field
  j has its word 0 at 8·W_j bytes below the struct's, W_j being the words of
  the fields before it. An enum's tag is word 0, and its payload starts one
  word below. Element i of a raw view of a w-word type is 8wi bytes below
  element 0. `str` is 2 words (data, then length) and a slice is 3 (data,
  length, stride). Each scalar is one word, so `u8`, `u16`, `u32`, `i8`,
  `i16`, `i64`, `u64` and `isize` now have a native layout too. A raw field
  place `s[i].f` is the element's address less the field's offset, and it
  traps (`rawMemoryBounds`) when that would go below 0. Before 10-22 fields,
  payloads and view elements went up from the value's lowest word, and
  slices were 2 words, so Core and laniusc disagreed on every aggregate
  stored in memory. One difference remains. Core writes `i32`, `bool`,
  `i8`, `i16`, `u8`, `u16`, `u32` and enum tags as 4 bytes and the 64-bit
  kinds as 8, while laniusc writes every scalar as a whole 8-byte word,
  zero-extended. The 4-byte writes are needed because the same writer
  stores packed `i32` view elements, which are 4 bytes apart. Both read the
  32-bit kinds with 4-byte loads. So the two differ only in the upper half
  of such a word, which only an aliasing 8-byte read sees. Core traps when a
  4-byte `u8`, `u16`, `i8` or `i16` read is out of the type's range; laniusc
  does not mask.
- **Checked by.** Reading, and Core's own Lean tests (`Lanius/Semantics/*Tests.lean`).
  Core is not tested against laniusc-built binaries.
- **To shrink it.** Run a differential test of `#eval evalExpr` against
  laniusc's output on the subset; this is roadmap step 12 run the other way.
  Extend the theorem to divergence and traps.

## 4. The front end

`compileSource_correct` takes a `SrcProgram` value, not source text;
`compileText_correct` (V5) takes the files' text and composes the two. Roadmap
step 8 adds a front end that gives source text a `SrcProgram`, by translation
validation of laniusc's parser:

```text
sourceProgram source prods parents : Option SrcProgram    (Mini/FrontLex.lean)
sourceProgramFiles files : Option SrcProgram              (several files, the program's own first)
```

`source` is the file's bytes. `prods` and `parents` are laniusc's parse tree:
the production ids in preorder (its `node_kind` array) and each node's parent.
The validator, `validate_tree` in `Mini/Frontend.lean` (extracted from
`formal/lani/mini/frontend.lani`), follows the production list. It matches
each terminal with the next token and checks each node's production and
parent. Then `build` reads the program off the tree. Proved
(`Mini/FrontSpec.lean`, axioms `propext` and `Quot.sound`):

- `validate_sound`: an accepted tree is a parse tree of the grammar for
  `file` whose leaves read exactly the tokens (`Reads`: token by token,
  except that a `>>` may be read as its two halves, two `>`) and whose
  preorder is exactly `prods`. The exception is how laniusc's parser reads
  the `>>` that closes two type argument lists (`H<H<i32>>`); a `>` terminal
  takes the `>>`'s first byte and the next terminal its second.
- `validate_derives`: the leaves' token kinds are a sentence of the grammar
  (`Derives`, the usual derivation relation).
- `sourceProgram_sound`: the program is `build` of such a tree, for the tokens
  the Lean lexer gives `source`.
- `sourceProgramFiles_sound`: the program is `buildFiles` of one such tree
  per file.

Not trusted: laniusc's lexer and parser. A wrong tree is rejected, or it is
still a parse tree of the same tokens. Trusted:

- **The lexer.** `Lanius.Compiler.Lexer.lexCanonical`
  (`Lanius/Compiler/LexerCanonical.lean`) is the meaning of Lanius's lexical
  syntax. The self program's own lexer, `lex_source` in `frontend.lani`, is
  proved equal to it (`lexSource_eq`, `Mini/LexCorrect.lean`), so it is not
  trusted. `lexTokens` adds one keyword that `keywordRules` lacks: `as` is
  token code 195, as in laniusc. Token kinds are laniusc's codes
  (`TokenKind.gpuCode`). The difftest below compares these tokens with
  laniusc's lexer (kind, start and length). The keywords `requires` and
  `ensures` and the contextual `distinct` (2026-10-27) have no rule here, so
  a file that uses them lexes them as identifiers and its tree is rejected.
  `read_fn` also rejects a function with a contract list, because the front
  end does not model a `requires` trap.
- **The grammar.** The table `grammar` in `frontend.lani` is
  `grammar/lanius.bnf` as laniusc built its parse tables
  (`tables/parse_tables.meta.json`). Production `k` is entry `k`, a terminal
  is the token code of its lexer kind, and parser retags map back through
  `canonical_lexer_kind` (`crates/laniusc-compiler/src/lexer/tables/tokens.rs`).
  One mapping is added: `MatchArrow` becomes `Arrow`, because the lexer emits
  `->` in match arms as `Arrow`. `formal/tools/grammar_table.py` writes the
  table mechanically, and `--check` confirms that it is current. The grammar
  is trusted to say what Lanius's concrete syntax is, including precedence
  and associativity, which it encodes in its levels.
- **One reading (V4, proved).** The grammar is not unambiguous on the
  subset, as this file used to claim: `a < b > (c)` is both a comparison chain
  and a call of a generic path `a<b>`, and `f(a < b, c > (d))` likewise.
  `picks` (`frontend.lani`, checked by the validator at every node) is part of
  the syntax's definition: a path segment `x<...>` in an expression is read
  as type arguments exactly when `generic_path_at` holds of the tokens from
  `x` on (the matching `>`, counted outside brackets with `>>` closing two,
  comes before a bracket closes or a `;`, with no `||`, `==`, `!=`, `<=` or
  `>=` before it, and is followed by `(`, `::` or `{`), which is laniusc's
  rule without its 64-token limit; a statement that begins with `{` is a
  block statement (production 84), never an expression statement (85), as
  in Rust, since `{ a } - b;` has both trees; and a method's type arguments
  (production 298), which the subset does not use and which are ambiguous
  too (`x.f < a > (b)`), are not allowed.
  `grammar_unique` (`Mini/ParseUnique.lean`, standard axioms) proves that at
  most one parse tree for `file` is `Picked` for given tokens, from a
  certificate of first and follow sets (two token kinds deep, `>>` read
  either way) that the kernel checks (`grammarCert_ok`,
  `Mini/GrammarCert.lean`, written by `formal/tools/grammar_cert.py`), and
  `Cert.parse_unique` (`Mini/Unique.lean`). So `validate_unique`: the tree the
  validator accepts is the only one, and `sourceProgram_determined` and
  `sourceProgramFiles_determined`: the front end's program depends on the
  source text alone, not on the tree laniusc gives. What stays trusted is
  that `picks` says what the syntax means where it decides.
- **The reading.** `Reading roots sp` (`Mini/Reading/`, V8) is the meaning of
  the subset's concrete syntax, as `toCore` is the meaning of `SrcProgram`
  (section 2): an inductive relation on the files' parse trees, with lookups
  and choices said declaratively, and small total helpers of the builder
  (expected-type and literal-typing helpers such as `intAt`, `operandWant`,
  `knownExpr`, and the wide-literal check `wideLeftFuncs`) as its
  vocabulary. `buildFiles_sound` (standard axioms) proves that what `build`
  returns is a reading, so `build`'s code is no longer the specification.
  The builder's choices are ones the relation states exactly
  (SEMANTIC_DECISIONS.md, "The reading is one reading"), and the relation
  is deterministic (`reading_unique`, F1, `Mini/Reading/Det/`), so a text
  has at most one reading and the theorems are about it alone. The reading
  makes these choices:
  - each file is a module, named by its `module` item (the empty path
    without one); `m::x` names `x` of the module `m`, a bare `x` names `x`
    of the current module; `import m;` only adds m's variants to those a
    bare variant name may mean, and traits, type aliases with a `where`
    clause and extern functions are skipped, except that an `extern
    "lanius_std" fn` named `write_byte`, `write_stdout` or `write_stderr`
    (`hostExtern`) is a function whose instance returns the call of that
    host service on its parameters, `ECall(2^32 + k, params)` (`ReadExtern`;
    Core's meaning of that id is the host function, section 2);
  - `type A<P..> = T;` is an alias: a type path that names no type
    parameter, primitive or declared type names the alias of that module,
    and means T read in the alias's module with its parameters standing for
    the arguments (a cycle runs out of fuel and rejects); a cast may name an
    alias of a scalar type;
  - generic declarations are monomorphized (`mono`): an instance is a
    declaration with its type arguments, and a function or type id is a
    position in the instance tables. The first file's functions without type
    parameters come first, in order; every other function instance follows
    in the order it is first called. Types: the first file's non-generic
    types in order, then each instance as the functions' types (parameters,
    result, then the body's lets) first need it. A program without generics
    keeps the numbering of the next two lines;
  - a function is its position among the functions;
  - a struct or enum is its position among the type declarations;
  - a call's type arguments are written, or inferred by matching the
    callee's result type with the type its value is stored at, then its
    parameter types with the argument types in order, each argument read at
    its parameter's type once all are bound; an integer literal argument
    binds nothing unless a parameter is left unbound, when it counts as
    `i32`; a conflict or an unbound parameter rejects;
  - `x.m(args)` (`x` any value) and `T::m(args)` (`T` a type parameter, or
    a primitive type as in `i32::hash(v)`) call
    the method `m` of the one `impl` whose type matches the receiver's type,
    with `self` (by value) the receiver;
  - a `match` has one arm per variant of its scrutinee's enum, in any order,
    and its arms are listed in variant order (only one runs, so their order
    has no effect);
  - `x.f` is `Field` when `x` is a local, and otherwise the call of the
    projection `fn(v: T) -> F { return v.f; }` on `x`, an instance numbered
    like any other;
  - bounds and `where` clauses on functions are not checked. A wrong
    instance is still a well-formed `SrcProgram`, and its meaning is what
    `toCore` gives it, so this choice affects which programs are read, not
    what a read program means; an `impl` or type with a `where` clause is
    rejected;
  - a type parameter that no field or payload uses (a phantom) still makes
    distinct instances, but they lower to the same field types;
  - a constant is replaced by its value, which must be a literal of its
    declared type: `Int` for `i32`, `Unsigned` (range-checked) for the
    unsigned types, `Cast(Isize, Int(n))` for `isize`, `Boolean` for `bool`;
    a value whose tokens are `n` or `-` `n` with n of 2^31 or more is the
    type's literal of that value (`Int` of -2^31 for `i32`, `Unsigned` up to
    the type's largest value, the cast of the `u64` literal of its bits for
    `isize`);
  - a char literal (`CharLiteral`, added 10-30) is the code of the one
    Unicode scalar value (`ScalarValue`: below 0x110000, not a surrogate)
    whose UTF-8 encoding (`utf8Encode`) its text holds between the quotes,
    other than the quote, backslash and newline, or of one of the escapes
    `\n \r \t \0 \' \" \\` (`Escape`). laniusc's `parse_char_token` decodes
    these the same way; it also takes texts this reading rejects (`'ab'`,
    `\x` for other `x`, a malformed encoding as code 0). A constant of type
    `char` is its literal. `char` is the primitive type `SrcType.char`,
    held as its code (`UInt32`), which Core's `Value.character` is;
  - `f32` and `f64` (added 10-31, F9) are `SrcType.float .f32/.f64`, held
    as their IEEE bit patterns as Core's `.f32Bits`/`.f64Bits` are. A float
    literal (`floatParts`, `Reading/Exprs.lean`) is decimal digits with an
    optional `.` and fraction and an optional `e`/`E` exponent with a sign,
    read as the exact `m * 10^e`; underscores are rejected, and so is an
    exponent of more than 99999 (only so that the powers stay small). Its
    value is `ofDecimal` of `m` and `e` at the expected type when that is a
    float type, and at `f32` (Core's `literalDefaultType`) otherwise.
    `flDecimal_eq` (`Reading/FloatBits.lean`) proves that the front end's
    bignum rounding equals `Lanius.IEEE.Format.ofDecimal`, so the rounding
    is not trusted; only `ofDecimal` itself is (section 3). A constant of a
    float type is its literal, or the negation of its literal;
  - `[T; N]` (added 10-31, F6) is `SrcType.array T N`, Core's array type,
    when N is written as a decimal integer literal (`ArrayLen`; a constant
    name as the length is not read). An array literal is read only where an
    array type is expected (a `let`'s type, a parameter, a field):
    `[a, b, ..]` must have exactly N elements, each read at T, and `[x; n]`
    needs a pure x and n written as the decimal N; it is read as N copies
    of x (`EffR.array`, `EffR.arrayRepeat`). Both are the struct literal
    node `EStruct`/`LetStruct` at the array type, whose meaning is Core's
    array value (section 2). Copies of a pure x have the value Core's
    `[x; n]` gives, which evaluates x once; `a[i]` of an array local is
    read as `a[i]` of a slice local is (`EffTy.indexArray`);
  - a local is the byte offset of its binding (a parameter, `let` or match
    binder) from the start of its function's name (since 10-25, so that an
    edit to one function renumbers the locals of no other);
  - a use names the innermost binding with the same spelling, and locals may
    not be spelled like a type, type alias, variant or constant of their
    module (a function is only named by a call, so a local may share its
    spelling);
  - `let` scopes over the rest of its block;
  - `if` without `else` has an empty else;
  - binary operators fold to the left;
  - an integer literal below 2^31 is `Int`, and `-` before it is `negate`;
    one from 2^31 to 2^64 - 1 takes the type its context expects (decided by
    `lit_funcs`, below): `Unsigned(u, n)` when n fits u, for `isize` below
    2^63 the cast of the `u64` literal n, `-2147483648` at `i32` (or with no
    expectation) `Int` of -2^31, and `-n` at `isize` (n at most 2^63) the
    cast of the `u64` literal of its two's complement bits; any other
    rejects the program;
  - a bare literal operand of a shift (added 10-30) takes the shifted
    value's type, or else the shift's expected type, and a bare amount the
    value's (`amountWant`), as a shift's type is its left operand's;
  - `&self` (added 10-30) is read as `self`: the method takes the impl's
    type by value, as a shared reference to a value no one can change while
    it lives means the value (`PatternOf.selfRef`, `paramToken`);
  - `S::m(args)` for a struct S of the current module (added 10-30) is read
    as `T::m` is for a type parameter bound to S: the one method spelled m
    of an impl whose type matches S (`TypeOwner`, `OwnerTy`); an enum's
    path still names its variants;
  - `0` where a `ptr` is expected (a `let`, a parameter, an operand beside a
    `ptr`, a `ptr` constant) is `Null`, Core's null pointer;
  - a match arm whose value calls a `-> !` function g, in a match of value
    type t, calls g's instance at t: a function with g's parameters, result
    t and body `g(params); return self(params);`. Core traps in g (each
    `-> !` function in the stdlib is `assert(false)`), so the return, which
    only gives every path a value of type t, is not reached; if g returned,
    the instance would recurse until Core's fuel ran out, and the theorem
    covers only runs that return;
  - the path `alloc::allocator::alloc(size, align)`, in a `let` of type
    `ptr`, is Core's `alloc`, and the statement
    `alloc::allocator::dealloc(p, size, align);` is Core's `dealloc`; the
    alignment must be a literal `2^k` (`8` or `(8 as usize)`), read as the
    shift `k`. `slice_from_raw_parts(p, n)`, in a `let` of type `[T]`, is
    Core's raw view of `T`. These spellings are fixed: build does not look
    at the extern declarations in `alloc::allocator`, and these paths,
    `slice_stride` and `assert` are never read as a function or variant
    (`builtinPaths`);
  - `x op= e` is `x = x op e`, and `x.f op= e` is `x.f = x.f op e`, for
    `op` one of `+ - * & | ^`. Core has the compound form itself
    (`assign .add` and so on, `evalAssignValue`), which evaluates `e` before
    it reads `x`; for the subset's expressions, which neither trap nor have
    effects, the two orders give the same value and state;
  - an expression that calls a function, indexes a slice, divides (`/`,
    `%`), or is a struct literal, variant or `match` is a `SrcEff`, and its
    statement the effectful form (`LetEval`, `SetEval`, `SetFieldEval`,
    `IfEval`, `WhileEval`, `ReturnEval`, `SetIndexEval`, `Discard` for
    `f(x);`).
    Operators, casts and negations of pure operands are `EPure`, and a
    statement with a form of its own keeps it (`LetCall`, `SetCall`,
    `LetStruct`, `LetEnum`, `LetMatch` on a local, `LetIndex`, when their
    parts are pure). `x op= e` with `e` effectful, and `x /= e`, `x %= e`,
    are `SetEval(x, x op e)`, and `x.f op= e` is `SetFieldEval(x, f, x.f op
    e)`: `x` is read before `e` is evaluated, which is Core's order too
    since reading a local has no effect. A struct
    literal's or variant's type arguments come from the type its value is
    stored at when that is known (a `let`, the assigned local, the result
    type for `return`, a parameter of a callee whose type arguments are
    known), else from its fields' or payload's types; a match's result type
    is the stored-at type or its first arm's.

  - a function without `-> T`, or with `-> !`, returns `Unit`; `return;`
    is `ReturnUnit`; `assert(c);` (that spelling, one argument) is
    `Assert(c)`, Core's assert intrinsic. So `core::panic::panic()`, whose
    body in `stdlib/core/panic.lani` is `assert(false);`, traps.

  - `isize` is `Isize`. An integer literal whose expected type is `isize`
    is `Cast(Isize, Int(n))`, and one whose expected type is unsigned is
    `Unsigned(u, n)`, decided after monomorphization by `lit_funcs` from the
    types of locals, fields, parameters, callees and results; an operator's
    operands expect the type of whichever operand has one.

  - `slice_stride(x)` of a slice local x is `EStride(x)`;
  - `return slice_from_raw_parts(p, n);` in a function whose result is a
    slice is a slice local (named by the offset of `slice_from_raw_parts`)
    and its return;
  - a bare variant name is the one variant of that spelling among the
    current module's enums, else among its imported modules' enums;
    `E::V` and `m::E::V` name enum E's variant V, `m::V` module m's one V.

  It rejects anything outside the subset (`build` returns nothing, and the
  theorems say nothing). The difftest checks `build` against the
  generator's programs. Not yet proved: that a text has at most one reading
  (determinism of the relation) and that `build` finds one whenever there
  is one (fuel adequacy).
- **Extraction.** `Frontend.lean` is extracted, so section 5 applies to it.
  `extract.py`'s external sections (`// extract: external begin MODULE from
  PATH`) copy the source types and list operations from `compiler.lani`. The
  extractor checks that each copy has the same fields, constructors or
  signature as the original and emits `import MODULE` instead, so
  `Frontend.lean` uses `Compiler.lean`'s own `SrcProgram`.
- **Core**, as in section 3.

What is still outside: the type premise `FieldsHold (paramTypes func.params)
args ...` on the arguments, `=>` match arms, and block or `if` arms.

Checked by: `frontend_difftest.py` (MINI_COMPILER.md, step 8), which runs
laniusc's parser on generated programs and requires `sourceProgram` to give
the program the text was generated from; with `--generic`, on the same
programs abstracted into generic declarations over two modules, numbered as
`mono` numbers them; and with `--cases`, on hand-written generic programs
against hand-monomorphized copies.

## 5. Extraction, and how the compiler is run

The theorem is about the Lean definitions in `Lanius/Mini/Compiler.lean`. A
compiler that someone actually runs is one of these two:

1. **The Lanius build.** laniusc compiles `formal/lani/mini/compiler.lani`.
   Two things are trusted here:
   - **The extractor.** Since 10-30 (roadmap F2) it is the extractor in
     Lanius, `formal/lani/mini/extract.lani`, run by `lake exe extract`
     (`Lanius/Tools/Extract.lean`) on laniusc's parse tree of the source once
     the front end's validator accepts the tree, so it reads the source as
     the front end does; `formal/tools/lani_extract.py` runs it. It writes
     what `formal/tools/extract.py` wrote, byte for byte, and extract.py
     still extracts the two programs the front end does not read yet (the
     `&mut` pilot and the TLS machine). Either is
     trusted to give each construct it accepts the Lean meaning that Lanius
     gives it. It maps types one to one (`i32` and `u32` to `BitVec 32`,
     `u64` to `BitVec 64`, `usize` to `Nat`, `u8` to `UInt8`, `List<T>` to
     `List T`, `Box<T>` to `T`) and rejects anything outside the subset.
     `compiler.lani` and `frontend.lani` have no `&mut`; the translation of
     `&mut` parameters is used only by the pilot (see "`&mut` pilot" below).
   - **The prelude table.** `PRELUDE_FNS` and `PRELUDE_TYPES` in
     `extract.py`, and the same table in `extract.lani`, are trusted. `boxed` and `unbox` are the identity,
     `plus`/`times`/`minus` are `Nat` `+`/`*`/`-` on every run that returns
     (they panic instead of wrapping, and `minus` panics when `b > a`), and
     `max_of` is `max`. The prelude bodies are the only code that touches
     raw memory (`alloc`, `typed_slice_from_storage`).

   The list operations (`SPEC_FNS`) are *not* trusted. Each is extracted with
   a spec theorem that Lean checks. The trust also covers laniusc itself and
   the Lanius runtime (allocation, panics, stack depth) on this one program.

   Checked by:
   - `lani_extract.py --check` (the gate's `extract` step), which confirms
     that `Compiler.lean`, `Frontend.lean`, `Extract.lean` and
     `SqliteStatement.lean` are what the extractor in Lanius writes from
     laniusc's trees (it passes at this commit; CI does not run it);
   - `mini_difftest.py`, which compares images from `#eval compileProgram`
     and from the Lanius build byte for byte (3,006 programs, 757,000 bytes,
     no differences);
   - `fn_difftest.py`, which calls each extracted function in Lean and
     natively (8,200 calls on the back end and 3,140 on the front pass, no
     differences).

   To shrink it: a Lean semantics for the pure subset and a proof that
   extraction preserves it (roadmap steps 2 and 6), and self-hosting
   (step 11).

   Partly done (10-25): for the self program, the front end's reading of
   the compiler's own source (`mini::selfhost`, `Faithful/Gen/Self.lean`),
   each of the 1,547 functions reachable from `front_end_files`, `grammar`
   and `compile_source` has a kernel-checked certificate
   (`Faithful/Gen/SelfCert.lean`, standard axioms): a pure run of it that
   returns represents the extracted Lean function's result. What remains
   trusted there: the representation relations (`Gen/SelfRep.lean`, one
   per type, generated) and the pure semantics `pcall`, which `call_sim`
   relates to Core. The certificates are partial: a run that does not
   return is not covered. Joined (10-28, roadmap V1): `driver_faithful`
   (`Faithful/SelfDriver.lean`, standard axioms) is about a Core run of the
   self program's entry `w(input, words, output, room)`, the driver
   `self_host.py` builds. If the run completes on an input view reading
   `W`, it returns -1 when `compileWords (frontEndWords grammar W)` is
   `none`, and otherwise the result's length, with the output view reading
   the result. The driver's own functions (`oracle_read`, `oracle_put`,
   `oracle_write`, which make raw `i32` slices and write through them) are
   proved by hand at the Core level; `compile_words`, `front_end_words` and
   `grammar` are `call_sim` joined with their certificates. The
   representation relations and `pcall` are no longer in the statement, so
   they are no longer trusted. The statement's premises: the Core state
   invariant (`Inv`: no live `i32` array views, the heap's block bases
   unique), a heap cursor in range at the end, fewer than 2^31 input words
   and output room, and an output view whose `room * 4` bytes are readable.
   V6 (the startup wrapper) is to discharge the last.
   Since V5 (10-29) the input is source text: `front_end_words` reads each
   file's bytes (below 256), productions and parents and lexes the bytes
   with `lex_source`. `driver_files` (standard axioms) restates
   `driver_faithful` for the words of files (`filesWords`, in
   `Mini/TextWords.lean`): the result is the words of `compileText`'s
   binary, and `compileWords_some` shows that any input the driver accepts
   is the words of files. The lexer is in the certified functions now.
   The extraction's and the sources' bodies are hidden from other Lean
   modules (module system, for incremental checking); that changes only
   what the elaborator may unfold, not what the kernel checks, and a proof
   that needs a hidden body fails rather than passes. Each certificate is
   proved for any program and prims holding the function's source at some
   index, from its callees' certificates as hypotheses; the link
   (`Gen/SelfCert.lean`) instantiates them with the program's indices, the
   lookups (`prog.funcs[i]? = ...`, from `prog.funcs.drop i`, each from the
   previous one, over the chain of named tails `prog` is) and the prim tests
   (by `decide +kernel`, which adds no axiom). Nothing in a proof depends on
   another function's index, so the generator names everything by Lanius
   function name, not index (decided 10-25).
2. **The Lean build.** Run `#eval compileSource` or a compiled Lean
   executable. Extraction is then irrelevant, but Lean's code generator and
   runtime are trusted: GMP `Nat`, and the `@[extern]` and `implemented_by`
   implementations of `BitVec`, `UInt8` and `List`. The kernel does not see
   any of this code.

### `&mut` pilot

`formal/lani/mini/mut_pilot.lani` is extracted to `Lanius/Mini/MutPilot.lean`
with `&mut` parameters translated Aeneas style: a function takes each `&mut`
argument's value and returns `(result, updated values)`, an assignment
through a parameter rebinds it, and a call rebinds each `&mut` argument to
the value returned for it. Trusted, beyond the rest of this section:

- **Exclusivity.** The translation is right only if no other argument of a
  call reaches a `&mut` argument's value. laniusc rejects such a call
  (`shaders/type_checker/conditions/compact_exclusive.slang`, LNC0006), and
  extract.py rejects it again (a `&mut` argument must be a bare local, used by
  no other argument). Both compare roots at the call; neither follows aliases
  made by copying a record that holds a pointer, and the pilot has none.
- **By-reference passing.** laniusc passes a `&mut` argument by address, so
  the callee's writes reach the caller's local. `fn_difftest.py --source
  formal/lani/mini/mut_pilot.lani` checks it (gate step `mut-pilot`): each
  case prints the `&mut` locals after the call and compares them with the
  Lean tuple. Whether a by-value record argument is copied is not checked;
  `paid` gives the same result either way.

`Lanius/Mini/MutPilotCorrect.lean` proves facts about the extracted
definitions (a transfer conserves the two balances, a relay's result is the
total before it); nothing else depends on them.

## 6. The x86 model

- **What.** The x86 semantics that `Steps` uses:
  - `Lanius/X86/Machine/State.lean`: user-mode state, meaning sixteen 64-bit
    registers, `rip`, RFLAGS as one 64-bit word, and memory as a total function
    from 64-bit addresses to bytes;
  - `Machine/Scalar.lean`: `decode`, `execute`, `Step`, `Steps` and `Fault`;
  - `Machine/Flags.lean` and `Machine/Alu.lean`: flag results and condition
    codes;
  - `Machine/Memory.lean`: little-endian reads and writes;
  - `Control/Decode.lean`, `Register.lean` (REX) and `Word.lean`;
  - `Machine/Sse.lean` (added 10-30, F9): the low 64 bits of xmm0-xmm15
    (`State.xmm`) and the scalar SSE instructions the compiler emits.

  These were written by hand from the Intel SDM. Here is what the model does
  not contain, so each of the following is assumed:
  - **Faults.** Pages are mapped and have the right permissions, addresses are
    canonical, alignment checking is off (AC), and nothing raises #GP or #PF.
    Model addresses wrap modulo 2^64. Every address the code touches must be
    mapped, and then it is also canonical.
  - **Concurrency.** There are no interrupts or signals that change state, no
    other thread or process writes to the image, stack or heap, and memory
    ordering is irrelevant because the program is single-threaded.
  - **Code fetch.** One byte map serves both code and data. The proofs keep
    the image apart from every write, so self-modifying code never comes up.
  - **Not modeled at all.** Segment bases, CET shadow stacks (the compiled code
    pairs every `call` with a `ret`), and the CPU being in 64-bit mode with
    default operand sizes.
  - **SSE (F9).** The meaning of each SSE instruction is `Lanius.IEEE`'s
    operation on the bits (section 3); that the CPU computes it is trusted:
    - `movd xmm, r32` and `movq xmm, r64` (66 [REX.W] 0F 6E /r) put the
      zero-extended register in the low 64 bits; `movd r32, xmm` writes the
      low 32 bits zero-extended, `movq r64, xmm` the low 64 (66 [REX.W] 0F
      7E /r);
    - `addss subss mulss divss` (F3 0F 58/5C/59/5E /r) replace the
      destination's low 32 bits by binary32 `add sub mul div` of the two low
      32-bit fields (destination first) and keep bits 32-63; the `sd` forms
      (F2) replace all 64 low bits by the binary64 operation;
    - `cmpss`/`cmpsd` (F3/F2 0F C2 /r ib) with predicates 0 (EQ_OQ), 1
      (LT_OS) and 2 (LE_OS) write all ones in the low 32 (single) or 64
      (double) bits when `eq`, `lt` or `le` holds, else zeros (false on a
      NaN); only these three predicates decode;
    - `cvtsi2ss`/`cvtsi2sd` (F3/F2 [REX.W] 0F 2A /r) round the signed 32-
      or 64-bit register (`ofInt`); `cvtss2sd` (F3 0F 5A) widens and
      `cvtsd2ss` (F2 0F 5A) rounds (`convert`);
    - the high 64 bits of each xmm register are not modeled: no modeled
      instruction reads them into the low half, so they cannot change a
      result;
    - MXCSR is not modeled. It is assumed to hold Linux's default at exec,
      0x1F80 (round to nearest, every exception masked, no flush to zero,
      no denormals as zero), which no compiled code changes; its sticky
      exception flags are set by the CPU and never read.
- **Encoders are proved, not trusted.** The literal bytes in `Compiler.lean`
  are proved equal to the `X86/Machine` encoders (`Instr.encode_eq`,
  `prologue_eq`). Those encoders are proved to decode to the intended
  instruction for every tail of following bytes. `decode` and `execute` remain
  trusted: they are the model's claim about what the CPU does.
- **Checked by.** `formal/tools/x86_model_test.py` (step 14), described in
  section 9. On this CPU it found no disagreement on any form the compiler
  emits. It did find one decoder defect outside those forms (section 9), now fixed.
- **To shrink it.**
  - Run the same test on an Intel CPU.
  - Use a decoder oracle such as Intel XED for `decode`.
  - Compare against an independent formal ISA (Sail x86 or ACL2 X86isa) for
    the subset.
  - Make `decode` reject byte forms that the compiler does not emit.

## 7. One model run versus the CPU's run

- **What.** `compileSource_correct` and `compileProgram_correct` are
  existential: *some* model run `Steps n s s'` returns. `Step` is a relation,
  and it leaves these choices free:
  - AF after AND, OR, XOR and TEST;
  - every flag after IMUL, NEG and shifts;
  - the byte list it decodes, which may be any list loaded at `rip`.

  The proofs choose `AF = false` for the logical operations and keep the old
  flags after IMUL (`BinOp.final_step`). The CPU does neither. In the step 14
  test, the CPU's free flags differed from `execute`'s choice in about 3,200
  of 28,000 cases per seed. So the CPU's run is generally a *different* model
  run from the one the proof builds.
- **Proved (step 14).** Every model run of the same length ends the same way:

  ```text
  compileProgram_deterministic (Mini/Determinism.lean), same premises as
  compileProgram_correct:
    ∃ n s', Steps n s s' ∧ Returned window s s' value after ∧
      ∀ t, Steps n s t → DataEq s' t ∧ Returned window s t value after
  ```

  `DataEq` is equality of registers, rip and memory, so only RFLAGS may
  differ. `compileSource_deterministic` is the same for
  `compileSource_correct`. Both depend only on propext, Classical.choice and
  Quot.sound. The proof has three layers:
  - `decode_unique` (`Mini/DecodeUnique.lean`): `decode` reads only the bytes
    of the instruction it returns, so two byte lists loaded at the same `rip`
    decode to the same instruction and size. The byte-list choice is gone.
  - `Step` up to flags (`Mini/StepDet.lean`): two steps from states that are
    `DataEq` are `DataEq` again, unless the instruction reads flags (`jcc`,
    `setcc`). After CMP, TEST, ADD, SUB, AND, OR or XOR, the flag bits every
    condition code reads agree too. `Det n s s'` says that every `n`-step run
    from a state `DataEq` to `s` ends `DataEq` to `s'`.
  - Runs (`Mini/DetSteps.lean`, `Simulation.lean`, `Correct.lean`): every
    simulation lemma, `Contract` and the function contract now return `Det`
    with their run. Each flag reader comes right after its writer in the same
    abstract instruction (`cmp; setcc`, `test; jz`, `add; jb` and `cmp; jbe`
    in `bump`, `cmp; jbe` in the prologue), and every other emitted form
    reads no flags.
- **Still assumed.** That the CPU's run is one of the model's runs (section
  6). The theorem covers runs of exactly `n` steps, the length of the run to
  the return; after `n` steps the code is back in the caller, and no shorter
  run stops (`Live`). It says nothing about longer runs.

## 8. What the caller and the loader must provide

The premises of `compileProgram_correct` (also inside
`compileSource_correct`) are obligations on whatever sets up the x86 state.
The difftests run images from a ctypes stub, which is not trusted: it only
tests. Since V6 the verified compiler also writes the executable itself
(`elfFile`, `formal/lani/mini/compiler.lani`), and `process_exits` and
`process_behaviour` discharge every premise below from what Linux does, so
for a process the trusted part is only this:

- **`Loaded` (`Mini/Process.lean`).** For a file with one program header, a
  loadable segment from file offset 0, `execve` leaves the segment's
  `p_filesz` file bytes (header offset 96) at `p_vaddr` (80), zeros after
  them up to `p_memsz` (104), and rip at `e_entry` (24). It reads those
  fields from the file's own bytes (`fieldAt`), so a wrong header could not
  make the theorem easier. Registers, flags and the rest of memory are
  arbitrary. `elfFile`'s segment is at 2^32, readable, writable and
  executable, and its `p_memsz` covers the stack and the heap.
- **`Exits`.** A `syscall` with rax 60 ends the process with status rdi, of
  which the parent sees the low byte. The model's `Kernel` has no exit
  case, so the theorems' runs stop there (`Exits.stuck`).
- **The kernel's `write` (`Kernel` in `X86/Machine/Scalar.lean`, roadmap
  F8).** The x86 model's only other `syscall` step (`Step.syscalled`) is
  this trusted meaning of Linux's `write`: with rax 1, rdi 1 or 2, and rdx at
  most `maxTransfer` (2,147,479,552, Linux's `MAX_RW_COUNT`), the call
  - writes all rdx bytes read from memory at rsi, recorded as the event
    `.write rdi bytes` appended to the state's trace (`State.io`,
    `X86/Machine/Io.lean`), and changes no memory;
  - returns rdx in rax, leaves the next instruction's address in rcx and
    rip, an unknown value in r11 (where Linux saves RFLAGS), and every other
    register and RFLAGS as they were.

  So it is trusted that fds 1 and 2 are open for writing when the process
  starts, that a write to them never fails, blocks forever or is partial
  (a pipe whose reader has gone raises SIGPIPE, a full disk gives ENOSPC,
  and a write to a terminal or pipe may in principle return short; none of
  these is modeled), and that no signal handler runs. Any other rax, fd or
  count has no step, so a run that reaches it stops, and the theorems say
  nothing past it. `Loaded` starts the trace empty, and `process_exits`
  says the trace at the exit is the compiled mini program's write trace,
  whose bytes on fds 1 and 2 (`outputOf`) are what Core's world gained on
  its standard output and error. Core's `write_byte`, `write_stdout` and
  `write_stderr` are lowered to this `write` (SEMANTIC_DECISIONS.md,
  "Externs and the runtime"); their Core meaning is `World.call`, part of
  Core's semantics (section 3).
- **The kernel's `read` (`Kernel.read`, roadmap F8, 10-31).** The state's
  `io` also holds `input`, the bytes not yet read from standard input.
  With rax 0, rdi 0 and rdx at most `maxTransfer`, the call
  - delivers the first rdx bytes of `input`, or all of it when fewer are
    left, written to memory from rsi on (`writeBytes`; no other byte
    changes), and drops rdx bytes from `input`;
  - returns how many it delivered in rax (0 at the end of the input),
    with rcx, rip, r11 and the other registers and RFLAGS as for `write`.

  So it is trusted that fd 0 is open for reading when the process starts
  and that it delivers like a regular file: every read returns as many
  bytes as were asked for until the input ends, never fails, never blocks
  forever and is never interrupted. A terminal or a pipe can return fewer
  bytes than asked for before its end (a short read), which the model does
  not have; the compiled code would still be right on one (it reads again
  only after a full read), but the theorems do not cover it. Linux checks
  the buffer with `access_ok` before reading, and could return EFAULT for
  a range outside user space even when the file has no bytes left; the
  model assumes the call does not fault, and the verified compiler's
  buffers are inside its heap, whose end is below 2^62 (`HeapAt`). Core's
  `read_stdin` is lowered to this `read` (SEMANTIC_DECISIONS.md, "Host
  reads"). `Loaded` leaves `input` as the stream the process was given:
  `process_exits` takes it as a premise (`s.io.input = input`), with Core's
  world starting from the same `standardInput` (`startState input`).
  No other system call is modeled (SEMANTIC_DECISIONS.md, "Externs and the
  runtime").
- The startup code sets rsp, r12 to r15 and calls `entry` (the driver's
  convention is function 0, `main`), and `mov rdi, rax; mov eax, 60; syscall`
  follows the call. Its 65 bytes are proved, not trusted. `entry` must take
  no parameters.
- `tools/elf_test.py` (gate step `elf`) runs such executables natively:
  exit statuses, a division by zero (SIGFPE) and a stack too small for the
  recursion (SIGILL from the prologue's check).

For code entered some other way the premises are obligations on whatever
sets up the x86 state:

`compileSource_stops` (Mini/SourceStops.lean) has the same premises, without
`stackNeed depth ≤ window`, and with a heap limit of at least 1; its
conclusion is `Faults`. `compileSource_behaviour` has those premises too,
and a run to a state with no step that is not a fault.

- **Image.** `CodeAt s.memory imageBase binary.image`: the image is loaded
  byte for byte at any base and is executable. Its bytes are apart from the
  stack window and from the heap. The proofs then show that nothing writes to
  them.
- **Entry.** `s.rip = imageBase + entries[f]`. The function is entered by a
  near call, so the return address is at `[rsp]`.
- **Arguments.** Argument `k` is the 64-bit word at `rsp - (8k + 16)`, just
  below the return address. The results come back in the same slots, and the
  last one is also in rax. This is not the SysV convention, so a stub has to
  translate between the two.
- **Stack.**
  - r15 holds the stack limit, and the window is the stack from
    `binary.guard` bytes below r15 up to the return address (`StackAt`:
    `r15 + window = rsp + guard`, r15 above 4 GiB and at most 8 bytes above
    rsp). Its bytes must be mapped and writable, and they must be apart from
    the image. `binary.guard` is one frame plus 8 bytes: what a call writes
    (arguments, return address) before the callee's check.
  - Each prologue ends with `cmp r15, rsp; jbe +2; ud2`, so a frame that
    would end below r15 faults before it writes a slot. The contract of
    every function is therefore "returns, or the window is short of
    `binary.stackNeed depth` and the run stops at a fault"; with
    `binary.stackNeed depth ≤ window ≤ 2^62` it returns.
  - `depth` is existential in `compileSource_correct`, so nobody can compute
    the needed stack before the run.
- **Heap (`HeapAt`).**
  - The base is in r12, the cursor (an offset) in r13, and the limit in r14,
    with `limit < 2^62`.
  - The bytes at `r12 + a` for `a < limit` are the heap. They are mapped,
    writable, and apart from the stack window, the return address and the
    image.
  - `compileSource_correct` also requires `r13 = 1` and zero bytes from
    offset 1 up, which a fresh anonymous mapping provides, and an empty
    write trace (`silent`: the state's trace, which `HeapAt` makes the mini
    heap's, has no events yet), so that the output it concludes equal to
    Core's world's is the code's own.
  - `compileProgram_correct` accepts any cursor.
- **Registers after the call.**
  - rsp is restored to `rsp + 8` and rbp is restored.
  - rax, rcx, rdx, rsi, rdi, r11 and r13 may change (the code writes rdx,
    rsi and rdi only for a `Sys` statement). r13 is callee-saved under SysV, so a
    SysV caller's stub has to save it. The stubs also save r12, r14 and
    r15, which they set.
  - RFLAGS is unspecified. DF is never changed, and the code has no string
    instructions.
- **Memory.** Only the window and the heap change.
- **Operating system.** Linux maps memory as requested, saves and restores
  the full register state and RFLAGS across preemption and signal delivery,
  and no debugger or second thread changes the process. Linux enables CET
  shadow stacks only for programs that opt in. They are compatible with the
  compiled code anyway, because every `call` is paired with a `ret`.

## 9. Testing the x86 model against the CPU

```bash
python3 -I formal/tools/x86_model_test.py target/claude-work/step14/seed1 --per-form 500 --seed 1 --probes
python3 -I formal/tools/x86_model_test.py target/claude-work/step14/seed2 --per-form 500 --seed 2
```

**The forms.** The tool tests every instruction form the mini compiler emits
(on 10-31, 80 emitted encodings split into 107 forms, 28 of them SSE). The Lean side prints
`Instr.encode` for every `Instr` constructor (every `BinOp` and `CmpOp` at
both words), plus `prologue` and `epilogue`. The tool splits those bytes into
the form table and fails on any byte it cannot place, so a new emitted form
cannot go untested. The forms are:
- `mov` with an imm64 or imm32 operand;
- the frame-slot load and store through `[rbp+disp32]`;
- the heap byte load and store;
- seven register moves;
- `neg`;
- add, sub, and, or, xor and imul at 32 and 64 bits;
- the bump allocator's 64-bit add and and;
- `sub rsp, r11`;
- three `cmp`s and `test`;
- ten `setcc`s and `movzx`;
- `jmp`, `je`, `jb`, `jbe` and `call` (rel32);
- `push` and `pop rbp`, `ret`, and `ud2`;
- (F9) `movd`/`movq` of xmm0 and xmm1 from and to rax and rcx, `addss`
  ... `divsd xmm0, xmm1`, `cmpss`/`cmpsd xmm0, xmm1` with predicates 0, 1
  and 2, `cvtsi2ss`/`cvtsi2sd xmm0` from ecx and rcx, `cvtss2sd` and
  `cvtsd2ss xmm0, xmm0`. Their cases also load xmm0 and xmm1 (random float
  patterns in the low 64 bits: zeros, infinities, NaNs with payloads,
  subnormals, near operands; random high bits) and MXCSR's default
  0x1F80, and compare the low 64 bits of both registers afterwards. The
  gate runs this test as the quick step `x86-model` (100 cases a form). On
  10-31 (AMD Ryzen 9 5900HX): 10,603 cases, 2,800 of them SSE, 0 disagree.

**Each case.** The tool draws random registers (with special values and
equal operands mixed in), random status flags and DF, a random 256-byte
memory region, and a random displacement or immediate. Each memory form's
base register is set so that the access lands in the region.

**Native run.** A stub in an RWX mapping loads RFLAGS and all sixteen
registers and executes the bytes. Every possible next `rip` (fall-through,
branch target, call target, or return address) holds a landing pad that
records which one was reached, along with the registers and RFLAGS. `ud2`
runs in a forked child, which must die of SIGILL.

**Lean run.** The tool generates `ModelTest.lean` and runs it with
`lake env lean`. It applies `decode` and `execute` to the same states with
`#eval`.

**The comparison.**
- Exact on the sixteen registers, `rip` and the region. The rest of the page
  must be unchanged.
- On the flag bits that `Step` fixes: CF, PF, AF, ZF, SF, OF and DF. AF is
  left out for AND, OR, XOR and TEST, and every flag is left out for IMUL
  and NEG.
- `decode` must return exactly the instruction's length, every shorter prefix
  must decode to nothing, a random tail must not change the result, and the
  instruction must not decode as a division.

**Results** (2026-10-21, AMD Ryzen 9 5900HX, Zen 3).

| run | compiler forms | cases | disagreements |
|---|---:|---:|---:|
| seed 1 | 57 | 28,003 | 0 |
| seed 2 | 57 | 28,003 | 0 |

Each run took about 4 s natively and 35 s in Lean. A deliberately wrong
model was caught on every case of the mutated forms: CF flipped after `cmp`,
ZF flipped after `add`, and rbx changed by `pop rbp`.

**Disagreement found (outside the compiler's forms).** `decode` accepts the
byte store `88 /r` with no REX prefix and reg field 4-7 as a store of SPL,
BPL, SIL or DIL. Without REX, the CPU stores AH, CH, DH or BH. For example,
`88 a1 00 00 00 00` (`mov [rcx], ah`):

- input: rax = 0xbbc8298e, so AH = 0x29; rsp = 0x2b;
- the model writes 0x2b, the low byte of rsp;
- the CPU writes 0x29.

The `--probes` forms `mov [rcx+disp32], ah` and `bh` disagree on 950 of
1,000 cases. The other 50 are cases where the two bytes happen to be equal.
With a 0x40 prefix (SPL, DIL), the model and the CPU agree.

The compiler emits only `88 81` (AL), and the encoder `byteMemoryBytes`
forces a REX prefix for registers 4-7, so the theorems were not affected.
But `Step` accepted the wrong successor for those bytes.

**Fixed.** `decodeOpcode` in `Machine/Scalar.lean` now rejects opcode 136
without REX when the reg field is 4-7, as `byteRegister?` already does for
SETcc and MOVZX. `byte_opcode_memory` in `Machine/Encoding.lean` takes the
matching side condition. The `--probes` AH and BH forms now expect `decode`
to return `none`. Seed 6 at 200 cases per form, with probes: 61 compiler
forms and 4 probe forms, 0 disagreements.

## 10. Not trusted

These are evidence, not part of the trusted base:
- the difftests (`mini_difftest.py`, `fn_difftest.py`, `x86_model_test.py`,
  `frontend_difftest.py`);
- laniusc's lexer and parser, whose tree the front end validates (section 4);
- the native harness stubs (except as the loader in section 8, when they are
  used that way);
- `compileSource` and `compileProgram`, and the optimizer
  (`optimize_program`) inside `compileSource`;
- the encoders and every proof file.
