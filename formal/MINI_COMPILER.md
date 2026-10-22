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
| `LowerExpr` | 685 | 5.1 | expressions |
| `Grows` | 1274 | 4.0 | Core's `nextAddress` never decreases; Core call and statement inversions |
| `HeapCorr` | 501 | 1.1 | Core heap to mini heap correspondence; allocate, load, store, free |
| `SliceLayout` | 601 | 6.3 | Core's native layout of word structs and enums; their field reads and the mini element address |
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
`bool`, `u8`, `u32`, `u64` and `usize` values, structs and enums of those,
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
struct and enum literals with such fields; `s[i]` of an `i32` slice (`EIndex`)
at an `i32` or `usize` index that may call, kept in bounds as a literal,
`e & (n - 1)` or a nonnegative `e % n`; `match` expressions (`EMatch`) of
any type in any of those places, on a call, an enum literal, a local or
another match, with arms that use their binders and may call, index and
match; `s[i] = value` (`SetIndexEval`) of an `i32` slice with an effectful
index and value, often a value that calls a function writing `s` at the same
literal index, so the store (after the value in Core's order) must win; and
later functions with struct,
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
instead, 19 programs would give other results).

Not covered yet: the stdlib, which needs generics and modules in the front
pass.

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
- **Validator** (`validate original optimized`, about 590 lines, most of them
  exhaustive matches on the other statement). A structural walk of both
  programs: same functions with the same params, results and locals, and
  each optimized statement must agree with its original. Expressions agree
  when the optimized one is the literal that `Expr.constant` (a constant
  evaluator: literals, operations on constants, and `x * 0`, `x & 0`)
  computes for the original, or has the same shape with agreeing operands,
  or is the operand an identity keeps. Statements agree by shape, or when a
  statement that does nothing became `skip`, or an `if` on a constant
  became its branch, or both branches agree with the result.
- **Pipeline** (`compile_optimized`): optimize, keep the result when
  `validate` accepts it and it compiles, and otherwise compile the original
  program. `compile_source` calls it.

`Lanius/Mini/Validate.lean` proves:

```text
Expr.agrees_eval          : a.agrees b = true → ∀ env, b.eval env = a.eval env
Exec.agrees               : funcsAgree p.funcs q.funcs = true → Exec p d env h s out →
                              ∀ s', s.agrees s' = true → Exec q d env h s' out
Returns.validated         : validate p q = true → p.Returns d f args h v after → q.Returns d f args h v after
compileOptimized_correct  : compileProgram_correct's statement, with compileOptimized
```

`Exec.agrees` is induction on the original's derivation; a call uses the
induction hypothesis on the callee's body derivation, since the optimized
callee's body agrees with it. The outcome (environment, heap, results) and
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
| `Validate` | 680 | 1.3 | word arithmetic, constants and identities, expression and statement simulation, the pipeline theorem |

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
- a local is the byte offset of its binding.

With generics these positions are positions in the instance tables (see
below). `sourceProgramFiles` takes several files, each a module, the
program's own first; `sourceProgram` is the one-file case.

| file | lines | check (s) | role |
|---|---:|---:|---|
| `Frontend` | 3485 | 9.3 | extracted from `formal/lani/mini/frontend.lani`: the grammar table, `validate_tree`, `build`, the monomorphizer |
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

`frontend.lani` is about 4,540 hand-written lines, followed by the generated
grammar table: 318 productions, with terminals as lexer token codes. Two
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
`x` of module `a::b`; a bare `x` names `x` of the current module. `import`
items, traits, type aliases and extern functions are skipped. Generic structs,
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
unsigned one `Unsigned`. A local may not be spelled like a function, type,
variant or constant of its module.

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

2026-10-21, after the generics: 400 programs (seeds 1 and 2) read as before;
with `--generic`, 400 programs (seeds 1 and 2), 276,000 tokens and 2.1
million tree nodes, 694 declarations made generic, 917 moved to `gen::lib`
and 688 literals written as constants, all read as expected, no lexer
disagreements, 48 of 48 mutants rejected; 12 of 12 hand-written cases pass.

What it does not read yet:
- calls inside expressions, unit functions (`core::panic::panic()`), `/`
  and `%`, shifts, `&self`, `isize` and `size_of<T>()`, which have no
  `SrcProgram` form;
- `=>` match arms, and block or `if` arms;
- integer literals of 2^31 and above (so `const MIN: i32 = -2147483648;`);
- methods of generic impls called as `T::m` where `T` is not a type
  parameter (`Vec::new()`), and trait-generic code that relies on bounds;
- struct literals or calls in `return`.

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
  programs now run in one binary in 39 MB. Every allocation is still one page;
  a small-object allocator matters once the verified compiler runs on itself.
