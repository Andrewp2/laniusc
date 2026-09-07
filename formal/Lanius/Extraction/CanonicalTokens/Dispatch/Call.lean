import Lanius.Extraction.CanonicalTokens.Dispatch.Checked
import Lanius.Extraction.CanonicalTokens.Dispatch.Lexer

namespace Lanius.Extraction.CanonicalTokens.Dispatch

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts

structure CheckedFunction (program : Program) (functionId matcher : FunctionId) where
  statement : Stmt
  correct : Checked program matcher statement
  found : program.function? functionId = some
    (sourceFunction functionId matcher correct.source.fallback correct.source.groups)

def checkFunction? (program : Program) (functionId matcher : FunctionId) :
    Option (CheckedFunction program functionId matcher) := do
  match found : program.function? functionId with
  | none => none
  | some function =>
      let statement ← function.body
      let correct ← check? program matcher statement
      let same ← Equality.function? function
        (sourceFunction functionId matcher correct.source.fallback correct.source.groups)
      pure ⟨statement, correct, found.trans (congrArg some same.equal)⟩

theorem CheckedFunction.evaluates_call (checked : CheckedFunction program functionId matcher)
    (before : State) (sourceCell : CellId) (source : List Int) (start width : Nat) (arguments : List Expr)
    (wellFormed : StateWellFormed before)
    (sourceContents : before.cellEntry? sourceCell = some {
      id := sourceCell, value := some (.array (signedI32Values source)) })
    (argumentsResult : ArgumentsEvaluateTo program before arguments [
      .slice (.scalar (.signed .i32)) sourceCell [] 0 source.length,
      .signed .i32 start, .signed .i32 (start + width)] before)
    (capacity : start + width ≤ source.length) (bounded : source.length ≤ 2147483647) :
    ∃ after, Evaluates program before (.call functionId arguments)
      (.signed .i32 (lookup ((source.drop start).take width) referenceRows 1)) after ∧ CellEffect CellSet.empty before after := by
  let slice := Value.slice (.scalar (.signed .i32)) sourceCell [] 0 source.length
  let bindings : List (VarId × Value) := [(0, slice), (1, .signed .i32 start), (2, .signed .i32 (start + width))]
  let entered := enterCall before bindings
  have enteredWF : StateWellFormed entered := enterCall_preserves_wellFormed wellFormed
  have enterEffect := enterCall_effect before bindings
  have sourceOld := StateWellFormed.cell_lt_next_of_entry wellFormed sourceContents
  have sourceReady : entered.cellEntry? sourceCell = some {
      id := sourceCell, value := some (.array (signedI32Values source)) } :=
    (enterEffect.oldCells sourceCell sourceOld (by simp [CellSet.empty])).trans sourceContents
  have sourceLocal : entered.local? 0 = some slice :=
    enterCall_local_of_binding before [] [(1, .signed .i32 start), (2, .signed .i32 (start + width))]
      0 slice wellFormed (by
        intro binding member
        simp only [List.mem_cons, List.not_mem_nil, or_false] at member
        rcases member with rfl | rfl <;> simp)
  have startLocal : entered.local? 1 = some (.signed .i32 start) :=
    enterCall_local_of_binding before [(0, slice)] [(2, .signed .i32 (start + width))]
      1 (.signed .i32 start) wellFormed (by intro binding member; simp_all)
  have endLocal : entered.local? 2 = some (.signed .i32 (start + width)) :=
    enterCall_local_of_binding before [(0, slice), (1, .signed .i32 start)] []
      2 (.signed .i32 (start + width)) wellFormed (by simp)
  obtain ⟨completed, run, frame⟩ := checked.correct.executes entered sourceCell source start width
    enteredWF sourceLocal sourceReady startLocal endLocal capacity bounded
  rw [checked.correct.source.exactSource] at run
  have parameters : bindParameters
      (sourceFunction functionId matcher checked.correct.source.fallback checked.correct.source.groups).parameters
      [slice, .signed .i32 start, .signed .i32 (start + width)] = some bindings := rfl
  have called := evaluatesCallReturned argumentsResult checked.found parameters rfl run
  have domain := enterEffect.domain.trans frame.domain
  refine ⟨restoreLocals before completed, called, ?_⟩
  refine ⟨domain.restoreLocals_wellFormed wellFormed frame.wellFormed, rfl,
    frame.world.trans enterEffect.world, ?_, Nat.le_trans enterEffect.nextCell frame.nextCell,
    domain.restoreLocals⟩
  intro cell old _
  exact (frame.empty_preserves_cell cell (Nat.lt_of_lt_of_le old enterEffect.nextCell)).trans
    (enterEffect.oldCells cell old (by simp [CellSet.empty]))

end Lanius.Extraction.CanonicalTokens.Dispatch
