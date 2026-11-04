module

public import Lanius.Faithful.SelfPre.CompileSlots
public import Lanius.Faithful.SelfPre.NB

@[expose] public section

open Lanius.Mini
open Lanius.Faithful.SelfPre

/-- A function's compiled code names only slots of its frame, its frame fits
the limit, its code is at most `2 ^ 40` bytes, and its instructions' numbers
are its function's numbers or at most `2 ^ 40`. `CompileFuncSlots` with
`slotReach` (SelfPre/CompileSlots: a call's arguments and a return's sources
counted by their number too, since they are copied to the callee's or the
frame's first slots), the code's size and its numbers. The encoders' pre
lemmas need it (GenPC's `slot_offset`, `frame_size`, `arg_base`,
`copy_bytes`, `sys_bytes`, `Instr_encode`, `encode_onto`, `link_onto`,
`layout`, `Code_size`): each slot becomes a 32-bit displacement
`-(slot + 1) * 8`, and `encode_onto` asks for the instructions' numbers below
`2 ^ 62`. Why it holds: `compileFunc` checks `slots = locals + temps ≤
frameLimit` (`2 ^ 20`). The code is `imm 0`, `zeroLocals params
(locals - params)` (slots `params .. locals - 1`), then `compileStmt locals ..
body`. `Stmt.within body locals ..` keeps the body's variables, stores and
call targets with their result counts (`target + count ≤ locals`) below
`locals`, and `compileExpr` and `compileArgs` put an operand's temporaries at
`base + depth` with `depth < Stmt.temps body` (`argSlots base args 0` puts
argument k at `base + k`, `k < args.length ≤ argsTemps args 0`; a `sys` has
exactly three arguments, so `slot .. slot + 2` are temporaries), so they are
below `locals + temps`. The code's size: the room check bounds the body's
weight by `imageLimit` (`2 ^ 30`), its code is at most 64 bytes per unit of
weight (`codeSize_le`), and the prologue's `zeroLocals` 7 bytes per local.
The numbers: slots (below `2 ^ 20`), jump targets (positions in the code, at
most its size), and a call's callee, target and count, an `alloc`'s shift, a
`frame`'s bytes and a `static`'s offset, which are the body's. -/
def Lanius.Open.CompileFuncSlotsV2 : Prop :=
  ∀ (arities : List Arity) (func : Func) (c : Code),
    compileFunc arities func = some c →
      c.slots ≤ frameLimit ∧ codeSlotReach c.instrs ≤ c.slots ∧ codeSize c.instrs ≤ 2 ^ 40 ∧
        nb c.instrs ≤ max (nb func) (2 ^ 40)
