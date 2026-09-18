import Lanius.Extraction.CanonicalTokens.Dispatch.Checked
import Lanius.Extraction.CanonicalTokens.Dispatch.Lexer
import Lanius.FunctionalViewCoreSimulation

namespace Lanius.Extraction.CanonicalTokens.Dispatch

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView
open Lanius.FunctionalView.Core

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
      (.signed .i32 (lookup ((source.drop start).take width) referenceRows 1)) after ∧ CellEffect CellSet.empty before after ∧
      Host.MemoryFrame before after := by
  let slice := Value.slice (.scalar (.signed .i32)) sourceCell [] 0 source.length
  let environment : Env 3 := fun index => [slice, .signed .i32 start,
    .signed .i32 (start + width)].get index
  let bindings := parameterBindings environment
  let entered := enterCall before bindings
  have locals := enterCall_parameterBindings_matches (environment := environment) wellFormed
  have enterEffect := enterCall_effect before bindings
  have sourceOld := StateWellFormed.cell_lt_next_of_entry wellFormed sourceContents
  have sourceReady : entered.cellEntry? sourceCell = some {
      id := sourceCell, value := some (.array (signedI32Values source)) } :=
    (enterEffect.oldCells sourceCell sourceOld (by simp [CellSet.empty])).trans sourceContents
  obtain ⟨completed, run, frame, memory⟩ := checked.correct.executes entered sourceCell source start width
    (enterCall_preserves_wellFormed wellFormed)
    (locals ⟨0, by decide⟩)
    sourceReady
    (locals ⟨1, by decide⟩)
    (locals ⟨2, by decide⟩)
    capacity bounded
  rw [checked.correct.source.exactSource] at run
  have parameters : bindParameters
      (sourceFunction functionId matcher checked.correct.source.fallback checked.correct.source.groups).parameters
      [slice, .signed .i32 start, .signed .i32 (start + width)] = some bindings := rfl
  have called := evaluatesCallReturned argumentsResult checked.found parameters rfl run
  have closed := CellEffect.closeCall before bindings wellFormed frame
  exact ⟨restoreLocals before completed, called, closed,
    ((Host.MemoryFrame.enterCall before bindings).trans memory).restoreLocals before closed.wellFormed⟩

end Lanius.Extraction.CanonicalTokens.Dispatch
