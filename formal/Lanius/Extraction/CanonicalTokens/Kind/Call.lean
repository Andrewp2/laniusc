import Lanius.Extraction.CanonicalTokens.Kind.Execution

namespace Lanius.Extraction.CanonicalTokens.Kind

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView Lanius.FunctionalView.Core

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
      (.signed .i32 (result source rawKind start width)) after ∧ CellEffect CellSet.empty before after ∧
      Host.MemoryFrame before after := by
  let slice := Value.slice (.scalar (.signed .i32)) sourceCell [] 0 source.length
  let environment : Env 4 := fun
    | ⟨0, _⟩ => slice
    | ⟨1, _⟩ => .signed .i32 rawKind
    | ⟨2, _⟩ => .signed .i32 start
    | ⟨3, _⟩ => .signed .i32 (start + width)
  let bindings := parameterBindings environment
  let entered := enterCall before bindings
  have enteredWF : StateWellFormed entered := enterCall_preserves_wellFormed wellFormed
  have locals : EnvironmentMatches identityLayout environment entered :=
    enterCall_parameterBindings_matches (environment := environment) wellFormed
  have enterEffect := enterCall_effect before bindings
  have sourceOld := StateWellFormed.cell_lt_next_of_entry wellFormed sourceContents
  have sourceReady : entered.cellEntry? sourceCell = some {
      id := sourceCell, value := some (.array (signedI32Values source)) } :=
    (enterEffect.oldCells sourceCell sourceOld (by simp [CellSet.empty])).trans sourceContents
  obtain ⟨completed, run, frame, memory⟩ := checked.executes_body entered sourceCell source rawKind start width
    enteredWF (locals ⟨0, by decide⟩) sourceReady (locals ⟨1, by decide⟩)
      (locals ⟨2, by decide⟩) (locals ⟨3, by decide⟩) capacity bounded
  have parameters : bindParameters (sourceFunction functionId keywordId checked.identifier).parameters
      [slice, .signed .i32 rawKind, .signed .i32 start, .signed .i32 (start + width)] = some bindings := rfl
  have called := evaluatesCallReturned argumentsResult checked.found parameters rfl run
  have closed := CellEffect.closeCall before bindings wellFormed frame
  exact ⟨restoreLocals before completed, called, closed,
    ((Host.MemoryFrame.enterCall before bindings).trans memory).restoreLocals before closed.wellFormed⟩

end Lanius.Extraction.CanonicalTokens.Kind
