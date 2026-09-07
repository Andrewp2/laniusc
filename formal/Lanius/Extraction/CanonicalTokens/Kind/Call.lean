import Lanius.Extraction.CanonicalTokens.Kind.Execution

namespace Lanius.Extraction.CanonicalTokens.Kind

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts

theorem Checked.evaluates_call (checked : Checked program functionId keywordId matcher)
    (before : State) (sourceCell : CellId) (source : List Int) (rawKind : Int) (start width : Nat)
    (expressions : List Expr) (wellFormed : StateWellFormed before)
    (sourceContents : before.cellEntry? sourceCell = some {
      id := sourceCell, value := some (.array (signedI32Values source)) })
    (argumentsResult : ArgumentsEvaluateTo program before expressions [
      .slice (.scalar (.signed .i32)) sourceCell [] 0 source.length,
      .signed .i32 rawKind, .signed .i32 start, .signed .i32 (start + width)] before)
    (capacity : start + width ≤ source.length) (bounded : source.length ≤ 2147483647) :
    ∃ after, Evaluates program before (.call functionId expressions)
      (.signed .i32 (result source rawKind start width)) after ∧ CellEffect CellSet.empty before after := by
  let slice := Value.slice (.scalar (.signed .i32)) sourceCell [] 0 source.length
  let bindings : List (VarId × Value) := [(0, slice), (1, .signed .i32 rawKind),
    (2, .signed .i32 start), (3, .signed .i32 (start + width))]
  let entered := enterCall before bindings
  have enteredWF : StateWellFormed entered := enterCall_preserves_wellFormed wellFormed
  have enterEffect := enterCall_effect before bindings
  have sourceOld := StateWellFormed.cell_lt_next_of_entry wellFormed sourceContents
  have sourceReady : entered.cellEntry? sourceCell = some {
      id := sourceCell, value := some (.array (signedI32Values source)) } :=
    (enterEffect.oldCells sourceCell sourceOld (by simp [CellSet.empty])).trans sourceContents
  have sourceLocal : entered.local? 0 = some slice :=
    enterCall_local_of_binding before [] [(1, .signed .i32 rawKind), (2, .signed .i32 start),
      (3, .signed .i32 (start + width))] 0 slice wellFormed (by
        intro binding member
        simp only [List.mem_cons, List.not_mem_nil, or_false] at member
        rcases member with rfl | rfl | rfl <;> simp)
  have rawLocal : entered.local? 1 = some (.signed .i32 rawKind) :=
    enterCall_local_of_binding before [(0, slice)] [(2, .signed .i32 start), (3, .signed .i32 (start + width))]
      1 (.signed .i32 rawKind) wellFormed (by
        intro binding member
        simp only [List.mem_cons, List.not_mem_nil, or_false] at member
        rcases member with rfl | rfl <;> simp)
  have startLocal : entered.local? 2 = some (.signed .i32 start) :=
    enterCall_local_of_binding before [(0, slice), (1, .signed .i32 rawKind)] [(3, .signed .i32 (start + width))]
      2 (.signed .i32 start) wellFormed (by intro binding member; simp_all)
  have endLocal : entered.local? 3 = some (.signed .i32 (start + width)) :=
    enterCall_local_of_binding before [(0, slice), (1, .signed .i32 rawKind), (2, .signed .i32 start)] []
      3 (.signed .i32 (start + width)) wellFormed (by simp)
  obtain ⟨completed, run, frame⟩ := checked.executes_body entered sourceCell source rawKind start width
    enteredWF sourceLocal sourceReady rawLocal startLocal endLocal capacity bounded
  have parameters : bindParameters (sourceFunction functionId keywordId checked.identifier).parameters
      [slice, .signed .i32 rawKind, .signed .i32 start, .signed .i32 (start + width)] = some bindings := rfl
  have called := evaluatesCallReturned argumentsResult checked.found parameters rfl run
  have domain := enterEffect.domain.trans frame.domain
  refine ⟨restoreLocals before completed, called, ?_⟩
  refine ⟨domain.restoreLocals_wellFormed wellFormed frame.wellFormed, rfl,
    frame.world.trans enterEffect.world, ?_, Nat.le_trans enterEffect.nextCell frame.nextCell,
    domain.restoreLocals⟩
  intro cell old _
  exact (frame.empty_preserves_cell cell (Nat.lt_of_lt_of_le old enterEffect.nextCell)).trans
    (enterEffect.oldCells cell old (by simp [CellSet.empty]))

end Lanius.Extraction.CanonicalTokens.Kind
