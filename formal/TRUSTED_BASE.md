# Trusted base of the verified compiler

Roadmap step 14. This is every assumption that the two top-level theorems rest
on but do not prove:

- `Lanius.Mini.compileSource_correct` (`Lanius/Mini/SourceCorrect.lean`). If
  `compileSource sp = some binary` and Core evaluates `f(args)` to `v`, then
  the code for `f`, entered by a near call in a suitable x86 state, returns
  slots that represent `v`.
- `Lanius.Mini.compileProgram_correct` (`Lanius/Mini/Correct.lean`). The same
  for a mini IR program against the mini big-step semantics.

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
| `SrcProgram.toCore` and the `toCore` of each construct | `Mini/Source.lean` | which Core program a source program *is*: each construct is the Core construct of the same name, and functions are numbered by position |
| `FieldsHold`, `SrcType.HoldsAt` | `Mini/Source.lean` | how a Core value sits in 64-bit slots: an `i32` is zero-extended, a `bool` is 1/0, a struct is its fields in order, an enum is a tag then its payload, a pointer is its address |
| `Returned`, `HeapAt`, `Contract`, `Scratch`, `InHeap` | `Mini/Simulation.lean` | the calling convention and what "returns" means (below) |
| `Below`, `Binary.stackNeed` | `Mini/Frame.lean`, `Mini/Bytes.lean` | the stack window |
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

`compileSource_correct` takes a `SrcProgram` value, not source text. Roadmap
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
  syntax. `lexTokens` adds one keyword that `keywordRules` lacks: `as` is
  token code 195, as in laniusc. Token kinds are laniusc's codes
  (`TokenKind.gpuCode`). The difftest below compares these tokens with
  laniusc's lexer (kind, start and length).
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
- **Unambiguity.** It is not proved that the grammar gives each token
  sequence at most one parse tree. `sourceProgram_sound` says the program is
  `build` of *some* parse tree of the tokens, namely laniusc's. If the grammar
  were ambiguous on the subset, a different tree could have a different
  reading, and the trusted claim is that it does not. The difftest's
  mutations (a production id, a parent or a token changed, all rejected) are
  evidence, not a proof. To shrink it: prove the grammar unambiguous on the
  subset, for example from the determinism of laniusc's LLP tables.
- **The reading.** `build` (in `Frontend.lean`) is the meaning of the subset's
  concrete syntax, as `toCore` is the meaning of `SrcProgram` (section 2). It
  makes these choices:
  - each file is a module, named by its `module` item (the empty path
    without one); `m::x` names `x` of the module `m`, a bare `x` names `x`
    of the current module; `import m;` only adds m's variants to those a
    bare variant name may mean, and traits, type aliases and extern
    functions are skipped;
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
  - `x.m(args)` (`x` any value) and `T::m(args)` (`T` a type parameter) call
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
  - a local is the byte offset of its binding (a parameter, `let` or match
    binder);
  - a use names the innermost binding with the same spelling, and locals may
    not be spelled like a function, type, variant or constant of their
    module;
  - `let` scopes over the rest of its block;
  - `if` without `else` has an empty else;
  - binary operators fold to the left;
  - an integer literal is below 2^31, and `-` before it is `negate`;
  - the path `alloc::allocator::alloc(size, align)`, in a `let` of type
    `ptr`, is Core's `alloc`, and the statement
    `alloc::allocator::dealloc(p, size, align);` is Core's `dealloc`; the
    alignment must be a literal `2^k` (`8` or `(8 as usize)`), read as the
    shift `k`. `slice_from_raw_parts(p, n)`, in a `let` of type `[T]`, is
    Core's raw view of `T`. These spellings are fixed: build does not look
    at the extern declarations in `alloc::allocator`;
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
    slice is a slice local (named by the byte offset of `slice_from_raw_parts`)
    and its return;
  - a bare variant name is the one variant of that spelling among the
    current module's enums, else among its imported modules' enums;
    `E::V` and `m::E::V` name enum E's variant V, `m::V` module m's one V.

  It rejects anything outside the subset. `build` has no relational spec yet;
  the difftest checks it against the generator's programs. To shrink it:
  state the reading as an inductive relation on `CTree` and prove `build`
  against it.
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
   - **The extractor.** `formal/tools/extract.py` (1,227 lines of Python) is
     trusted to give each construct it accepts the Lean meaning that Lanius
     gives it. It maps types one to one (`i32` and `u32` to `BitVec 32`,
     `u64` to `BitVec 64`, `usize` to `Nat`, `u8` to `UInt8`, `List<T>` to
     `List T`, `Box<T>` to `T`) and rejects anything outside the subset.
   - **The prelude table.** `PRELUDE_FNS` and `PRELUDE_TYPES` in
     `extract.py` are trusted. `boxed` and `unbox` are the identity,
     `plus`/`times`/`minus` are `Nat` `+`/`*`/`-` on every run that returns
     (they panic instead of wrapping, and `minus` panics when `b > a`), and
     `max_of` is `max`. The prelude bodies are the only code that touches
     raw memory (`alloc`, `typed_slice_from_storage`).

   The list operations (`SPEC_FNS`) are *not* trusted. Each is extracted with
   a spec theorem that Lean checks. The trust also covers laniusc itself and
   the Lanius runtime (allocation, panics, stack depth) on this one program.

   Checked by:
   - `extract.py --check`, which confirms that `Compiler.lean` is not stale
     (it passes at this commit; CI does not run it);
   - `mini_difftest.py`, which compares images from `#eval compileProgram`
     and from the Lanius build byte for byte (3,006 programs, 757,000 bytes,
     no differences);
   - `fn_difftest.py`, which calls each extracted function in Lean and
     natively (8,200 calls on the back end and 3,140 on the front pass, no
     differences).

   To shrink it: a Lean semantics for the pure subset and a proof that
   extraction preserves it (roadmap steps 2 and 6), and self-hosting
   (step 11).
2. **The Lean build.** Run `#eval compileSource` or a compiled Lean
   executable. Extraction is then irrelevant, but Lean's code generator and
   runtime are trusted: GMP `Nat`, and the `@[extern]` and `implemented_by`
   implementations of `BitVec`, `UInt8` and `List`. The kernel does not see
   any of this code.

## 6. The x86 model

- **What.** The x86 semantics that `Steps` uses:
  - `Lanius/X86/Machine/State.lean`: user-mode state, meaning sixteen 64-bit
    registers, `rip`, RFLAGS as one 64-bit word, and memory as a total function
    from 64-bit addresses to bytes;
  - `Machine/Scalar.lean`: `decode`, `execute`, `Step`, `Steps` and `Fault`;
  - `Machine/Flags.lean` and `Machine/Alu.lean`: flag results and condition
    codes;
  - `Machine/Memory.lean`: little-endian reads and writes;
  - `Control/Decode.lean`, `Register.lean` (REX) and `Word.lean`.

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
    abstract instruction (`cmp; setcc`, `test; jz`, `cmp; jbe` in `bump`), and
    every other emitted form reads no flags.
- **Still assumed.** That the CPU's run is one of the model's runs (section
  6). The theorem covers runs of exactly `n` steps, the length of the run to
  the return; after `n` steps the code is back in the caller. It says nothing
  about runs of other lengths.

## 8. What the caller and the loader must provide

The premises of `compileProgram_correct` (also inside
`compileSource_correct`) are obligations on whatever sets up the x86 state.
Today no verified loader exists. The images run natively only from a
hand-written ctypes stub, which checks the mini difftest's image and is kept
outside the repository with the scratch work. The ELF startup and exit wrapper (`X86/StartupExitCheck.lean`) has
not been composed with the theorem yet.

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
  - The window must satisfy `binary.stackNeed depth ≤ window ≤ 2^62`. Its
    bytes must be mapped and writable, and they must be apart from the image.
  - `depth` is existential in `compileSource_correct`, so nobody can compute
    the needed stack before the run.
  - The compiled code has no stack check. Overflow has to be caught by the
    runtime, for example with a guard page that turns it into a fault, and
    that case is outside the theorem.
- **Heap (`HeapAt`).**
  - The base is in r12, the cursor (an offset) in r13, and the limit in r14,
    with `limit < 2^62`.
  - The bytes at `r12 + a` for `a < limit` are the heap. They are mapped,
    writable, and apart from the stack window, the return address and the
    image.
  - `compileSource_correct` also requires `r13 = 1` and zero bytes from
    offset 1 up, which a fresh anonymous mapping provides.
  - `compileProgram_correct` accepts any cursor.
- **Registers after the call.**
  - rsp is restored to `rsp + 8` and rbp is restored.
  - rax, rcx, r11 and r13 may change. r13 is callee-saved under SysV, so a
    SysV caller's stub has to save it.
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

**The forms.** The tool tests every instruction form the mini compiler emits:
57 forms. The Lean side prints `Instr.encode` for every `Instr` constructor
(every `BinOp` and `CmpOp` at both words), plus `prologue` and `epilogue`.
The tool splits those bytes into the form table and fails on any byte it
cannot place, so a new emitted form cannot go untested. The 57 forms are:
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
- `jmp`, `je`, `jbe` and `call` (rel32);
- `push` and `pop rbp`, `ret`, and `ud2`.

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
