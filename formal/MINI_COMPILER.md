# Mini compiler pilot

A small verified compiler, built the way the full verified compiler should be:
pure functions over algebraic data, proved in Lean by induction on syntax and
one simulation lemma per pass, against the existing x86 machine semantics.
It measures two things the earlier attempt could not keep under control: proof
size relative to the compiler, and Lean check time.

## Rules

- The compiler is pure: enums, structs, a cons list `List<T>`, `Option`/`Result`,
  `match`, recursion, and a generic `Box<T>` for recursive syntax. No raw
  memory: no `slice_from_raw_parts`, no hand-computed record sizes, no packed
  word buffers. Allocation uses panicking operations, so a successful run never
  silently drops data.
- The Lean side is ordinary definitions extracted from the Lanius code, with
  the same shape (`Box<T>` is `T`, `List<T>` is `List T`, `i32` is `BitVec 32`,
  `u64` is `BitVec 64`, `usize` is `Nat`). Proofs are about those definitions; nothing is executed
  inside the kernel.
- The top-level theorem comes first. Every lemma is a premise of a pass theorem,
  and every pass theorem is a premise of the top-level theorem.
- Each file checks in seconds. Proof size is measured against the compiler code
  it covers.

## Top-level theorem

`Lanius.Mini.compileProgram_correct` in `Lanius/Mini/Correct.lean`. For a
program `prog`, function `f`, arguments `args` and an x86 state `s` about to
execute `f`'s entry:

```text
compileProgram prog = some binary
∧ prog.Returns depth f args vs      -- f returns the slots vs, calls nested < depth deep
∧ binary.image is loaded at imageBase, s.rip is f's entry
∧ argument k is at rsp - (8k + 16)  -- just below the return address
∧ window ≥ binary.stackNeed depth, and the image is apart from the
  window bytes below rsp
→ ∃ n s', Steps n s s'
    ∧ s'.rip = the return address at [s.rsp]
    ∧ vs[k] is at s.rsp - (8k + 16)  -- the results replace the arguments
    ∧ s'.rax = the last of vs
    ∧ s'.rsp = s.rsp + 8, rbp is restored
    ∧ every register but rax, rcx, r11 is unchanged
    ∧ no memory outside the window changed
```

This is forward simulation of terminating runs. The x86 model is deterministic
on everything the theorem observes, so it also rules out any other result.
Divergence, traps and the ELF startup/exit wrapper come later; the existing
`StartupExitCheck` composes with this function-level contract.

## Passes

The compiler is `formal/lani/mini/compiler.lani`; `Lanius/Mini/Compiler.lean` is
extracted from it.

1. `compileExpr` (expressions into rax, temporaries in frame slots) and
   `compileStmt` (statements; jump targets are byte offsets in the body, since
   every abstract instruction has a fixed size).
2. `Instr.encode` (offsets to rel32 displacements, then literal bytes, proved
   equal to the existing encoders in `X86/Machine/*Encoding.lean`) and
   `compileProgram` (functions back to back, calls resolved to entry offsets).
3. Prologue and epilogue, proved equal to the existing `framePrologueBytes` and
   epilogue.

Simulation invariant (one relation for every activation): `rip` is the body
base plus the abstract pc, `rbp`/`rsp` are the frame's, each slot `x` is
`read64` of frame slot `x`, and memory outside the activation's stack window is
what it was at entry, so the code bytes are untouched.

## Milestones

1. Straight-line: i32 literals and locals, `+ - * & | ^`, negation, assignment,
   `return`. One function.
2. `bool`, comparisons, `if`, `while`.
3. Functions with parameters and direct calls.
4. The same compiler written in Lanius, and the shallow extractor that produces
   these Lean definitions from it.

Each milestone records proof lines, compiler lines and fresh check time.

## Status

All four milestones are done, with no `sorry` and only the standard axioms
(`propext`, `Classical.choice`, `Quot.sound`). The source language has i32
arithmetic, signed comparisons producing 1/0, `if`, `while`, `return`, and
functions with parameters and direct (also recursive) calls. The top-level
theorem is about the definitions extracted from the Lanius source.

Slots and the accumulator are 64-bit words (roadmap step 6a, 2026-10-21). Each
arithmetic operation and comparison carries a `Word`. An `S32` one is the
32-bit x86 instruction: it acts on the low halves, zero-extends its result
(`Word.apply .s32 op a b = widen (op (low a) (low b))`) and compares signed. A
`U64` one is the same instruction with a REX.W prefix: it acts on all 64 bits
and compares unsigned (setb/setbe/seta/setae). Literals are `mov rax, imm64`.
The front pass uses `S32` for `i32` and `bool` and `U64` for enum tag tests;
an `i32` is held zero-extended (`SrcType.Holds`).

The mini IR has a byte heap (roadmap step 6c, back end, 2026-10-21). `alloc t
shift size` aligns the cursor up to `2^shift`, stores that offset in `t` and
moves the cursor past `size` bytes, or traps (`ud2`) when that would pass the
limit; `loadByte` and `storeByte` read and write one byte at an offset. On x86
the heap base sits in r12, the cursor (an offset) in r13 and the limit in r14;
r12 and r14 are never written, r13 only by the bump. The top-level theorem
gains two premises: the heap's bytes are at r12 + offset below the limit, and
that range is apart from the stack window. Its conclusion adds the final heap:
cursor in r13, bytes at r12 + offset. Memory outside the stack and the heap is
unchanged.

The proof has two layers.

- Compiler logic: `compileStmt_correct` / `compileFunc_correct` prove the compiler
  against an abstract machine (accumulator, frame slots, byte-offset pc), by
  induction on the source derivation. A call's effect is a parameter of the
  abstract machine: whatever the callee is known to return.
- Bytes: one x86 lemma per abstract instruction (`Simulation`). A call copies
  its arguments to just below the return address it pushes, which is where the
  callee's prologue puts its parameter slots, uses the callee's `Contract`,
  and copies the results the callee left in those slots to its target slots.
  A return copies its values to slots 0, 1, ... before the epilogue. `compiled_contract` proves every function's contract by strong
  induction on call depth: an activation that nests calls fewer than `d` deep
  uses at most `(d + 1) * frameNeed` stack bytes and changes nothing else.

| file | lines | check (s) | role |
|---|---:|---:|---|
| `Compiler` | 1541 | 2.9 | extracted: syntax, abstract instructions, compiler, encoder, linker, front pass |
| `Semantics` | 157 | 0.8 | big-step source semantics with call depth |
| `Asm` | 189 | 0.9 | abstract machine, byte-offset placement, `Star` runs |
| `CompileCorrect` | 518 | 1.3 | compiler against the abstract machine |
| `Fits` | 218 | 1.1 | static facts: slots in frame, targets in body, callees exist |
| `Bytes` | 396 | 1.7 | extracted encoders equal the x86 encoders; image layout |
| `Flags` | 135 | 1.4 | each comparison's condition code after `cmp` |
| `Frame` | 128 | 1.2 | stack windows and address depths (`bv_omega`) |
| `HeapSteps` | 250 | 1.6 | x86 runs of the bump allocator and the byte load and store |
| `Simulation` | 1414 | 5.8 | x86 lemma per instruction, slot copies, the call macro, body simulation |
| `Correct` | 323 | 1.7 | layout, prologue, function contract, top-level theorem |

Check times are `lake env lean` per file on the laptop, about 0.4 s of each is
import loading. The compiler is about 400 lines of Lanius (plus a 63-line prelude
and 64 lines of list operations); the proofs are about 3,700 lines.

### The front pass: a Core subset to the mini IR

The first piece of the verified compiler (roadmap step 4). `compile_source` in
`compiler.lani` type-checks and lowers a source program, a subset of Lanius
Core, to the mini IR, then runs `compile_program`. The subset: `i32`, `bool`,
`u8`, `u32`, `u64` and `usize` locals and parameters, `+ - * & | ^`, unary
`-` and `!`, the six comparisons (unsigned on the unsigned types), `&&` and
`||`, unsigned literals, casts between `i32` and the unsigned types (Core's
wrapping: an `i32` cast to a 64-bit type is sign-extended), `let`, assignment, `let x = f(...)` and
`x = f(...)`, sequencing, `if`, `while`, and `return`; and structs whose
fields have any type, structs and enums included: literals in `let`, field
reads (a struct or enum field copies its slots), writes of scalar fields,
whole-struct copies, and struct parameters; and enums whose payloads have any
type: `let x = E::V(...)`, copies, enum parameters, and
`let y = match x { ... }` with one arm per variant in order, each binding its
variant's payload and giving a value of any type; and raw pointers with the
byte heap, as Core's `let p = alloc(size, 2^k)`, `let b = loadByte(p, offset)`,
`storeByte(p, offset, b)` and `dealloc(p, size, 2^k)` (sizes and offsets
`usize`, bytes `u8`). Each binding gets its own
slots (lets after the parameters): a scalar one, a struct its fields' slots
one after another, an enum a tag slot (the variant number) and then room for
its longest payload; booleans are 1 and 0. An unsigned value is its number,
and arithmetic on a type narrower than 64 bits is masked back to its width.
A `match` is a chain of tag tests, and an arm's binders name the scrutinee's
payload slots, since an arm only reads them. A function returns its result
type's slots, so `return`, `let x = f(...)` and `x = f(...)` take structs and
enums too. A struct type must take a slot, so no two bindings share one.

`Lanius/Mini/Source.lean` maps each source construct to the Core construct of
the same name (`SrcProgram.toCore`). The theorem is about Core's own
evaluator, `Lanius.Semantics.evalExpr`, on that program:

```text
compileSource sp = some binary
∧ sp.funcs[f]? = some func
∧ ArgsHold (paramTypes func.params) args bits   -- each argument value is its bits
∧ heap.cursor = 1 ∧ (∀ a ≥ 1, heap.bytes a = 0) ∧ heap.limit < 2^62
∧ evalExpr fuel sp.toCore {} (call f args) = done v final
∧ final.heap.nextAddress ≤ heap.limit                   -- Core's run fits the heap
→ ∃ depth results after, func.ret.HoldsAt v (Func.entry results) 0   -- laid out like an argument
    ∧ results.length = func.ret.size
    ∧ after.cursor = final.heap.nextAddress
    ∧ (the compileProgram_correct conclusion for f, bits, heap, results, after and depth)
```

`compileSource_correct` in `Lanius/Mini/SourceCorrect.lean`. The proof is
forward simulation of Core's fuel-indexed evaluator into the mini big-step
semantics:

- Expressions (`LowerExpr`): a lowered expression evaluates in Core without
  changing the state, to a value its mini expression represents. `wrapSigned`
  on `i32` is `BitVec 32` arithmetic; `&&`/`||` short-circuit in Core and are
  `&`/`|` on 1/0 bits in the mini IR.
- Statements and calls (`LowerStmt`): Core's locals mirror the scope through a
  slot-to-cell map, every cell id is below `nextCell`, and a callee only
  touches cells allocated after its call, so the caller's cells survive. A
  struct is one Core cell holding a `.structure` value and several mini slots
  (`HoldsAt`, mutual with `FieldsHold` since types nest); bindings' slot ranges are disjoint (`Layout.apart`), which is
  what makes a copy `a = b` safe slot by slot. An enum value is a
  `.enumeration` whose variant is the tag and whose payload sits after it;
  `lowerArms_sound` follows Core's `evalMatchArms` down the arms against the
  tag tests, with the arm's binders bound to cells Core allocates and mapped
  to the payload slots. `stmt_sound` is strong
  induction on fuel, one lemma per statement form; the mini derivation's call
  depth is existential, and `Exec.mono` lifts it.
- The heap (`Grows`, `HeapCorr`): a pointer is its address in one slot.
  Core's `Heap.allocate` puts a block at `nextAddress` rounded up to the
  alignment and moves `nextAddress` past it by `max size 1`; the lowered
  `alloc` bumps the mini cursor the same way (the size goes through
  `x + (x == 0)`), so the cursor is always Core's `nextAddress`. `HeapCorr`
  says that, and that every live block's bytes are the mini heap's bytes at
  its addresses, that the blocks lie in order below the cursor without
  overlapping, and that the bytes from the cursor up are zero (Core's blocks
  start zeroed). A load or store Core completes is inside a live block, so it
  is below the cursor and reads or writes the same byte; `dealloc` changes no
  live bytes the mini heap needs, so it lowers to nothing (the bump allocator
  never frees). The theorem's premise bounds Core's final `nextAddress` by the
  mini limit; `execStmt_grows` (Core's `nextAddress` never decreases) carries
  that bound back to every allocation.

| file | lines | check (s) | role |
|---|---:|---:|---|
| `Source` | 353 | 1.1 | Core meaning of source programs, value representation, `i32` wrap lemmas |
| `Unsigned` | 166 | 2.4 | unsigned arithmetic, comparisons and casts as slot arithmetic |
| `LowerExpr` | 665 | 5.0 | expressions |
| `Grows` | 788 | 3.8 | Core's `nextAddress` never decreases; Core call and statement inversions |
| `HeapCorr` | 342 | 1.0 | Core heap to mini heap correspondence; allocate, load, store, free |
| `LowerStmt` | 2339 | 8.2 | Core cells, frames, flat values, calls, enums and `match`, statements |
| `SourceCorrect` | 111 | 0.8 | top-level theorem |
| `TypeSound` | 1206 | 2.2 | type checker soundness: an accepted program is well typed in Core (step 7) |

The pass is about 1,200 lines of Lanius (the end of `compiler.lani`), and the
proofs are about 4,800 lines. The per-function difftest covers it (146
functions, 2,920 calls after the unsigned types, run as two shards with
`--shard 0/2` and `1/2`, no differences; 11 native stack overflows on huge
random counts; types nested through `List` render through a `mutual` block of
`partial def`s; after the front-pass heap, 157 functions and 3,140 calls,
no differences, 9 native stack overflows); at 30 cases per function the harness is now too large for
laniusc on the laptop (a GPU buffer fails to allocate). Assumptions the theorem does not cover yet: Core
programs outside the subset, traps and divergence (the theorem covers runs that
return), and the source's type checker against Core's typing rules (step 7).

Type checker soundness (step 7, `Lanius/Mini/TypeSound.lean`): when the front
pass accepts a program, its Core meaning is well typed by Core's own rules,
`Lanius.Typing.ProgramWellTyped` (the judgment Core's checker
`checkProgramWellTyped` decides and the compiler boundaries use).
`compileSource_wellTyped` says `compileSource sp = some binary`, with two
premises the front pass does not check, gives
`ProgramWellTyped (sp.toCoreWith structs enums)`, which is `sp.toCore` with
those struct and enum declarations. Those are the two places the front pass
accepts programs Core rejects. Each comes with a program the front pass
lowers and a proof that Core rejects it. (1) Nominal types: Core looks struct
and enum types up by id in the program's declarations, but `SrcType.struct id
fields` carries its fields inline and `SrcProgram.toCore` emits no
declarations. The premise `sp.Declared P` says every parameter and binding
type agrees with `P`'s declarations. `idClash` uses struct id 0 with fields
`[i32]` and with `[bool]`, and no declarations make it well typed. A program
whose types are all scalar needs none (`compileSource_wellTyped_scalar`
concludes `ProgramWellTyped sp.toCore`). (2) Returns: Core requires a
function with a non-unit result to end in `return` on every path
(`DefinitelyReturns`, where a `while` never counts), and the front pass does
not check this. The premise is `func.body.returns = true` for every function;
`SrcStmt.returns` is that check (`returns_sound`). `noReturn` is
`fn f() -> i32 {}`. Everything else matches: operators, casts, literals
(unsigned ones in range, alignments `2^shift` with `shift < 32`), shadowing
(the scope's innermost binding is Core's last `Context.bind`, for parameters
and match binders too), calls (function `i` is the `i`th signature), field
reads and writes, and exhaustive non-empty `match`. The proof is one lemma per
lowering function, by induction on the syntax.

### Milestone 4: the compiler in Lanius, and extraction

`formal/lani/mini/compiler.lani` is the compiler, written in a pure subset of
Lanius: enums, structs, `match`, recursion, `let`, `if`/`return`. A prelude at
the top of the file holds the only code that touches memory: a generic
`Box<T>`, the cons list `enum List<T> { Nil, Cons(T, Box<List<T>>) }`, and
`usize` arithmetic (`plus`, `minus`, `times`) that panics instead of wrapping.

The list operations (`empty`, `single`, `cons`, `concat`, `length`, `get`,
`get_or`) are ordinary recursive Lanius code after the prelude. Each is
extracted as `Lists.name`, followed by a generated theorem that it equals the
Lean list function (`Lists.concat_spec : Lists.concat a b = a ++ b`), and calls
from the compiler are written as that function, so the proofs use the standard
list lemmas. A wrong list operation fails its theorem when Lean checks the
generated file. This replaced an earlier prelude on `std::vec::Vec<T>` whose
operations were loops that copied, so their Lean meaning was trusted.

`formal/tools/extract.py` turns everything after the prelude into
`Lanius/Mini/Compiler.lean`:

```bash
python3 formal/tools/extract.py formal/lani/mini/compiler.lani formal/Lanius/Mini/Compiler.lean
python3 formal/tools/extract.py --check formal/lani/mini/compiler.lani formal/Lanius/Mini/Compiler.lean
```

The extractor rejects anything outside the subset (loops, mutation, `usize`
`+`/`-`/`*` outside the prelude, signed comparisons, shifts by a variable,
missing match arms), and checks every prelude item against a fixed table of
signatures and Lean meanings. Types map one to one: `usize` to `Nat`, `i32`
and `u32` to `BitVec 32`, `u64` to `BitVec 64` (Lanius integer arithmetic wraps), `u8` to `UInt8`,
`List<T>` to `List T`, `Option<T>` to `Option T`, `Box<T>` to `T`. A prelude
`plus` that returns computed the `Nat` sum, so the `Nat` definitions agree
with every run of the Lanius code that returns. Functions marked
`// extract: inline` become `let` bindings at their call site; that is how a
match arm gets local definitions, since Lanius match arms are expressions.

What is trusted: the extractor and its prelude table (`Box` and the checked
arithmetic), and the Lanius semantics of that small subset. The theorem itself is about the Lean
definitions; the hand-written Lean compiler they replaced is gone. The x86
encoders the compiler writes as literal bytes are proved equal to the existing
`X86/Machine` encoders (`Instr.encode_eq`, `prologue_eq`).

Testing the Lanius binary against the Lean definitions:

```bash
python3 formal/tools/mini_difftest.py target/claude-work/mini/diff --count 300 --seed 2
```

It generates random mini programs (a quarter of them ill-formed, so both sides
must reject them), compiles each with `#eval compileProgram` and with the
Lanius compiler built by laniusc, and compares the images byte for byte. Two
seeds, 602 programs, 157,000 image bytes: no differences. The fact/fib/mix/gcd
image from the extracted definitions also passes the native run (2,368 calls).
After functions began returning several slots (2026-10-21): 201 programs,
58,000 image bytes, no differences, and the native run, now with a
two-result function and its caller, passes 3,368 calls. After the move to
64-bit words: 201 programs (random `S32` and `U64` operations, literals over
the full 64 bits), 78,000 image bytes, no differences, and the native run,
with three functions on 64-bit arguments (unsigned comparisons, `S32` sums
of 64-bit inputs), passes 12,368 calls. After the heap: 201 programs (random `alloc`,
`loadByte`, `storeByte`), 66,000 image bytes, no differences; the native run,
with a stub that maps a heap and sets r12-r14, adds a byte-sum over a fresh
allocation and an alignment probe and passes 12,427 calls. The per-function
difftest after the heap: 150 functions, 3,000 calls, no differences (9 native
stack overflows on huge random counts).

Two more checks of the extraction, 2026-10-21. The same difftest over six more
seeds: 3,006 programs, 757,000 image bytes, no differences. And a per-function
difftest:

```bash
python3 -I formal/tools/fn_difftest.py target/claude-work/mini/fn --per-fn 100 --seed 21
```

It calls each of the 41 extracted functions and methods on random arguments
generated from their declared types, in Lean with `#eval` and natively in a
copy of `compiler.lani` (only the module line changes), and compares canonical
renderings of the results. Two seeds, 8,200 calls: no differences. A run that
does not return is reported, not compared; the only ones were native stack
overflows in `zero_locals` and its callers on frames of about 10^6 locals,
since the compiler recurses once per local. A one-character change to
`BinOp.size` in the Lanius copy is caught.

Limits found on the way:

- laniusc rejected a `Type::Ctor(...)` match pattern anywhere after a bare `<`
  comparison in the same file, which is why the Lanius source writes
  comparisons with `>` and `>=` (the extractor emits `<` and `≤`). Fixed in the
  match-pattern pass (`shaders/parser/tokens/match/pattern/arm_comma.slang`).
- Lanius match arms cannot contain blocks, `if`, or a `match` inside a larger
  expression; helper functions and `// extract: inline` cover this.
- Native recursion depth: the compiler recurses once per list element and per
  zeroed local, so inputs near `frame_limit` overflow the stack. Lean has no
  such limit, so this is outside the theorem (it covers runs that return).
- The Lanius runtime gave every allocation its own page inside a 1 GiB
  `MAP_32BIT` window, which capped one run at about 262k live allocations. The
  window is gone (70a4134f), and the cons list made list walks free, so 300
  programs now run in one binary in 39 MB. Every allocation is still one page;
  a small-object allocator matters once the verified compiler runs on itself.
