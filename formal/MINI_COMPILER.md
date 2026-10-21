# Mini compiler pilot

A small verified compiler, built the way the full verified compiler should be:
pure functions over algebraic data, proved in Lean by induction on syntax and
one simulation lemma per pass, against the existing x86 machine semantics.
It measures two things the earlier attempt could not keep under control: proof
size relative to the compiler, and Lean check time.

## Rules

- The compiler is pure: enums, structs, `std::vec::Vec<T>`, `Option`/`Result`,
  `match`, recursion, and a generic `Box<T>` for recursive syntax. No raw
  memory: no `slice_from_raw_parts`, no hand-computed record sizes, no packed
  word buffers. Allocation uses panicking operations, so a successful run never
  silently drops data.
- The Lean side is ordinary definitions with the same shape as the Lanius code
  (`Box<T>` is `T`, `Vec<T>` is `List T`, `i32` is `BitVec 32`). Proofs are
  about those definitions; nothing is executed inside the kernel.
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
∧ prog.Returns depth f args v       -- f returns v, calls nested < depth deep
∧ binary.image is loaded at imageBase, s.rip is f's entry
∧ argument k is at rsp - (8k + 16)  -- just below the return address
∧ window ≥ binary.stackNeed depth, and the image is apart from the
  window bytes below rsp
→ ∃ n s', Steps n s s'
    ∧ s'.rip = the return address at [s.rsp]
    ∧ low 32 bits of s'.rax = v
    ∧ s'.rsp = s.rsp + 8, rbp is restored
    ∧ every register but rax, rcx, r11 is unchanged
    ∧ no memory outside the window changed
```

This is forward simulation of terminating runs. The x86 model is deterministic
on everything the theorem observes, so it also rules out any other result.
Divergence, traps and the ELF startup/exit wrapper come later; the existing
`StartupExitCheck` composes with this function-level contract.

## Passes

1. `compileExpr` (expressions into eax, temporaries in frame slots) and
   `compileStmt` (statements; jump targets are byte offsets in the body, since
   every abstract instruction has a fixed size).
2. `Instr.encode` (offsets to rel32 displacements, then bytes through the
   existing encoders in `X86/Machine/*Encoding.lean`) and `compileProgram`
   (functions back to back, calls resolved to entry offsets).
3. Prologue and epilogue: the existing `framePrologueBytes` and epilogue.

Simulation invariant (one relation for every activation): `rip` is the body
base plus the abstract pc, `rbp`/`rsp` are the frame's, each slot `x` is
`read32` of frame slot `x`, and memory outside the activation's stack window is
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

Milestones 1–3 are proved, with no `sorry` and only the standard axioms
(`propext`, `Classical.choice`, `Quot.sound`). The source language has i32
arithmetic, signed comparisons producing 1/0, `if`, `while`, `return`, and
functions with parameters and direct (also recursive) calls.

The proof has two layers.

- Compiler logic: `compileStmt_correct` / `compileFunc_correct` prove the compiler
  against an abstract machine (accumulator, frame slots, byte-offset pc), by
  induction on the source derivation. A call's effect is a parameter of the
  abstract machine: whatever the callee is known to return.
- Bytes: one x86 lemma per abstract instruction (`Simulation`). A call copies
  its arguments to just below the return address it pushes, which is where the
  callee's prologue puts its parameter slots, and then uses the callee's
  `Contract`. `compiled_contract` proves every function's contract by strong
  induction on call depth: an activation that nests calls fewer than `d` deep
  uses at most `(d + 1) * frameNeed` stack bytes and changes nothing else.

| file | lines | check (s) | role |
|---|---:|---:|---|
| `Syntax`, `Semantics` | 144 | 0.8 | source language and big-step semantics with call depth |
| `Asm` | 199 | 0.8 | abstract machine, byte-offset placement, `Star` runs |
| `Compile` | 134 | 0.7 | the compiler: expressions, statements, calls, frames |
| `CompileCorrect` | 428 | 1.1 | compiler against the abstract machine |
| `Fits` | 176 | 0.9 | static facts: slots in frame, targets in body, callees exist |
| `Bytes` | 285 | 1.2 | encoder with rel32 jumps and calls, program image layout |
| `Flags` | 100 | 1.3 | each comparison's condition code after `cmp` |
| `Frame` | 128 | 1.2 | stack windows and address depths (`bv_omega`) |
| `Simulation` | 840 | 3.8 | x86 lemma per instruction, the call macro, body simulation |
| `Correct` | 281 | 1.6 | layout, prologue, function contract, top-level theorem |

Check times are `lake env lean` per file on the laptop, about 0.4 s of each is
import loading. The compiler (`Compile`, `Bytes` definitions) is about 250
lines; the proofs are about 2,200.

A test program (iterative factorial, recursive Fibonacci, a function mixing all
six comparisons with a call, and gcd with `if` inside `while`) was compiled by
`#eval compileProgram` and its image run natively through a small stub that
puts SysV arguments where the convention expects them: 2,368 calls, all equal
to a Python reference with i32 wrapping.

Next: milestone 4, the same compiler written in Lanius and the shallow
extractor that produces these Lean definitions from it.
