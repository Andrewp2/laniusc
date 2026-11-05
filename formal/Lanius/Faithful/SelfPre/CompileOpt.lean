module

public import Lanius.Open.F14.OptimizeKeepsNumbers.Proof
public import Lanius.Open.F14.CompileFuncSlotsV2.Stmt
import all Lanius.Mini.Compiler.P.BinOp_bytes
import all Lanius.Mini.Compiler.P.BinOp_opcode
import all Lanius.Mini.Compiler.P.CmpOp_setcc
import all Lanius.Mini.Compiler.P.CmpOp_setccSigned
import all Lanius.Mini.Compiler.P.CmpOp_setccUnsigned
import all Lanius.Mini.Compiler.P.DivOp_bytes
import all Lanius.Mini.Compiler.P.DivOp_extend
import all Lanius.Mini.Compiler.P.DivOp_opcode
import all Lanius.Mini.Compiler.P.DivOp_result
import all Lanius.Mini.Compiler.P.Word_rex
import all Lanius.Mini.Compiler.P.arities
import all Lanius.Mini.Compiler.P.compileFuncs
import all Lanius.Mini.Compiler.P.fspLoad
import all Lanius.Mini.Compiler.P.fspSave
import all Lanius.Mini.Compiler.P.le32
import all Lanius.Mini.Compiler.P.le64
import all Lanius.Mini.Compiler.P.slotCompare
import all Lanius.Mini.Compiler.P.slotLoad
import all Lanius.Mini.Compiler.P.slotOffset
import all Lanius.Mini.Compiler.P.slotOperands
import all Lanius.Mini.Compiler.P.slotStore
import all Lanius.Mini.Compiler.P.Expr_temps
import all Lanius.Mini.Compiler.P.Expr_within
import all Lanius.Mini.Compiler.P.Stmt_temps
import all Lanius.Mini.Compiler.P.Stmt_within
import all Lanius.Mini.Compiler.P.allWithin
import all Lanius.Mini.Compiler.P.argSlots
import all Lanius.Mini.Compiler.P.argsRoom
import all Lanius.Mini.Compiler.P.argsTemps
import all Lanius.Mini.Compiler.P.arityIs
import all Lanius.Mini.Compiler.P.compileArgs
import all Lanius.Mini.Compiler.P.compileStmt
import all Lanius.Mini.Compiler.P.exprRoom
import all Lanius.Mini.Compiler.P.frameLimit
import all Lanius.Mini.Compiler.P.imageLimit
import all Lanius.Mini.Compiler.P.spend
import all Lanius.Mini.Compiler.P.stmtRoom
import all Lanius.Mini.Compiler.P.zeroLocals

@[expose] public section

/-! # The optimizer's numbers, for the compile side's pre lemmas (F14)

`compile_optimized` compiles `optimizeProgram p`, which no post bounds; the
Mini compile's pre lemmas need its numbers (`nb`) and temporaries
(`funcsTemps`) below `2 ^ 62`. The proved leaf `OptimizeKeepsNumbers` gives
both from `p`'s. `Tactic.valueFacts` finds `val_optimizeProgram` by name. GenPC's
pre modules import this one (`pre_certs.py`, `COMPILE_PRE_IMPORTS`). -/

namespace Lanius.Faithful.SelfPre

open Lanius.Mini

theorem val_optimizeProgram (p : Program) :
    nb (optimizeProgram p) ≤ nb p ∧ funcsTemps (optimizeProgram p).funcs ≤ funcsTemps p.funcs :=
  Lanius.Open.OptimizeKeepsNumbers.proof p

/-- The compiled functions fit their frames (`codesSlack`, SelfPre/CompileSlots) and their
instructions' numbers are the functions' or at most `2 ^ 40` (`codesNb`), by the open leaf
CompileFuncSlotsV2, which `compile_program`'s pre lemma and its callers' assume
(`COMPILE_OVERRIDES`); `Tactic.valueFacts` passes it from the context. -/
theorem vals_compileFuncs (ar : List Arity) : ∀ (fs : List Func) (codes : List Code),
    compileFuncs ar fs = some codes → Lanius.Open.CompileFuncSlotsV2 →
      codesSlack codes = 0 ∧ codesNb codes ≤ max (nb fs) 1099511627776
  | [], codes, h, _ => by
    simp only [compileFuncs, Option.some.injEq] at h; subst h
    exact ⟨codesSlack_nil, Nat.zero_le _⟩
  | f :: rest, codes, h, hs => by
    rw [compileFuncs] at h
    split at h
    · simp at h
    · rename_i c hc
      split at h
      · simp at h
      · rename_i cs hcs
        simp only [Option.some.injEq] at h; subst h
        have ⟨h1, h2, h3, h4⟩ := hs ar f c hc
        have ⟨h5, h6⟩ := vals_compileFuncs ar rest cs hcs hs
        simp only [codesSlack_cons_eq_zero, codesNb, nb_cons, frameLimit] at *
        omega

end Lanius.Faithful.SelfPre
