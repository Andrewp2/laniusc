import Lanius.Extraction.CompactOutput.Word.Entry
import Lanius.Extraction.CompactOutput.Buffer
import Lanius.FunctionalViewCoreSimulation

namespace Lanius.Extraction.CompactOutput.Word

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core

/-- The public checked eight-digit writer, including partial output on
capacity failure. Its temporary resources follow from ordinary arguments. -/
theorem Checked.write (checked : Checked program byte digit) (position : Int) (capacity value : Nat)
    (wellFormed : StateWellFormed before)
    (capacityBound : capacity ≤ original.length) (capacityFit : capacity ≤ 2147483647)
    (valueFit : value ≤ 2147483647)
    (backing : before.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values original)) })
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments
      (byteValues (.slice i32 outputCell [] 0 original.length) capacity position value) before) :
    ∃ after, Evaluates program.core caller (.call checked.source.function.id arguments)
        (.signed .i32 (appendAll capacity (hexDigits value 8) position original).position) after ∧
      after.cellEntry? outputCell = some {
        id := outputCell, value := some (.array (signedI32Values (appendAll capacity (hexDigits value 8) position original).contents)) } ∧
      CellEffect (CellSet.singleton outputCell) before after := by
  let bindings := byteBindings (.slice i32 outputCell [] 0 original.length) capacity position value
  have locals (index : Fin 4) : (enterCall before bindings).local? index.val = some
      ((byteValues (.slice i32 outputCell [] 0 original.length) capacity position value).get index) :=
    enterCall_parameterBindings_matches wellFormed index
  let entry : Entry (enterCall before bindings) := {
    outputCell, contents := original, position, capacity, value
    wellFormed := enterCall_preserves_wellFormed wellFormed
    room := capacityBound, capacityFit, valueFit
    output := locals ⟨0, by decide⟩
    capacityRead := locals ⟨1, by decide⟩
    positionRead := locals ⟨2, by decide⟩
    valueRead := locals ⟨3, by decide⟩
    backing := ((enterCall_effect before bindings).oldCells outputCell
      (StateWellFormed.cell_lt_next_of_entry wellFormed backing) (by simp [CellSet.empty])).trans backing
  }
  obtain ⟨completed, run, contents, effect⟩ := entry.execute byte digit
  have called := checked.call wellFormed argumentsResult (bindings := bindings) rfl run effect
  exact ⟨restoreLocals before completed, called.1, contents, called.2⟩

theorem Checked.success (checked : Checked program byte digit) (position capacity value : Nat)
    (wellFormed : StateWellFormed before) (room : position + 8 ≤ capacity)
    (capacityBound : capacity ≤ original.length) (capacityFit : capacity ≤ 2147483647)
    (valueFit : value ≤ 2147483647)
    (backing : before.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values original)) })
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments
      (byteValues (.slice i32 outputCell [] 0 original.length) capacity position value) before) :
    ∃ after, Evaluates program.core caller (.call checked.source.function.id arguments) (.signed .i32 (position + 8 : Nat)) after ∧
      after.cellEntry? outputCell = some {
        id := outputCell, value := some (.array (signedI32Values
          (original.take position ++ (hexDigits value 8).map Int.ofNat ++ original.drop (position + 8)))) } ∧
      CellEffect (CellSet.singleton outputCell) before after := by
  have encoded := appendAll_success capacity position (hexDigits value 8) original (by simpa only [hexDigits_length] using room) capacityBound
  simpa only [encoded, hexDigits_length, AppendOutcome.position, AppendOutcome.contents] using
    checked.write position capacity value wellFormed capacityBound capacityFit valueFit backing argumentsResult

/-- Negative inputs are rejected before any output access or loop allocation. -/
theorem Checked.reject (checked : Checked program byte digit) (output : Value) (capacity position value : Int)
    (wellFormed : StateWellFormed before) (negative : value < 0)
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments (byteValues output capacity position value) before) :
    ∃ after, Evaluates program.core caller (.call checked.source.function.id arguments) (.signed .i32 (-1)) after ∧
      CellEffect CellSet.empty before after := by
  let bindings := byteBindings output capacity position value
  let callee := enterCall before bindings
  have locals (index : Fin 4) : callee.local? index.val = some ((byteValues output capacity position value).get index) :=
    enterCall_parameterBindings_matches wellFormed index
  have valueRead : callee.local? 3 = some (.signed .i32 value) := locals ⟨3, by decide⟩
  have guard : Evaluates program.core callee (binary .lessEqual (read 3) negativeOne) (.boolean true) callee := by
    apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates program.core valueRead)
      (negativeOne_evaluates program.core callee)
    simp [evalBinaryValue, evalSignedBinary]
    omega
  have run : Executes program.core callee (body byte.source.function.id digit.source.function.id)
      (.returned (some (.signed .i32 (-1)))) callee :=
    executesSequenceReturned (executesIfTrue guard (executesSequenceReturned
      (executesReturnValue (negativeOne_evaluates program.core callee))))
  exact ⟨restoreLocals before callee, checked.call wellFormed argumentsResult (bindings := bindings) rfl run
    (CellEffect.refl (enterCall_preserves_wellFormed wellFormed))⟩

end Lanius.Extraction.CompactOutput.Word
