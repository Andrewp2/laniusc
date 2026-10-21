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

For a function `f` of the source language, an argument environment `args` and
an x86 state `s` about to execute a near call target:

```text
compile f = some code
∧ run f args = some v                    -- the source function returns v
∧ code is loaded at s.rip, and the frame below s.rsp is disjoint from it
→ ∃ n s', Steps n s s'
    ∧ s'.rip = the return address at [s.rsp]
    ∧ low 32 bits of s'.rax = v
    ∧ s'.rsp = s.rsp + 8 and rbp is restored
```

This is forward simulation of terminating runs. The x86 model is deterministic
on everything the theorem observes, so it also rules out any other result.
Divergence, traps and the ELF startup/exit wrapper come later; the existing
`StartupExitCheck` composes with this function-level contract.

## Passes

1. `compileExpr` (expressions into eax, temporaries in frame slots) and
   `compileStmt` (statements, then control flow with labels).
2. `assemble` (symbolic labels to rel32 displacements, then bytes through the
   existing encoders in `X86/Machine/*Encoding.lean`).
3. Prologue and epilogue: the existing `framePrologueBytes` and epilogue.

Simulation invariant (one relation for every pass): `rbp`/`rsp` are the frame's,
each local `x` is `read32` of frame slot `x`, temporaries live in slots above the
locals, the code bytes are untouched, and memory outside the frame is unchanged.

## Milestones

1. Straight-line: i32 literals and locals, `+ - * & | ^`, negation, assignment,
   `return`. One function.
2. `bool`, comparisons, `if`, `while`.
3. Functions with parameters and direct calls.
4. The same compiler written in Lanius, and the shallow extractor that produces
   these Lean definitions from it.

Each milestone records proof lines, compiler lines and fresh check time.

## Status

Milestone 1 is proved: `Lanius.Mini.compile_correct` in `Lanius/Mini/Correct.lean`,
with no `sorry` and only the standard axioms (`propext`, `Classical.choice`,
`Quot.sound`). Its hypotheses, from the caller's side of a near call:

- `compileFunc func = some code` and `func.run args = some value`;
- `code.image` (prologue, then the body's bytes) is loaded at `rip`;
- the image is apart from the stack window from the deepest frame slot up to the
  return address at `rsp` (`StackApart`);
- local `k` holds `args k` at `rsp - (8k + 16)`, where the prologue puts slot `k`.

Conclusion: some run of `Steps` reaches a state whose `rip` is the return address,
`rsp` is the entry `rsp + 8`, `rbp` is restored, `eax` is `value`, and every
register except rax, rcx, rsp, rbp and r11 is unchanged.

| file | lines | role |
|---|---:|---|
| `Syntax`, `Semantics` | 64 | source language and its semantics |
| `Asm` | 70 | abstract machine (accumulator + frame slots) |
| `Compile` | 69 | the compiler: expressions, statements, frame size |
| `Bytes` | 38 | one fixed byte sequence per abstract instruction |
| `CompileCorrect` | 150 | compiler against the abstract machine, by induction on syntax |
| `Frame` | 64 | slot address arithmetic (`bv_omega`) |
| `Simulation` | 275 | one x86 lemma per abstract instruction, then the body |
| `Correct` | 121 | prologue, body, epilogue: the top-level theorem |

Every file checks in about a second, most of it import loading
(`lake build LaniusMini`). The pass proof (`CompileCorrect`) is about 2x the
compiler it covers. `Frame` and `Simulation` are per-instruction, not
per-compiler-feature, so they grow with the instruction set, not with the
compiler. A sample function's image was also run natively; it returned the same
value as `Func.run`.
