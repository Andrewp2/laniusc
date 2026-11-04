module

public import Lanius.Open.F14.CompileFuncSlotsV2.Stmt
public import Lanius.Faithful.SelfPre.CompileSlotsProof

@[expose] public section

open Lanius.Mini
open Lanius.Faithful.SelfPre

/-- By induction over `compileExpr`, `compileArgs` and `compileStmt`
(SelfPre/CompileSlotsProof: `reach_compileStmt`, `nb_compileStmt`) with
`Stmt.within` and the room check (`codeSize_le`). -/
theorem Lanius.Open.CompileFuncSlotsV2.proof : Lanius.Open.CompileFuncSlotsV2 := by
  intro arities func c h
  exact compileFunc_slots arities func c h
