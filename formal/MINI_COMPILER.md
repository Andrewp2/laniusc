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

## Tests

The difftests run through one gate, from the repository root:

```text
python3 -I formal/tools/gate.py                 # quick tier: 10 steps, about 2 minutes cold
python3 -I formal/tools/gate.py --tier full     # larger counts, every stdlib module
```

A step that passes is stored under a hash of what it reads (the built
definitions, runAll, the .lani sources, the scripts, laniusc, the stdlib), so
the gate reruns only the steps a change can affect and prints the others'
stored results; with nothing changed it takes under a second. A step that
runs past 300 s is stopped. Below the gate, laniusc's parse trees and builds
and each `lake env lean` run are cached by content (`run_cache.py`), and the
Lean lexer and the validator run in linear and polynomial time where they had
been quadratic and exponential, so the suite that took 3 hours on
2026-10-24 takes about 2 minutes. The sections below give each script's own
command line.

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

This is forward simulation of terminating runs. The x86 `Step` leaves some
flags free, so `compileProgram_deterministic` (`Lanius/Mini/Determinism.lean`)
adds that every `n`-step run from `s` ends with the same registers, rip and
memory as the one above, so it has returned the same results too. The compiled
code reads a flag only right after the instruction that sets it.
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

The mini IR has integer division (roadmap step 10/11 item F4, back end,
2026-10-21). It is a statement, `divide word op t left right`, so expressions
stay total. `op` is one of `sDiv`, `sRem`, `uDiv`, `uRem`; the `Word` sets the
width as for arithmetic (`S32` acts on the low halves and zero-extends, `U64`
on all 64 bits). Signed division truncates and the remainder takes the
dividend's sign, as in Core. A zero divisor, or a signed division of the
least value by -1, has no run, like a trapping load. On x86 it is `mov rcx,
rax; mov rax, [slot]; mov r11, rdx`, then `cdq`/`cqo` or `xor edx, edx`,
`idiv`/`div` on ecx or rcx, `mov rax, rdx` for a remainder, and `mov rdx, r11`.
The front pass can use `(S32, sDiv/sRem)` for `i32`, `(U64, uDiv/uRem)` for
`usize` and `(U64, sDiv/sRem)` for `isize`; it does not yet.

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
| `Compiler` | 3136 | 3.6 | extracted: syntax, abstract instructions, compiler, encoder, linker, modules and objects (step 9), front pass, optimizer and validator |
| `Semantics` | 220 | 0.7 | big-step source semantics with call depth |
| `Asm` | 208 | 0.8 | abstract machine, byte-offset placement, `Star` runs |
| `CompileCorrect` | 574 | 1.4 | compiler against the abstract machine |
| `Fits` | 244 | 1.0 | static facts: slots in frame, targets in body, callees exist |
| `Bytes` | 459 | 1.6 | extracted encoders equal the x86 encoders; image layout |
| `Flags` | 135 | 1.4 | each comparison's condition code after `cmp` |
| `Frame` | 128 | 1.2 | stack windows and address depths (`bv_omega`) |
| `HeapSteps` | 262 | 1.9 | x86 runs of the bump allocator and the byte load and store |
| `WordSteps` | 289 | 2.0 | x86 runs of the 32- and 64-bit word load and store; memory words as bytes |
| `DivSteps` | 235 | 0.8 | x86 runs of a division: dividend extension, `div`/`idiv`, the result and rdx restored |
| `Simulation` | 1624 | 6.8 | x86 lemma per instruction, slot copies, the call macro, body simulation; each run with its `Det` |
| `Correct` | 325 | 2.1 | layout, prologue, function contract, top-level theorem |
| `DecodeUnique` | 467 | 5.3 | `decode` reads only its instruction's bytes, so it is unique at a rip (step 14) |
| `StepDet` | 377 | 2.1 | `Step` agrees on two states but for flags; `Det` runs (step 14) |
| `DetSteps` | 177 | 1.0 | which emitted forms read or set flags; prologue and epilogue as `Det` runs (step 14) |
| `Link` | 675 | 1.4 | separate compilation: linking separately compiled modules is `compileProgram` of their program (step 9) |

Check times are `lake env lean` per file on the laptop, about 0.4 s of each is
import loading. The compiler is about 400 lines of Lanius (plus a 63-line prelude
and 64 lines of list operations); the proofs are about 5,000 lines.

### The front pass: a Core subset to the mini IR

The first piece of the verified compiler (roadmap step 4). `compile_source` in
`compiler.lani` type-checks and lowers a source program, a subset of Lanius
Core, to the mini IR, then runs `compile_optimized` (the optimizer, checked by
the validator, then `compile_program`; see step 13 below). The subset: `i32`, `bool`,
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
`usize`, bytes `u8`), and `p + n` and `p - n` with a `usize` `n`, which wrap
at 2^64 like Core's pointer offset; and Core's raw `i32` slices, as
`let s = slice_from_raw_parts(p, n)`, `let x = s[i]` and `s[i] = v`, with an
`i32` or `usize` index. Each binding gets its own
slots (lets after the parameters): a scalar one, a struct its fields' slots
one after another, an enum a tag slot (the variant number) and then room for
its longest payload; booleans are 1 and 0. An unsigned value is its number,
and arithmetic on a type narrower than 64 bits is masked back to its width.
A `match` is a chain of tag tests, and an arm's binders name the scrutinee's
payload slots, since an arm only reads them. A function returns its result
type's slots, so `return`, `let x = f(...)` and `x = f(...)` take structs and
enums too. A struct type must take a slot, so no two bindings share one.

`Lanius/Mini/Source.lean` maps each source construct to the Core construct of
the same name (`SrcProgram.toCore`), and declares each struct and enum id with
the fields or variants the front pass derives from the program's types. The theorem is about Core's own
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
- Raw slices (`LowerStmt`, `HeapCorr`): a slice is its address in one slot.
  Its length lives only in Core, which checks every index against it; the
  theorem covers runs that return, so the lowered code needs no bounds test.
  Element `i` is the 4 bytes at address + 4i, read by `loadWord M32` and
  written by `storeWord M32`. `HeapCorr.loadNatLE` and `HeapCorr.storeBytesFrom`
  match Core's little-endian `loadNatLE` and `storeBytes` with the mini heap's
  `readLE` and `writeLE`. Making a slice only marks its block borrowed, which
  `HeapCorr` does not depend on.
- Struct slices (`SliceLayout`, `LowerStmt`): `slice_from_raw_parts` also
  takes structs whose fields are all `i32`, `bool`, `usize` or `ptr`. Core
  gives each such field one 8-byte native word, and element `i` of a struct
  of `n` fields sits at address - (i*n + n - 1)*8 (Core's `elementBase?`,
  which grows down). The front pass computes that base, then loads or stores
  each field with one word operation at base + 8j: 4 bytes for `i32` and
  `bool`, 8 for `usize` and `ptr`. The lowering now gets the program's
  declarations, so it checks a slice's element type against the declared
  struct. `SliceLayout` proves Core's layout for these structs
  (`valueWords_struct`, `fieldOffset_struct`) and reads them field by field;
  `exec_loadFields` and `exec_storeFields` match the mini loads and stores
  with Core's `readNativeValue` and `writeNativeValue`.
- Enum slices: an enum whose payload fields are all word types, with at most
  2^32 variants, takes 1 + (longest payload) words: Core stores the tag in
  4 bytes of word 0 and payload field j in word 1 + j. A read loads the tag,
  then tests it against each variant in turn (the last needs no test) and
  loads that variant's payload words; a write stores the tag, then the
  payload of the value's variant the same way. `valueWords_enum` and
  `readNativeValue_enum` give Core's layout; `loadVariants_pick` and
  `storeVariants_pick` show the tag tests reach the variant Core used.
- Effectful expressions (`LowerEval`): `SrcEff` is an expression that may
  call functions anywhere inside it, with statements `LetEval`, `SetEval`,
  `IfEval`, `WhileEval`, `ReturnEval` and `Discard` that take one. Its code
  computes the value into the slots from a given slot, in Core's order: the
  left operand in `slot`, the right in `slot + 1`, a call's arguments one
  after another, and the right side of `&&` and `||` only when Core
  evaluates it. A `while` computes its condition again after the body. Its
  own type, apart from `SrcExpr`, keeps `SrcExpr`'s proofs by induction:
  `SrcEff` nests through `List`, so `EvalSound` is proved together with
  `StmtSound` by strong induction on Core's fuel (`sound_both`), which drops
  at every subexpression. A struct literal computes its fields one after
  another from `slot`; an enum literal its payload from `slot + 1`, then the
  tag into `slot`. `SrcEff.types` lists the literals' types, which
  `SrcStmt.declare` declares, so Core's typing finds them. `slice[index]`
  on a raw `i32` slice computes the index into `slot`, then loads the
  element over it. A `match` (`EMatch`, which names the enum type and the
  result type) computes the scrutinee into `slot`; the arm its tag picks binds
  the payload and computes its value from `slot + max(enum size, result
  size)`, which is then copied down to `slot`.
- Division (`EDivide`, in `LowerEval`): `/` and `%` on `i32` or one unsigned
  type. The mini IR divides in a statement, so division is only an
  effectful expression: both operands, then `Divide` into the left one's
  slot, on the low 32 bits for `i32` and on the whole word for the unsigned
  types. Core traps on a zero divisor and on the least `i32` divided by -1,
  exactly the cases where the mini division has no run (`eval_i32_div`,
  `eval_uint_div`; Core's `truncDiv` is `Int.tdiv`).

| file | lines | check (s) | role |
|---|---:|---:|---|
| `Source` | 497 | 1.2 | Core meaning of source programs and their declarations, value representation, `i32` wrap lemmas |
| `Unsigned` | 166 | 2.4 | unsigned arithmetic, comparisons and casts as slot arithmetic |
| `Shifts` | 109 | | Core's `<<` and `>>` (which trap outside the type's bits) as the mini IR's `shl`, `shr`, `sar` |
| `LowerExpr` | 685 | 5.1 | expressions |
| `Grows` | 1274 | 4.0 | Core's `nextAddress` never decreases; Core call and statement inversions |
| `HeapCorr` | 501 | 1.1 | Core heap to mini heap correspondence; allocate, load, store, free |
| `SliceLayout` | 341 | | one native word: its widths, Core's read and write of it, and the mini element address |
| `ElementLayout` | 627 | | slice elements of word types (structs and enums nested in any order): Core's words, field and payload offsets, reads (`FieldReads`) and writes (`FieldWrites`) |
| `LowerStmt` | 3626 | 9.4 | Core cells, frames, flat values, calls, enums and `match`, statements |
| `LowerEval` | 1430 | 1.8 | effectful expressions and their statements; the simulation by induction on fuel |
| `SourceCorrect` | 104 | 0.7 | top-level theorem |
| `Determinism` | 122 | 1.1 | both top-level theorems for every run of the same length, through the optimizer (step 14) |
| `TypeSound` | 2367 | 4.1 | type checker soundness: an accepted program is well typed in Core (step 7) |

The pass is about 1,880 lines of Lanius (the end of `compiler.lani`), and the
proofs are about 5,700 lines, plus 1,802 for type checker soundness. The per-function difftest covers it (146
functions, 2,920 calls after the unsigned types, run as two shards with
`--shard 0/2` and `1/2`, no differences; 11 native stack overflows on huge
random counts; types nested through `List` render through a `mutual` block of
`partial def`s; after the front-pass heap, 157 functions and 3,140 calls,
no differences, 9 native stack overflows; after struct slices, 204 functions and 4,080 calls as three shards, no differences, 9 stack overflows and 3 `element_base` panics on huge random counts, where `times` checks for overflow); at 30 cases per function the harness is now too large for
laniusc on the laptop (a GPU buffer fails to allocate). Assumptions the theorem does not cover yet: Core
programs outside the subset, and traps and divergence (the theorem covers runs
that return). The source's type checker is sound for Core's typing rules
(step 7, below).

Type checker soundness (step 7, `Lanius/Mini/TypeSound.lean`): when the front
pass accepts a program, its Core meaning is well typed by Core's own rules,
`Lanius.Typing.ProgramWellTyped` (the judgment Core's checker
`checkProgramWellTyped` decides and the compiler boundaries use), with no
other premise:

```text
compileSource_wellTyped : compileSource sp = some binary → Typing.ProgramWellTyped sp.toCore
```

`sp.toCore` is the program `compileSource_correct` is about. Two of Core's
rules are checks of their own in `compile_source`, beside the lowering. (1)
Nominal types: Core looks struct and enum types up by id in the program's
declarations, but `SrcType.struct id fields` carries its fields inline.
`declare_program` threads a table of declarations through every parameter,
result and binding type and the types nested in them, adding an id the first
time it appears and rejecting the program when a later appearance gives the
same id other fields or variants (`types_same`); `SrcProgram.toCore` emits the
table as Core's `structures` and `enumerations`. The proof: the table only
grows, and every type it has passed is declared in a Core program holding
the final table (`SrcType.declare_sound`, one mutual lemma per type list,
then statements, parameters and functions); `declareProgram_declared`
concludes `sp.Declared sp.toCore`. (2) Returns: Core requires a function with
a non-unit result to end in `return` on every path (`DefinitelyReturns`,
where a `while` never counts); `compile_source` requires `SrcStmt.returns` of
every function body, which `returns_sound` proves is that rule. Everything
else matches the lowering's own checks: operators, casts, literals (unsigned
ones in range, alignments `2^shift` with `shift < 32`), shadowing (the
scope's innermost binding is Core's last `Context.bind`, for parameters and
match binders too), calls (function `i` is the `i`th signature), field reads
and writes, and exhaustive non-empty `match`. The proof is one lemma per
lowering function, by induction on the syntax. Two programs show each check
is needed: `idClash` uses struct id 0 with fields `[i32]` and with `[bool]`,
and `noReturn` is `fn f() -> i32 {}`. The lowering alone accepts both, Core
rejects both whatever declarations they are given (`idClash_not_wellTyped`,
`noReturn_not_wellTyped`), and `compileSource` rejects both
(`idClash_rejected`, `noReturn_rejected`, by `rfl`).

### Separate compilation and linking (step 9)

A module (`Module` in `compiler.lani`) is a list of mini functions and the
functions it imports. Inside a module, callee `c` below the module's function
count `own` is its own function `c`, and `own + i` is its import `i`. An
`Import` names its owner, the module that defines it, by its position in the
link order, a function by its position in that module, and the arity the
importing module compiles its calls against.

- `compile_module` compiles one module with nothing else in view: it runs
  `compile_funcs` against the module's own arity table (its functions', then
  its imports' declared arities), lays the functions out in module offsets,
  and encodes each into object code. An `Object` holds the module's
  exports (its arities), its imports, and per function its frame slots and a
  list of `Piece`s: literal bytes, or `Rel(i)`, the 4-byte rel32 field of a
  call to import `i`, left as a hole. A call inside the module is already
  bytes: a module's functions stay together, so the distance between two of
  them is known when it is compiled, and a rel32 field depends only on that
  distance.
- `link_objects` checks every import against the objects' exports (the owner
  exists, has the function, and the function has the declared arity), lays
  the objects out back to back in order, renders each piece at its image
  offset (a hole at offset `p` becomes `le32(relative(p + 4, entry))` with
  the import's entry), and checks the image limit. It gives an `Executable`:
  each function's frame slots, the entries and the image.
- `link_program` says what a list of modules means: one mini program of all
  their functions in link order, each call renamed (`Stmt.rename`) to a
  program index. Own function `c` of the module whose first function is
  program function `first` becomes `first + c`; import `i` becomes its
  owner's first function plus its function index; a callee past the table
  becomes the program's function count, which no function has. It is `none`
  when an import fails the linker's check.

The theorem, `Lanius/Mini/Link.lean`, is an equality of `Option`s, so
separate compilation also fails exactly when compiling the whole program
fails:

```text
link_eq : (compileModules ms).bind linkObjects
            = ((linkProgram ms).bind compileProgram).map Binary.executable
```

`Binary.executable` keeps a binary's frame slots, entries and image (the
abstract `codes` of a `Binary` exist only for the proofs). `linked_correct`
is `compileProgram_correct` for a linked executable, with the same premises
read off the executable (`exe.image`, `exe.entries`, `exe.stackNeed`, equal
to the binary's) and `prog.Returns` for `linkProgram ms = some prog`;
`linked_deterministic` is `compileProgram_deterministic` the same way. There
are no new premises. `link_eq` depends on `propext` and `Quot.sound`; the two
corollaries on the standard three.

The proof has two layers.

- Code (`compileFunc_rename`, `table_agrees`, `resolve_compile`): renaming
  callees commutes with `compileStmt` (only `call` instructions change, and
  their sizes do not) and keeps `within`, provided the program's arity at
  every renamed callee is the module's arity at the callee. That holds when
  the module's imports check out: own callees sit at `first + c` in the
  program's arity list, an import's callee has its owner's arity there, which
  the check made the declared one, and a callee past the table has no arity
  on either side. By induction over the modules, `compileModules` fails
  exactly when `compileFuncs` of the program does, and otherwise the
  program's codes are each module's local codes, renamed, back to back
  (`Agrees`).
- Bytes (`Instr.pieces_render`, `objectFuncs_render`, `Agrees.bytes`): a
  module's pieces, rendered at the module's image offset, are `linkFrom` of
  its renamed codes. Non-call instructions do not depend on where they are
  placed; a call inside the module has the same rel32 field at module
  offsets as at image offsets (`relative_shift`); a hole's field is the
  call's field, since the linker's target is the program entry of the
  renamed callee. The layout and the frame slots agree the same way, and
  the linker's import check is the program's.

The linker is about 350 lines of Lanius (with comments) in the back end of
`compiler.lani`, extracted into `Compiler.lean` (256 lines); the proof is
674 lines and checks in 1.4 s.

Test, Lean only:

```bash
python3 -I formal/tools/link_difftest.py target/claude-work/link --count 1000 --seed 9
```

It generates random lists of 1 to 4 modules of 1 to 3 functions (bodies from
`mini_difftest.py`'s generator, against each module's own callee numbering),
with random imports between them, including from a module to itself, and
most functions calling one of their imports. A quarter are broken: an import
with the wrong arity, naming a missing module or function, a call past the
module's callees, or an ill-formed function. For each it evaluates both
sides of `link_eq` with `#eval` and compares them. 2026-10-21, seeds 9 and
10: 2,000 programs (5,058 modules), 1,353 linked, 647 rejected by both,
1,356,524 image bytes, 3,492 holes filled, no differences.

laniusc builds the linker: `fn_difftest.py` (299 functions, 5,980 calls as
four shards) finds no differences from the extracted Lean, including the new
module, object and linker functions. Not run yet: a `mini_difftest.py` mode
that compiles modules natively and compares linked images byte for byte with
`#eval`. Modules in the front pass (named imports, Core's own module
structure) are not done; this step is at the mini IR level.

### The verified compiler as an oracle for laniusc (step 12)

```bash
python3 -I formal/tools/oracle_difftest.py target/claude-work/oracle --count 300 --seed 12
```

It generates random source programs in the front pass's subset: `i32`,
`bool`, `u8`, `u32`, `u64` and `usize` values, structs and enums of those
(fields and payloads may also be earlier structs, nested),
literals, locals, fields, the operators, casts, `let`, assignment and field
assignment, variants, `match`, `if`, bounded `while` loops, calls to later
functions (so every run ends) and `return`. The entry function also allocates
up to two blocks and views each as a raw slice the way Core lays it out:
`i32` elements packed up from the pointer, word structs and word enums as
descending words from `p + top`. It writes every element, then reads and
writes them at literal indices anywhere in the body. Each program is compiled twice: by
`compileSource` under `#eval`, whose image runs natively in this process (a
stub sets r12-r14 with the cursor at 1, as the top theorem assumes), and by
laniusc, from the same program printed as Lanius with a `main` that writes
each result. A Python interpreter of the programs gives a third answer, so a
disagreement shows which side is wrong. `--only K` reruns one program.

2026-10-21: 2,300 programs, 18,400 calls, no disagreements and no rejections.
The first unsigned run reported 7 disagreements; the interpreter sided with
laniusc, and the cause was the harness, which masked 64-bit arguments to 32
bits before the call.

With heap and slice programs: 320 programs, 2,560 calls, no disagreements.

Effectful expressions (`EFFECTS`, off in `frontend_difftest.py`): calls
nested anywhere in an expression, in `let`, assignment, `if` and `while`
conditions, `return` and as bare call statements (`Discard`); `/` and `%`
with divisors that cannot trap (`(d | 1)`, and `(d | 1) & -3` for `i32`);
struct and enum literals with such fields; `s[i]` (`EIndex`) of a slice of
`i32`, of word structs or of word enums (as `let`, assignment and return
values, arguments and `match` scrutinees) at an `i32` or `usize` index that
may call, kept in bounds as a literal,
`e & (n - 1)` or a nonnegative `e % n`; `match` expressions (`EMatch`) of
any type in any of those places, on a call, an enum literal, a local or
another match, with arms that use their binders and may call, index and
match; `s[i] = value` (`SetIndexEval`) of a slice of `i32`, word structs or
word enums with an effectful index and value (for structs and enums a
literal, a call, a `match` or, often, another slice's element: `to[i] =
from[j]`), often a value that calls a function writing `s` at the same
literal index, so the store (after the value in Core's order) must win;
`x.f = value` (`SetFieldEval`) of a scalar field of a struct local (a
parameter or a local) with an effectful value; unit functions (no `-> T`,
mostly writing a slice they are passed), called as statements, ending
without a return or with `return;`, also early inside `if` and `while`;
`assert` with conditions that always hold (`c || true`, `c || !c` on a pure
`c`, `(e & 255) >= 0`, `(e % 7) < 7`), since the verified compiler's image
does not trap on a false assert (the theorem covers runs that return) and
laniusc's does; and later functions with struct,
enum and slice parameters and struct and enum results. A function with a
slice parameter writes into its caller's slice, the right side of `&&` and
`||` often calls one, and the entry's result folds in every element of its
slices, so Core's order (left before right, arguments left to right, short
circuit) shows in the result: with the interpreter changed to evaluate both
sides of `&&` and `||`, 15 of 1,000 generated programs give other results, and
with right-to-left evaluation 6. `while` conditions are `counter < bound && c`
in either order, so loops stay bounded. 2026-10-21, seeds 51-56 with
indexing: 1,800 programs, 14,400 calls, no disagreements and no rejections.
The programs hold 1,712 indexings, 3,524 calls in expressions, 3,772
divisions, 1,266 struct and enum literals and 8,455 Eval statements (2,142
`let`, 639 assignments, 1,018 `if`, 992 `while`, 4,004 `return`, 660 bare
calls). The same seeds before indexing: 1,800 programs, 14,400 calls, no
disagreements. With `match`, seeds 51-56 again: 1,800 programs, 14,400 calls,
no disagreements and no rejections, with 2,878 `match` expressions. With
`SetIndexEval`, seeds 51-56 again: 1,800 programs, 14,400 calls, no
disagreements and no rejections; 529 such stores, of which 305 runs had the
value's call write the very element stored (with the value's write winning
instead, 19 programs would give other results). With word struct and
enum element reads, seeds 51-54: 1,200 programs, 9,600 calls, no
disagreements and no rejections. With their writes, seeds 51-54 again: the
same counts, no disagreements and no rejections (about 70 struct and enum
element stores per 300 programs). With `SetFieldEval`, seeds 51-54 again:
1,200 programs, 9,600 calls, no disagreements and no rejections (about 110
field stores per 300 programs). With unit functions, `return;` and
`assert`, seeds 51-54 again: 1,200 programs, 9,600 calls, no disagreements
and no rejections, after one laniusc bug: a call to a unit function whose
body is empty (`fn f(v0: i32) {}` called as `f(3);` from `main`) failed with
LNC0057 "compiler execution failed" while generating target output. An empty
body owned no LIR rows, so laniusc registered no target function for it; it
now lowers as a bare `return;`, and the generator makes empty bodies again
(seeds 51-52: 600 programs, 4,800 calls, no disagreements). With `isize`
(locals, parameters, results, fields, payloads, the operators, unary minus,
signed order and the casts, values near 2^63 included; literals are
`.cast .isize (.int n)`, and laniusc also gets bare ones such as `x + 5`),
seeds 61-64: 1,200 programs, 9,600 calls, no disagreements and no
rejections. laniusc wraps isize arithmetic at 64 bits and does not trap on
overflow, as Core and the reference interpreter do. The entry's result folds
in an isize's low and high 32 bits and a signed comparison; about a quarter
of the programs then answer differently if isize order is taken unsigned,
and a deliberately unsigned laniusc side gives 363 disagreements in 800
calls.

Boxes (`BOXES`, 10-22; off without `NESTED`, so off in
`frontend_difftest.py`): half the programs get one or two box structs, the
shape of the mini compiler's own `Box<T>` and `List<T>`: one `ptr` field,
pointing at a block that holds one value of the box's target type. A target
is a new enum whose payloads hold boxes of itself (a list's `Cons(x, Box)`,
a tree's `Node(Box, x, Box)`, beside a variant without boxes), or a type
declared earlier (`i32`, a struct, an enum, another box). The entry makes
boxes as `boxed<T>` does: `alloc`, a one-element raw view of the block (an
`i32` at its start, any other type's word 0 at its top word), element 0
written, the pointer stored in the struct. So slice elements hold enums
holding structs holding pointers, at Core's layout, and the boxes are
copied, matched on, passed and returned like any struct. The entry's result
follows each box local as `unbox` does (a second view of the same block,
element 0 read): the leaves of the value, then each box in its payloads,
taken out by a `match`, its pointer compared (`==`) with another box's, and
followed, to depth 2. Pointers never reach the result directly (the two
compilers' heaps differ). Later functions that handle values holding boxes
are passed a box of each type they hold and copy those; only the entry's
top level allocates. The reference interpreter gives each allocation its
views by start, element type and length, so two views of one block share
their elements. With the stores into the boxes left out of the laniusc side
only, its programs fault on the first unbox (a null pointer read back), so
the result does see what the boxes hold. Seeds 501, 503, 504, 506, 507
(40 + 4 × 300): 1,240 programs (at least 594 with boxes), 9,920 calls, no
disagreements and no rejections. Seeds 502 and 505 stopped on laniusc syntax errors (LNC0016) in
programs without boxes: a `match` expression in an `if` or `while` condition
beside comparisons and shifts, rejected only after some earlier functions
(`target/claude-work/f9/repro/d3.lani` in the step 6 worktree fails at
31:1039; the same function alone, `c1.lani`, parses). Not yet reduced
further.

The stdlib half:

```bash
python3 -I formal/tools/stdlib_oracle.py target/claude-work/step12/full
```

It reads every module under `stdlib/` with a `module` line and its imports.
The targets are the pub top-level functions and the trait-impl methods whose
parameters and result are scalars or `Option` of a scalar (generics at
`i32`), plus `core::mem::size_of` at `i32`, `u8`, `bool` and a struct. Each
target gets a wrapper `fn w(...) -> i32` (an `Option` parameter is a flag
and a payload; a 64-bit result is compared as its low and high halves; a
trait method is called through a generic helper with a `where` clause). The
wrapper and its modules are parsed by laniusc, read by the front end and
compiled with `compileSource`; the image runs natively on 8 random
arguments, and laniusc builds the same wrappers into one harness program.
A function that doesn't read or compile gets a reason from its body and its
callees; `--modules a::b,c::d` limits the run.

2026-10-22, all 113 modules: 2,187 targets. 1,160 are outside the harness
(by type: u16 95, i8 73, i16 71, extern 63, slices at least 180, wide-integer
structs at least 114, str 41). Of the 1,027 testable ones, at first 281
compiled, 5 read but didn't compile and 741 didn't read (674 for type
aliases). After the type aliases, wide literals, null pointers, scalar
type methods and `!` arms below: 943 compile and run, 3 read but don't
compile, 81 don't read; 3,930 calls compared, no disagreements.

Why the rest don't read or compile (a target can count under several; the
counts include callers of a function that fails):

- shifts, 60: `<<`, `>>`, `<<=`, `>>=` (being added).
- extern callees, 30, and with them arrays, 13, and `for`, `loop`,
  `break`, `continue`, 7 (std's I/O, env, random and time wrappers).
- `core::mem::size_of` at `u8` and `bool`, 2 (compileSource): raw views of
  `u8` and `bool` elements, which the front pass does not have.
- `<isize as SaturatingAdd<isize>>::saturating_add`, 1 (compileSource),
  cause not yet found.

The per-function list is `unread.txt` in the work directory.

### Optimizer and validator (step 13)

The optimizer is not proved; a validator is. Both are Lanius code at the end
of `compiler.lani`, before `compile_declared`, and both are extracted.

- **Optimizer** (`optimize_program`, about 170 lines, marked NOT PROVED; no
  proof mentions it). Over the mini IR: folds constant subexpressions
  (`Word.compute`/`Word.test` give S32 and U64 arithmetic and comparisons on
  64-bit values); rewrites `x + 0`, `x - 0`, `x * 1`, `x & -1`, `x | 0`,
  `x ^ 0` and the commuted forms to `x` (for S32 only when `x` is narrow, that
  is zero-extended, since an S32 result is), and `x * 0`, `x & 0` to `0`; takes
  the branch of an `if` on a constant; drops `skip`, `x = x`, an `if` with two
  empty branches and a `while` whose condition is 0. It leaves each division
  in place (only its operands are optimized), so one that traps still traps.
  Along each sequence it propagates copies and constants: after `x = y` or
  `x = 5`, later reads of `x` read `y` or `5` until `x` or `y` is written
  (branches, loops and calls forget every fact). And it drops `x = e` when
  the optimized rest of the sequence kills `x`, that is writes it before
  reading it on every path, or returns without reading it.
- **Validator** (`validate original optimized`, about 590 lines, most of them
  exhaustive matches on the other statement). A structural walk of both
  programs: same functions with the same params, results and locals, and
  each optimized statement must agree with its original. Expressions agree
  when the optimized one is the literal that `Expr.constant` (a constant
  evaluator: literals, operations on constants, and `x * 0`, `x & 0`)
  computes for the original, or has the same shape with agreeing operands,
  or is the operand an identity keeps. Statements agree by shape, or when a
  statement that does nothing became `skip`, or an `if` on a constant
  became its branch, or both branches agree with the result. The walk
  carries a list of facts (slot = literal or slot) that hold on entry:
  `Stmt.factsAfter` computes them along a sequence, and each original
  expression is read with them substituted (`Expr.subst`) before it is
  compared. A sequence `x = e; rest` also agrees with `other` when
  `other.kills x` (`Stmt.kills`, with `Stmt.ignores` for "does not read")
  and `rest` agrees with `other` under the facts after `x = e`.
  The cases are tried in an order that keeps the walk polynomial
  (2026-10-25): the same shape first, then the dropped store, then a
  dropped statement on either side. Against `skip` the two dropped-statement
  cases of a sequence are one check, and with a constant condition "both
  branches agree" implies "the chosen branch agrees", so the second of each
  pair is guarded off (the guards change no result). Before, each level of a
  deep `Seq` nest checked its children against `skip` twice, and validating
  the verified compiler's own program (1,647 functions, one a 334,000-character
  table) did not finish in 2 hours; it now takes 0.7 s.
- **Pipeline** (`compile_optimized`): optimize, keep the result when
  `validate` accepts it and it compiles, and otherwise compile the original
  program. `compile_source` calls it.

`Lanius/Mini/Validate.lean` proves:

```text
Expr.agrees_eval          : a.agrees b = true → ∀ env, b.eval env = a.eval env
Exec.agrees               : funcsAgree p.funcs q.funcs = true → Exec p d env h s out →
                              ∀ facts s', Facts.Hold env facts → s.agrees facts s' = true →
                              Exec q d env h s' out
Exec.killed               : s.kills i = true → Exec p d env h s out →
                              ∀ env2, Env.Except i env env2 → Exec p d env2 h s out
Returns.validated         : validate p q = true → p.Returns d f args h v after → q.Returns d f args h v after
compileOptimized_correct  : compileProgram_correct's statement, with compileOptimized
```

`Exec.agrees` is induction on the original's derivation; a call uses the
induction hypothesis on the callee's body derivation, since the optimized
callee's body agrees with it (with no facts, as a loop body is).
`Expr.subst_eval` gives the substituted expression the original's value
where the facts hold, and `Stmt.factsAfter_hold` keeps them holding along a
sequence. For a dropped `x = e`, the induction hypothesis runs the optimized
rest from the state after `x = e`, and `Exec.killed` moves that run to the
state before it, which differs only at `x`; it uses `Exec.ignores` (a
statement that does not read `x` keeps two such states differing only at
`x`). The outcome (environment, heap, results) and
the call depth are the same, so the downstream theorem needs nothing new.
`compileSource_correct` keeps its statement and premises; its proof uses
`compileOptimized_correct` where it used `compileProgram_correct`, so the top
theorem covers the optimizing pipeline. S32 constant folding needed the
low-half lemmas (`low (op a b) = op (low a) (low b)`, `a & 0xFFFFFFFF =
widen (low a)`) and a signed-order key: `signedKey a = (a + 2^31) & 0xFFFFFFFF`
orders unsigned exactly as `low a` orders signed (`key_lt`, `key_le`). Axioms:
`propext`, `Classical.choice`, `Quot.sound` for `compileSource_correct`,
`compileOptimized_correct` and `Returns.validated`.

| file | lines | check (s) | role |
|---|---:|---:|---|
| `Validate` | 1057 | 1.7 | word arithmetic, constants and identities, facts and dead slots, expression and statement simulation, the pipeline theorem |

The test:

```bash
python3 -I formal/tools/optimize_test.py target/claude-work/opt/run --count 1000 --seed 2
```

It generates mini IR programs (`mini_difftest.py`'s generator, well-formed
ones) and source programs (`oracle_difftest.py`'s), lowers the source ones
with `lowerFuncs`, and for each reports under `#eval` whether the optimizer
changed it and whether `validate` accepts the change, with image sizes with
and without it. A mutant of each optimized program (every literal plus one)
must be rejected. The source programs are also compiled by `compileSource`
and run natively against `oracle_difftest.py`'s reference interpreter.
laniusc is not used. 2026-10-21, seed 2, 1,000 of each:

| programs | changed | accepted | image bytes | mutants rejected |
|---|---:|---:|---:|---:|
| mini IR | 653 | 653 (100%) | 403,475 to 366,368 (9.2% smaller) | 890 / 890 |
| front pass | 910 | 910 (100%) | 1,680,756 to 931,535 (44.6% smaller) | 965 / 965 |

and 8,000 native calls of the optimized `compileSource` images, no
disagreements with the reference. The front pass gains more because its
casts, masks and literal operands lower to constant subexpressions.

With copy and constant propagation and dead stores (2026-10-22, seed 2,
1,000 of each; the generators have grown since, so the unoptimized sizes
differ from the table above), on the same programs:

| programs | unoptimized | first pass | both passes | mutants rejected |
|---|---:|---:|---:|---:|
| mini IR | 395,509 | 362,767 | 360,995 | 899 / 899 |
| front pass | 6,611,872 | 4,722,125 | 4,165,929 (11.8% under the first pass) | 1,000 / 1,000 |

Every change accepted (661 and 998), and 8,000 native calls agree with the
reference.

laniusc builds the new Lanius code: `fn_difftest.py` (265 functions, 5,300
calls as four shards) finds no differences from the extracted Lean, and
`oracle_difftest.py` (300 programs, 2,400 calls) finds no disagreements
between the optimized images, laniusc and the reference interpreter.

### The front end by translation validation (step 8)

Source text gets a `SrcProgram` without a parser proof. laniusc parses the
file on the GPU, and the verified compiler checks its tree:

```text
sourceProgram source prods parents : Option SrcProgram
```

`prods` is laniusc's parse tree as its production ids in preorder (the
`node_kind` array) and `parents` is each node's parent index.
`lexTokens` lexes `source` with the Lean lexer (`lexCanonical`). Then
`validate_tree` follows `prods` against the grammar. It matches each terminal on a
production's right side with the next token, checks that each node's
production has the expected left side and its recorded parent, and builds a
concrete tree (`CTree`) whose leaves are the tokens. One exception: laniusc's
parser reads the `>>` that closes two type argument lists (`H<H<i32>>`) as
two `>`, so a `>` terminal may take the first half of a `>>` token, and the
second half is then the next token. `build` reads the program off the
concrete tree. It rejects anything outside the front pass's subset, and it
resolves names to numbers:
- a function is its position among the functions;
- a struct or enum is its position among the type declarations;
- a local is the byte offset of its binding from the function's name (so an
  edit to one function renumbers no other function's locals).

With generics these positions are positions in the instance tables (see
below). `sourceProgramFiles` takes several files, each a module, the
program's own first; `sourceProgram` is the one-file case.

| file | lines | check (s) | role |
|---|---:|---:|---|
| `Frontend` | 5513 | 15 | extracted from `formal/lani/mini/frontend.lani`: the grammar table, `validate_tree`, `build`, the monomorphizer |
| `FrontLex` | 59 | 0.6 | tokens from the Lean lexer; `sourceProgram`, `sourceProgramFiles` |
| `FrontSpec` | 354 | 0.9 | `CTree.leaves`, `CTree.preorder`, `Shape`, `Derives`, `Reads`; `validate_sound`, `sourceProgram_sound`, `sourceProgramFiles_sound` |

Proved, with only `propext` and `Quot.sound`:

- `validate_sound`: when `validateTree g tokens prods parents = some root`, then
  `Shape g 0 root` (a parse tree of `file`), `Reads root.leaves tokens []`
  (its leaves are the tokens, with some `>>` read as two `>`) and
  `root.preorder = prods` (it is laniusc's tree).
- `validate_derives`: the leaves' token kinds are derived from `file`.
- `sourceProgram_sound`: the program is `build` of such a tree for the tokens
  of `source`.
- `sourceProgramFiles_sound`: the program is `buildFiles` of one such tree per
  file.

laniusc's lexer and parser are not trusted. The trusted parts are the Lean
lexer, the grammar table, the grammar's unambiguity (not proved) and `build`
as the meaning of the concrete syntax. TRUSTED_BASE.md section 4 lists them.

`frontend.lani` is about 7,050 hand-written lines, followed by the generated
grammar table: 324 productions, with terminals as lexer token codes. Two
tools regenerate it:

```bash
python3 formal/tools/grammar_table.py formal/lani/mini/frontend.lani
python3 formal/tools/extract.py formal/lani/mini/frontend.lani formal/Lanius/Mini/Frontend.lean
```

Both take `--check`. The source types and list operations sit in an
`// extract: external` section. `extract.py` checks that section against
`compiler.lani` and emits `import Lanius.Mini.Compiler` instead, so the front
end builds `Compiler.lean`'s own `SrcProgram`.

The test:

```bash
python3 -I formal/tools/frontend_difftest.py target/claude-work/frontend/dt --count 100 --seed 1
```

It generates programs with `oracle_difftest.py`'s generator and prints them
as Lanius, 25 to a file, with uint literals of 2^31 and above built from
16-bit pieces. laniusc parses each file under `heavy`. The tree is captured
after `parser/tree/parent_parallel` and the lexer's tokens are dumped. Under
`#eval`, the front end must give exactly the program the text was printed
from, and the Lean lexer's tokens must equal laniusc's. The test also mutates
the trees and the sources and expects every mutant to be rejected: a
production id, a parent or one `+` is changed.

2026-10-21: 400 programs (seeds 1 and 2), 292,000 tokens and 2.4 million
tree nodes. Every file was read as expected, the lexers agreed on every
token, and 132 of 132 mutants were rejected. 300 programs take about 4
minutes, almost all of it in the Lean lexer under `#eval`. Comparing
`SrcProgram`s as elaborated Lean terms was much slower, so the test compares
a printed form of the programs instead.

2026-10-21, with the heap and slice constructs back in the generator
(`oracle.SLICES`, half the allocations freed with `dealloc`) and every other
`x = x op e` printed as `x op= e`: 400 programs (seeds 1 and 2), 248,000
tokens and 2.1 million tree nodes, all read as expected, no lexer
disagreements, 48 of 48 mutants rejected.

laniusc also compiles `frontend.lani` itself: with the module line changed and a
`main` that returns the grammar's length, the binary exits with 318 mod 256.
A native difftest of `front_end` is not written yet.

It reads the heap and raw slice constructs: `alloc::allocator::alloc(size,
align)` in a `let` of type `ptr` is `LetAlloc` and `alloc::allocator::dealloc(p,
size, align);` is `Free`, with the alignment a literal power of two (its
exponent is the shift); `slice_from_raw_parts(p, n)` in a `let` of type `[T]`
is `LetSlice`; `let x: T = s[i];` is `LetIndex` and `s[i] = v;` is
`SetIndex`. `p + n` and `p - n` are ordinary `Apply`s. The stdlib has no
byte load or store function, so `LetLoad` and `SetByte` have no spelling.
Compound assignments `x op= e` and `x.f op= e`, for `+ - * & | ^`, read as
`x = x op e` and `x.f = x.f op e`.

Generics, modules, constants and methods. Each file is a module, named by
its `module a::b;` item (the empty path without one). A path `a::b::x` names
`x` of module `a::b`; a bare `x` names `x` of the current module. An
`import m;` item only adds m's variants to those a bare variant name may
mean; traits, type aliases and extern functions are skipped. Generic structs,
enums and functions are monomorphized by `mono`, a worklist of instances, each
a declaration with its type arguments:
- the roots are the first file's functions without type parameters, in order,
  so a program without generics keeps its function numbers;
- reading an instance's body (with its type parameters standing for its
  arguments) adds the instances it calls that are new, numbered in the order
  they are first requested;
- the type table is the first file's non-generic types in order, then each
  instance as the functions' types (parameters, result, then the body's
  lets in order) first need it, the instance before its field types.

A call's type arguments are written (`f<i32>(x)`) or inferred: the callee's
parameter types are matched with the argument types and its result type with
the type of the `let` (or the assigned local). Methods of `impl` blocks take
`self` by value and are called as `x.m(args)` (`x` a local) or `T::m(args)`
(`T` a type parameter); the method is the one whose impl type matches the
receiver's type, and two matches are rejected. Bounds and `where` clauses on
functions are ignored. A constant (`const K: u8 = 15;`) is replaced by its
value, which must be a literal of its type: an `i32` constant is `Int`, an
unsigned one `Unsigned`, an `isize` one `Cast(Isize, Int(n))`. A constant
whose value is a literal of 2^31 or more (its tokens are `n` or `-` `n`) is
the declared type's literal of that value: `Int` for `i32` (only
`-2147483648`), `Unsigned` up to the type's largest value, and for `isize`
the cast of the `u64` literal holding its two's complement bits (as the
oracle writes them). Anything else (an expression, a value out of range) is
rejected where the constant is used. A local may not be spelled like a
type, variant or constant of its module (a function, since 10-22, it may). The case `constants`
reads `stdlib/std/vec.lani`'s three constants as written there (in a
module `std::vec`): `MAX_CAPACITY: i32 = 2147483647` is `Int(2147483647)`,
`MAX_BYTES: usize = 2147483647` is `Unsigned(Usize, 2147483647)` and
`ALIGN: usize = 8` is `Unsigned(Usize, 8)`; it also has `-2147483648`,
`u64` and `u32` values past 2^31, and both `isize` extremes.
`reject_const_range` rejects `const BIG: i32 = 2147483648;`.

Two more tests. `--generic` takes each generated program and abstracts it:
about half the structs, enums and functions get a type parameter standing for
one of their types (uses write the type as an argument, or leave a call's to
inference), about a quarter of the types and functions (and half the constants)
move to a second file, the module `gen::lib`, with qualified paths both ways, some literals become constants,
and half the functions start with a call of a generic identity function at
one of their parameter types. The script numbers the expected program the
way `mono` does, and the front end must give exactly it. `--cases DIR` runs
the hand-written cases in `formal/tools/frontend_cases`: each is a program
(one or more files) and either a monomorphic copy written by hand, which must
read as the same program up to local ids, or a mark that it must be rejected
(an ambiguous method, a wrong type argument count, a duplicate name, an
inference conflict, a local spelled like a constant).

A file with `import m;` lines makes laniusc load the imported modules and
capture the tree of the whole program, so the script gives laniusc a copy
with those lines blanked to spaces and puts each import's subtree (`item ->
import_item`, `import -> 'Import' import_tail`, `import_tail -> path ';'`,
the path's segments) back into the item list where the line was. The front
end validates the result against the tokens of the file as written, so a
wrong splice is rejected; only the comparison with laniusc's own token dump
leaves out the import lines' tokens. The import lines must come together,
first in the file or right after its `module` line. The case `imports` has
one, and its second file, `stdlib/core/option.lani` as it is, has three.

2026-10-21, after the generics: 400 programs (seeds 1 and 2) read as before;
with `--generic`, 400 programs (seeds 1 and 2), 276,000 tokens and 2.1
million tree nodes, 694 declarations made generic, 917 moved to `gen::lib`
and 688 literals written as constants, all read as expected, no lexer
disagreements, 48 of 48 mutants rejected; 12 of 12 hand-written cases pass.

Effectful expressions. An expression that calls a function, indexes a
slice, divides (`/`, `%`), or is a struct literal, a variant or a `match` is
read as a `SrcEff`, and its statement takes the effectful form: `LetEval`,
`SetEval`, `SetFieldEval`, `IfEval`, `WhileEval`, `ReturnEval`, `SetIndexEval`, or
`Discard` for a call statement `f(x);`. Two things keep the old forms, so
programs read before still read the same:
- an expression with none of these inside is pure (`EPure`), and so are
  operators, casts and negations of pure operands: `(f(x) + 1) * 2` is
  `EApply(times, EApply(plus, ECall .., EPure 1), EPure 2)`;
- a statement that has a form of its own keeps it: `let x: T = f(a);` with
  pure arguments is `LetCall`, `x = f(a);` is `SetCall`, a `let` of a match
  on a local with pure arms is `LetMatch`, and pure struct literals,
  variants and `s[i]` in a `let` are `LetStruct`, `LetEnum` and `LetIndex`.

Type arguments inside expressions:
- a struct literal's or variant's come from the type its value is stored at
  (a `let`'s type, the assigned local's, the function's result type for
  `return`, or a parameter's type when the callee's type arguments are
  known), or else are inferred from the field or payload types;
- a call's are written, or inferred from the argument types and, when known,
  the stored-at type;
- a match's result type is the stored-at type, or else its first arm's.

`x op= e` with `e` effectful, and `x /= e` and `x %= e`, are `SetEval(x,
x op e)`. Reading the local `x` has no effect, so evaluating it before `e`
gives what Core's own compound form gives. Likewise `x.f = e` with `e`
effectful is `SetFieldEval(x, f, e)`, and `x.f op= e` (effectful `e`, or
`/=`, `%=`) is `SetFieldEval(x, f, x.f op e)`.

The difftest generates these with `oracle_difftest.py`'s `EFFECTS` (on except
with `--generic`): calls nested in operators, casts, `/` and `%`, struct and
enum literals with such fields, indexing at computed indices, `match`
expressions of any type on a call, literal, local or match, effectful `if`
and `while` conditions, returns and call statements, and struct, enum and
slice parameters and results. The script reads each expected statement the
same way: pure parts collapse, and a statement with a pure form keeps it.
Some `x = x op e` with `e` effectful are printed `x op= e`. The case
`effects` has generic calls inferred through effectful arguments, a variant
typed by a parameter and by the result type, methods inside expressions,
`/=` and `%=`, and an effectful slice store. `effectful_field` has effectful
field assignments, plain and compound, on a generic struct.

2026-10-21, with effectful expressions: 400 programs (seeds 1 and 2), 572,000
tokens and 5.0 million tree nodes, with 1,262 effectful statements (316
`LetEval`, 89 `SetEval`, 122 `IfEval`, 70 `WhileEval`, 513 `ReturnEval`,
152 `Discard`) holding 813 calls, 627 matches, 832 divisions, 420 slice
indexings, 182 struct literals and 321 variants. All read as expected, no
lexer disagreements, 48 of 48 mutants rejected. `--generic` (seeds 1 and 2)
and the programs without effects read as before, and 14 of 14 hand-written
cases pass.

2026-10-22, with the oracle's effectful slice stores (`s[i] = v` on slices of
`i32`, word structs and word enums, `to[i] = from[j]`) and `SetFieldEval`:
seeds 11 and 12, 400 programs, 571,000 tokens and 5.0 million tree nodes,
191 `SetIndexEval` and 645 slice reads in expressions, all read as expected,
48 of 48 mutants rejected; `--generic` seed 11 as before; 14 of 14 cases
(`effectful_field` reads 5 `SetFieldEval`s). The generator does not make
`SetFieldEval` yet.

Unit functions, `return;` and `assert`. A function without `-> T`, or with
`-> !`, has result type `Unit`, and its body may end without a return.
`return;` is `ReturnUnit`. `assert(c);` (the spelling `assert`, one
argument) is `Assert(c)`, with `c` collapsed to `EPure` when pure. A call
statement of a unit function is `Discard(ECall ..)`, like any discarded call.
So `core::panic::panic()` is read from `stdlib/core/panic.lani` as it is: a
unit function (`-> !`) whose body is `assert(false);`. The case `unit_fns`
has all of these, with that file as the program's second file. Results,
2026-10-22: seeds 11 and 12, 400 programs, all read as expected, 48/48
mutants rejected; `--generic` seed 11, 200 programs, all read, 24/24
rejected; 15 hand-written cases pass. The oracle's generator now makes
unit functions, `return;`, `if c { return; }` and `assert`, in the forms
the script prints.

`isize`. The type `isize` is `SrcType.Isize`; operators, comparisons,
unary minus and `as` to and from `isize` read as for `i32`. laniusc gives
an integer literal the type its context expects, and for `isize` the reading
does too: after monomorphization a pass (`lit_funcs`) walks every function
with the types of its locals, fields, parameters and callees, and an integer
literal whose expected type is `isize` becomes `Cast(Isize, Int(n))`. The
expected types are a `let`'s type, the type of the local, field or slice
element stored to, a parameter's, the result type for `return`, a field's or
payload's in a literal, a match's result type for its arms, and `Bool` for
conditions and `assert`. An operator's operands expect the type of whichever
operand has one, else (for arithmetic) the operator's expected type; the
operand of `as` and the heap operations' operands expect nothing, so their
literals stay `i32`. Literals of 2^31 and above are rejected, as for `i32`.
A literal argument of a generic call takes its parameter's type (see the
type argument inference below), so `unwrap_or(wrap(r), 0)` with `r: isize`
is `unwrap_or<isize>`. The
cases `isize` (its `want.lani` writes every literal as `(n as isize)`) and
`reject_isize_big` test this. Results, 2026-10-22, with the oracle's unit
functions and `assert` on: seeds 17 and 18, 400 programs (at seed 17, 162
`return;`, 128 `assert`s and 192 unit functions), all read as expected,
48/48 mutants rejected; `--generic` seed 11 as before; 17 of 17 cases.

Then with the oracle's `isize` on. The script writes an `isize` literal as
the oracle means it: `(n as isize)` below 2^31 in magnitude, a bare `n` beside
an operand whose type laniusc knows (`x + 5`), and past that the cast of a
`u64` literal with the same bits, built from 16-bit pieces as the unsigned
literals are. It expects what that text reads as: a bare literal is typed by
its context, so its integer literals are `.cast .isize`. An effectful
expression that reads as a pure one is printed as the pure one, so the same
rule decides bare literals in both. Since a bare literal can now be an
operator's left operand, the type that type argument inference gives an
operator comes from its other operand when the left one is only literals.
Seeds 11 and 12, 400 programs, 7,692 `as isize` and 1,266 `isize` lets and
parameters, all read as expected, 48/48 mutants rejected; `--generic` seeds
11 and 12, 400 programs, 48/48; 19 of 19 cases.

`slice_stride(x)` with `x` a slice local is `EStride(x)`, an `isize`; any
other argument is rejected. So `core::mem::size_of<T>()` reads from
`stdlib/core/mem.lani` as it is, one instance per `T` after monomorphization
(the case `slice_stride`, at `i32`, a struct and `u8`). Its
`let nowhere: ptr = 0;` reads as `Let(.., Ptr, Int(0))`. With the oracle's
`eStride` on, seeds 29 and 30, 400 programs (712 `slice_stride`s), all read
as expected, 48/48 mutants rejected; `--generic` seed 29, 200 programs,
24/24; 20 of 20 cases.

`return slice_from_raw_parts(p, n);` in a function whose result is a slice
reads as a slice local and its return,
`LetSlice(id, el, p, n, Return(Local(id)))`; `id` is the offset of the
value's first token, which no binding has. An integer literal whose expected
type is unsigned is now `Unsigned(u, n)` (the `8` in
`(length as usize) - 8`). So `typed_slice_from_storage` and
`typed_prefix_from_storage` read from `stdlib/core/mem.lani` as they are,
one instance per `T` (the case `slice_return`, at a struct and `i32`; the
prefix function's untyped call of `typed_slice_from_storage` gets its `T`
from the result type). A case directory holding a file named `compiles`
also checks that `compileSource` accepts the program read.
`slice_return_compiles` does: a generic function that returns a slice, at
`i32` and a struct, and a caller that indexes the result. `slice_return`
did not at first, because `compileSource` rejected `Let(.., Ptr, Int(0))`;
it compiles since `0` expected at `ptr` reads as `Null` (below). Results, 2026-10-22: seeds 31 and
32, 400 programs, all read as expected, 48/48 mutants rejected; `--generic`
seed 31, 200 programs, 24/24; 22 of 22 cases.

Variants are scoped by their enum. A bare `V` is the one variant spelled V
among the current module's enums, or else among the enums of the modules
the file imports (`import m;`); two candidates are rejected. `E::V` and
`m::E::V` name enum E's variant, values and patterns alike, and `m::V` is
module m's one variant V. So a module may have variants of one name in two
enums, or a variant spelled like a type; its functions, types and constants
must still have distinct names, and no variant may be spelled like a
function or constant.

Fields and methods of any value. A postfix chain may continue past its first
step: `q.p.x`, `mk(a).k`, `left.ty.is_i32()`, `unbox(l).within(locals)`. A
field of a local is `Field`. A field of any other value is a call of that
field's projection, `fn(v: T) -> F { return v.f; }`, a function instance
that `mono` adds like any other: its declaration number is the number of
declared functions plus the field's index, its one type argument T, and it
is numbered when it is first requested. A method's receiver may be any
value, passed as the call's first argument. Binding the value to a
temporary before the statement would move its effects ahead of the
statement's earlier ones, and has no place inside a `while` condition or a
match arm; a projection call keeps Core's order. A call whose arguments are
all pure keeps its statement form (`LetCall`, `SetCall`) however it is
reached. The case `chains` tests these, and compiles since the front pass
copies a struct local's aggregate field in an effectful expression
(`eval_field_copy`).

Type arguments from the expected type and the arguments in order. A generic
call's type parameters are bound first by matching its result type with the
type its value is stored at, then by each argument in order, and each
argument is read at its parameter's type once every type parameter is
bound. So `cons(x, empty())`, `core::option::unwrap_or(None, 5)` and an arm
`None -> empty()` read. An integer literal argument binds nothing, since
laniusc gives it its parameter's type: with `u: u8`, `same(u, 7)` is
`same<u8>` and its `7` is `Unsigned(U8, 7)`. If a type parameter is still
unbound after the arguments, the literals count as `i32`, as before. The
cases `infer_args` and `imports` test these.

Match arms in any order. A `match` needs one arm per variant, each variant
named by exactly one arm, and its arms are put in variant order (as
`SrcArm`s and `EMatch` values are indexed); only one arm runs, so the order
they are written in has no effect. `frontend.lani` writes `None -> ..` before
`Some(..) -> ..` throughout. The cases `arm_order` and `reject_arm_twice`.
Results, 2026-10-22, with all three: seeds 35 and 36, 400 programs, all read
as expected, 48/48 mutants rejected; `--generic` seed 35, 200 programs,
24/24; 27 of 27 cases (seeds 33 and 34 and `--generic` seed 33, before the
arm order, also all as expected).

A census of the mini compiler's own sources (step 11): laniusc parses each
file, import lines kept as above (`frontend.lani` with its `module` fields
and parameters renamed, since `module` is a keyword and laniusc rejects it
as a name), and the front end reads each function on its own, type
parameters at `i32`, with `core::option`, `core::mem`, `core::panic` and
`alloc::allocator` loaded. Functions read, 2026-10-22:

| front end | `compiler.lani` | `frontend.lani` |
|---|---|---|
| before the step 11 work | 145 of 442 | 279 of 757 |
| variants by enum, slice returns | 242 of 462 | 449 of 796 |
| fields and methods of any value, argument inference | 320 of 462 | 495 of 796 |
| match arms in any order | 431 of 462 | 784 of 796 |
| aliases, wide literals, locals spelled like functions | 469 of 471 | 869 of 869 |

The census of the last row (the sources as of 10-22, `frontend.lani` with
its new functions) reads every function but `le32` and `le64`, whose shifts
are being added separately. `wellNamed` holds for both files: variants are
scoped by their enum, and `Some`/`None` resolve to core::option's through
the import. With them loaded, core::option reads 15 of 21 (the rest need
core::result or the trait call `T::eq`), alloc::allocator 29 of 32 before
the `ptr` constant fix below, core::mem and core::panic all.

The whole of `compiler.lani`, with `le32`'s and `le64`'s shifts written as
divisions, now reads as one program with those four modules: 646 function
instances after monomorphization, every body ending in a return, the
declarations consistent. `compileSource` lowers all but 98 of them, every
one part of `Box<T>`: `boxed`, `unbox`, `core::mem::typed_slice_from_storage`
and `core::mem::size_of` at element types such as `Expr`, `Stmt`, `SrcType`
and `List<X>`, whose raw views hold enums inside enums (`List<X>`'s payload
is X and a `Box`). Enum fields and payloads in slice elements were the open
item of step 6. (Probe: `target/claude-work/census/Probe.lean` in the step
11 worktree.)

Re-measured on integ2 at 176c0d14 (10-22), after F8 stage 2 (any word type
as a slice element, enums nested anywhere) and with the shifts read as
written: the whole of `compiler.lani` (457 functions now) with the same four
modules reads as one program of 618 instances, every body ends in a return,
the declarations are consistent, `lowerFunc` accepts all 618, and
`compileSource` compiles the program. `Box<T>` at `Expr`, `Stmt`,
`SrcType`, `List<X>` and the rest lowers: its element types are word types
(the box is a struct of one `ptr`, `List<X>` an enum whose `Cons` payload
is X and that struct), so F8 stage 2's `word_type`/`load_type`/`store_type`
already cover them, and `size_of`'s probe view and `slice_stride` give
`8 × words`. No front pass or proof change was needed. (Probe:
`target/claude-work/f9/census/probe.sh` in the step 6 worktree, the step
11 probe's `Probe.lean` on laniusc's parse trees of the current files; it
takes about 2 minutes under `#eval`. The same probe on `frontend.lani` as
one program was stopped after 82 minutes without output, so that file is
still measured function by function only.)

Self-hosting (M11c, `tools/self_host.py`, gate steps `self-host` and, full
tier, `self-host-fixpoint`). `mini::selfhost` is `compiler.lani` followed by
the body of `frontend.lani`; `compileSource` of a driver over it is the
self-built verified compiler (11.0 MB of x86 in 1,672 functions, 2026-10-25).
Run natively on the front end's 64 case programs it gives the entries and
image bytes of Lean's `compileSource` and of laniusc's build of the same
driver. The fixpoint (10-25): run on its own source (the driver and the
eight modules, lexed, with laniusc's parse trees) it returns in about 105 s
exactly Lean's result, 11,032,230 words, whose image is its own image byte
for byte. What it took, measured with a sampling profiler and an
allocation tracer on the native run (`target/claude-work/q/dbg/run.c`):
- Heap. The bump allocator never frees, so the heap must hold everything
  the run allocates: first 4 GiB ran out in the front end (the trap), then
  12.3 GiB at `link`. `primitive` built its eight spellings as lists on
  every call (38% of the front end's allocation); the optimizer used the
  validator's `kill`, which rebuilds the whole fact list on every write (7
  GiB of the 12, half in the optimizer, half in the validator). Now
  `primitive` compares characters (`spelled0`..`spelled5`), the optimizer
  has its own `opt_facts_after`, whose `opt_kill` keeps the facts after the
  last one a write kills (same facts, shared tail), and the run allocates
  7.0 GiB. The validator's `kill` is unchanged (its proofs unfold it): 3.7
  GiB of the 7.
- Stack. `length` and `concat` over the 11M-byte image, and the driver's
  output loop, recurse once per byte: more than 1 GiB of stack (the second
  failure: SIGSEGV at the 1 GiB thread stack inside `link`'s `length`).
- Memory held. self_host.py runs each native run in a fork with a fresh
  2^36-byte heap and 2^33-byte stack, both `MAP_SHARED` on sparse files it
  has already unlinked, and the stub switches to that stack; all native
  runs happen in one child under a 4 GiB cgroup cap. The kernel writes
  pages out to the files instead of holding them, so the cap bounds what is
  resident (3.9 GiB at peak), not what is allocated.
- Time. The native code is about 40 times slower than Lean's compiled code
  on the front end. Comparing names before module paths in the lookups,
  passing over types whose instance the type table already holds
  (`type_table_more`, `ty_known`), and lowering each type instance once for
  the close phase (`Tables.lowered`, `close_ty`) took the run from 206 s
  (the first that returned) to 105 s, the front end's part from about 150 s
  to 50 s; Lean's compiled `frontEnd` on the same program went from 3.8 s
  to 0.6 s.
laniusc's build of the driver does not finish the fixpoint: its runtime's
`alloc` is one `mmap` per allocation (a page each), and the run makes on
the order of 10^8 allocations; under the cap it is killed after about 10 s.
It still gets every case program right. A laniusc small-object allocator
(roadmap step 3) is what remains for the three-way fixpoint.

Type aliases, wide literals, null pointers, `!` arms (10-22). Each closes a
gap the stdlib oracle or the census found:
- `type A<P..> = T;` (no `where` clause) is an alias: a type path that
  names no type parameter, primitive or declared type names the alias of
  its module (`m::A` another module's), read in the alias's module with its
  parameters standing for the arguments; a cast may name an alias of a
  scalar (`x as PathByte`). Alias names count with the module's type names
  for distinctness. A cycle runs out of fuel (`reject_alias_cycle`). Case
  `type_alias`.
- an integer literal of 2^31 to 2^64 - 1 outside a constant reads as a
  marker, `Cast(Unit, Unsigned(Uint64, n))` (no source cast names `Unit`),
  which `lit_funcs` gives its expected type: `Unsigned(u, n)` when n fits,
  the `u64` cast for `isize` below 2^63, `Int(-2^31)` for `-2147483648` at
  `i32`, the two's complement cast for `-n` at `isize`; a marker left
  untyped rejects the program (`wide_left_funcs`). Cases `wide_literals`,
  `reject_wide_i32`, and `reject_isize_big` (now 2^63 at `isize`).
- `0` expected at `ptr` (a `let`, an operand beside a `ptr`, a `ptr`
  constant) is `SrcExpr.Null`, new in the front pass: Core's `.pointer 0`,
  lowered to `Lit(0)` at `Ptr` (`lower_sound`, `lower_typed`, `lower_below`,
  `eval_state` cover it). So `core::mem::size_of` compiles at `i32` and a
  struct (`size_of_compiles`; at `u8` it needs raw `u8` views, which the
  front pass does not have) and `slice_return` compiles. Case
  `null_pointer`.
- a local may be spelled like a function (`let kid: CTree = kid(c, 0)`): a
  function is only named by a call. Case `local_like_fn`.
- `i32::hash(v)`: a path prefix that is a primitive type calls the method
  of the impl for that type, as for a type parameter. Case `scalar_method`.
- a match arm whose value calls a `-> !` function g (`None ->
  core::panic::panic()`), in a match of value type t, calls g's instance at
  t: an instance with one type argument more, whose body is `g(params);
  return self(params);`. Core traps in g, so the return is not reached; it
  gives the body a value of type t on every path. Case `panic_arm`
  (`core::option::unwrap`, which compiles).

What it does not read yet:
- shifts (being added) and `&self`, which have no `SrcProgram` form;
- `=>` match arms, and block or `if` arms;
- methods of generic impls called as `T::m` where `T` is not a type
  parameter (`Vec::new()`), and trait-generic code that relies on bounds;
- indexing a slice that is not a local.

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
`Lanius/Mini/Compiler.lean`, a Lean module importing the types
(`Compiler/Types.lean`) and the parts `Lanius/Mini/Compiler/P/<first
definition>.lean` (about 8 definitions each, the boundaries chosen by a hash
of the names so that adding a definition changes one part; bodies hidden from
other modules, and a part imports the parts its bodies name privately, so a
new definition does not rebuild what imports those). A module that unfolds
them lists them between `-- import all: Lanius.Mini.Compiler` and `-- end
import all`, and one that names them in its statements lists the names after
`-- import parts: Lanius.Mini.Compiler`; the extractor rewrites both blocks:

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
allocation and an alignment probe and passes 12,427 calls. After word loads and stores (`loadWord`, `storeWord`
with a width of 4 or 8 bytes, little-endian, x86 `mov` through r12): 201
programs, 54,000 image bytes, no differences; the native run adds a function
that stores and reloads 64- and 32-bit words, aligned and not, and passes
15,427 calls. The per-function
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
  programs now run in one binary in 39 MB. Every allocation is still one page,
  so laniusc's build cannot run the self-hosting fixpoint (about 10^8
  allocations); the self-built compiler's own bump allocator can (see the
  self-hosting paragraph of the front end section).

### Exclusive references: the `&mut` extraction pilot

`&mut T` and `&mut self` (phase S4 of `docs/memory-scoped-stacks-design.md`)
exist so that mutating code still extracts to pure functions. The pilot,
`formal/lani/mini/mut_pilot.lani`, is a small bank (`Account.deposit`,
`Account.withdraw`, `transfer`, `relay`, `paid`, `pay_all`). extract.py
translates it the way Aeneas translates Rust's mutable borrows:

```text
fn transfer(source: &mut Account, target: &mut Account, amount: u32) -> bool
def transfer (source : Account) (target : Account) (amount : BitVec 32) : Bool × Account × Account
```

- A function returns its result, then each `&mut` parameter's final value,
  in parameter order (just the values when it has no result).
- `x = e;` and `x.f.g = e;` become `let x := { x with f := ... }`.
- A call that passes `&mut` arguments is a statement or a `let`'s whole
  initializer: `let (moved, source) := Account.withdraw source amount`.
- A `&mut` argument is a bare local that no other argument of the call uses.
  laniusc rejects the same calls (LNC0006), so the translation is never asked
  to model an alias.

`Lanius/Mini/MutPilotCorrect.lean` proves seven facts about the extracted
definitions, among them that a transfer conserves the sum of the two
balances and that a relay's result is the total before it (`bv_omega`, no
`bv_decide`). Gate step `mut-pilot` runs `fn_difftest.py` on the pilot: each
case calls the function natively with references to locals, prints the result
and then each local, and compares that with the Lean tuple. 2026-10-27: 300
cases on seed 7 and 180 in the gate, no differences; one wrong `+ 1` in a
copy of `deposit` gives 40 mismatches in 60 cases.

Not covered: `&mut` into a field or an array element (`f(x.field)`: the
argument must be a bare local), and `&mut` in `compiler.lani`, which stays as
it is.
