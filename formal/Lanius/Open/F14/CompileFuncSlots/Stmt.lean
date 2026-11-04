import Lanius.Faithful.SelfPre.CompileSlots

open Lanius.Mini
open Lanius.Faithful.SelfPre

/-- A function's compiled code names only slots of its frame, and its frame
fits the limit: `compileFunc` returns `slots = locals + temps ≤ frameLimit`
(`2 ^ 20`), and every slot its instructions read or write is below `slots`
(`codeSlotTop`, SelfPre/CompileSlots). The encoders' pre lemmas need it
(GenPC's `slot_offset`, `frame_size`, `arg_base`, `copy_bytes`, `sys_bytes`,
`Instr_encode`, `encode_onto`, `link_onto`): each slot becomes a 32-bit
displacement `-(slot + 1) * 8`. Why it holds: the first part is
`compileFunc`'s own check. The code is `imm 0`, `zeroLocals params
(locals - params)` (slots `params .. locals - 1`), then `compileStmt locals ..
body`. `Stmt.within body locals ..` keeps the body's variables, stores and
call targets (with their result counts) below `locals`, and `compileExpr`
and `compileArgs` put an operand's temporaries at `base + depth` with
`depth < Stmt.temps body` (`argSlots base args 0` for a call's arguments, a
`sys`'s three arguments at `slot .. slot + 2`), so they are below
`locals + temps`. -/
def Lanius.Open.CompileFuncSlots : Prop :=
  ∀ (arities : List Arity) (func : Func) (c : Code),
    compileFunc arities func = some c → c.slots ≤ frameLimit ∧ codeSlotTop c.instrs ≤ c.slots
