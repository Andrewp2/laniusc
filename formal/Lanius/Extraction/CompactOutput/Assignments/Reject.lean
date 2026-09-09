import Lanius.Extraction.CompactOutput.Assignments.Arguments
import Lanius.Extraction.CompactOutput.Assignments.Guard

namespace Lanius.Extraction.CompactOutput.Assignments

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core

/-- A short declared input length rejects at the public call without reading
input/output storage or allocating iteration locals. Buffer values are arbitrary. -/
theorem Checked.short_input (checked : Checked program byte digit word)
    (input output : Value) (length count : Nat) (capacity position : Int)
    (wellFormed : StateWellFormed before) (short : length < 2 * count)
    (lengthFit : length ≤ 2147483647)
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments
      (argumentsValues input output length count capacity position) before) :
    ∃ after, Evaluates program.core caller (.call checked.source.function.id arguments) (.signed .i32 (-1)) after ∧
      CellEffect CellSet.empty before after := by
  let params := bindings input output length count capacity position
  let callee := enterCall before params
  have locals (index : Fin 6) : callee.local? index.val = some
      ((argumentsValues input output length count capacity position).get index) :=
    enterCall_parameterBindings_matches wellFormed index
  have rejected := entry_guard_rejects program.core count length short lengthFit
    (locals ⟨2, by decide⟩) (locals ⟨1, by decide⟩)
  have run : Executes program.core callee (body word.source.function.id)
      (.returned (some (.signed .i32 (-1)))) callee :=
    executesSequenceReturned (executesIfTrue rejected (executesSequenceReturned
      (executesReturnValue (negativeOne_evaluates program.core callee))))
  exact ⟨restoreLocals before callee, checked.call wellFormed argumentsResult (bindings := params) rfl run
    (CellEffect.refl (enterCall_preserves_wellFormed wellFormed))⟩

end Lanius.Extraction.CompactOutput.Assignments
