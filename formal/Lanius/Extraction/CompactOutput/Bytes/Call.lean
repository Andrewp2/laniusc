import Lanius.Extraction.CompactOutput.Bytes.Entry
import Lanius.Extraction.CompactOutput.Buffer
import Lanius.FunctionalViewCoreSimulation

namespace Lanius.Extraction.CompactOutput.Bytes

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core

def argumentsValues (input output : Value) (length capacity position : Int) : List Value :=
  [input, .signed .i32 length, output, .signed .i32 capacity, .signed .i32 position]

def bindings (input output : Value) (length capacity position : Int) : List (VarId × Value) :=
  parameterBindings (fun index : Fin 5 => (argumentsValues input output length capacity position).get index)

/-- Public execution of the complete checked byte serializer. Logical input
length is independent of allocation size, and errors retain partial output. -/
theorem Checked.write (checked : Checked program byte digit hex)
    (values : List Nat) (capacity : Nat) (position : Int)
    (wellFormed : StateWellFormed before)
    (input : I32Prefix before inputCell physicalCapacity (values.map Int.ofNat))
    (distinctBuffers : outputCell ≠ inputCell)
    (lengthFit : values.length ≤ 2147483647)
    (byteBound : ∀ value ∈ values, value < 256)
    (capacityBound : capacity ≤ original.length) (capacityFit : capacity ≤ 2147483647)
    (backing : before.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values original)) })
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments
      (argumentsValues (.slice i32 inputCell [] 0 physicalCapacity)
        (.slice i32 outputCell [] 0 original.length) values.length capacity position) before) :
    ∃ after, Evaluates program.core caller (.call checked.source.function.id arguments)
        (.signed .i32 (appendAll capacity (encoding values) position original).position) after ∧
      after.cellEntry? outputCell = some {
        id := outputCell, value := some (.array (signedI32Values
          (appendAll capacity (encoding values) position original).contents)) } ∧
      CellEffect (CellSet.singleton outputCell) before after := by
  let params := bindings (.slice i32 inputCell [] 0 physicalCapacity)
    (.slice i32 outputCell [] 0 original.length) values.length capacity position
  have locals (index : Fin 5) : (enterCall before params).local? index.val = some
      ((argumentsValues (.slice i32 inputCell [] 0 physicalCapacity)
        (.slice i32 outputCell [] 0 original.length) values.length capacity position).get index) :=
    enterCall_parameterBindings_matches wellFormed index
  have inputCallee : I32Prefix (enterCall before params) inputCell physicalCapacity (values.map Int.ofNat) := by
    obtain ⟨unused, size, contents⟩ := input
    exact ⟨unused, size, ((enterCall_effect before params).oldCells inputCell
      (StateWellFormed.cell_lt_next_of_entry wellFormed contents) (by simp [CellSet.empty])).trans contents⟩
  let entry : Entry (enterCall before params) := {
    inputCell, outputCell, values, contents := original, position, capacity
    wellFormed := enterCall_preserves_wellFormed wellFormed
    room := capacityBound, capacityFit, lengthFit, byteBound, distinctBuffers
    input := ⟨physicalCapacity, locals ⟨0, by decide⟩, inputCallee⟩
    lengthRead := locals ⟨1, by decide⟩
    output := locals ⟨2, by decide⟩
    capacityRead := locals ⟨3, by decide⟩
    positionRead := locals ⟨4, by decide⟩
    backing := ((enterCall_effect before params).oldCells outputCell
      (StateWellFormed.cell_lt_next_of_entry wellFormed backing) (by simp [CellSet.empty])).trans backing
  }
  obtain ⟨completed, run, contents, effect⟩ := entry.execute hex
  have called := checked.call wellFormed argumentsResult (bindings := params) rfl run effect
  exact ⟨restoreLocals before completed, called.1, contents, called.2⟩

theorem encoding_length (values : List Nat) : (encoding values).length = 2 * values.length := by
  induction values with
  | nil => rfl
  | cons value rest ih => simp only [encoding_cons, List.length_append, List.length_cons, List.length_nil, ih]; omega

/-- With sufficient capacity, replace exactly the encoded interval and
advance by two characters per byte, preserving prefix and suffix. -/
theorem Checked.success (checked : Checked program byte digit hex)
    (values : List Nat) (capacity position : Nat)
    (wellFormed : StateWellFormed before)
    (input : I32Prefix before inputCell physicalCapacity (values.map Int.ofNat))
    (distinctBuffers : outputCell ≠ inputCell) (lengthFit : values.length ≤ 2147483647)
    (byteBound : ∀ value ∈ values, value < 256)
    (room : position + 2 * values.length ≤ capacity)
    (capacityBound : capacity ≤ original.length) (capacityFit : capacity ≤ 2147483647)
    (backing : before.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values original)) })
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments
      (argumentsValues (.slice i32 inputCell [] 0 physicalCapacity)
        (.slice i32 outputCell [] 0 original.length) values.length capacity position) before) :
    ∃ after, Evaluates program.core caller (.call checked.source.function.id arguments)
        (.signed .i32 (position + 2 * values.length : Nat)) after ∧
      after.cellEntry? outputCell = some {
        id := outputCell, value := some (.array (signedI32Values
          (original.take position ++ (encoding values).map Int.ofNat ++ original.drop (position + 2 * values.length)))) } ∧
      CellEffect (CellSet.singleton outputCell) before after := by
  have encoded := appendAll_success capacity position (encoding values) original
    (by simpa only [encoding_length] using room) capacityBound
  simpa only [encoded, encoding_length, AppendOutcome.position, AppendOutcome.contents] using
    checked.write values capacity position wellFormed input distinctBuffers lengthFit byteBound
      capacityBound capacityFit backing argumentsResult

/-- Negative logical lengths return before dereferencing either buffer. -/
theorem Checked.reject (checked : Checked program byte digit hex)
    (input output : Value) (length capacity position : Int)
    (wellFormed : StateWellFormed before) (negative : length < 0)
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments
      (argumentsValues input output length capacity position) before) :
    ∃ after, Evaluates program.core caller (.call checked.source.function.id arguments) (.signed .i32 (-1)) after ∧
      CellEffect CellSet.empty before after := by
  let params := bindings input output length capacity position
  let callee := enterCall before params
  have locals (index : Fin 5) : callee.local? index.val = some
      ((argumentsValues input output length capacity position).get index) :=
    enterCall_parameterBindings_matches wellFormed index
  have lengthRead : callee.local? 1 = some (.signed .i32 length) := locals ⟨1, by decide⟩
  have guard : Evaluates program.core callee (binary .lessEqual (read 1) negativeOne) (.boolean true) callee := by
    apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates program.core lengthRead)
      (negativeOne_evaluates program.core callee)
    simp [evalBinaryValue, evalSignedBinary]
    omega
  have run : Executes program.core callee (body hex.source.function.id)
      (.returned (some (.signed .i32 (-1)))) callee :=
    executesSequenceReturned (executesIfTrue guard (executesSequenceReturned
      (executesReturnValue (negativeOne_evaluates program.core callee))))
  exact ⟨restoreLocals before callee, checked.call wellFormed argumentsResult (bindings := params) rfl run
    (CellEffect.refl (enterCall_preserves_wellFormed wellFormed))⟩

end Lanius.Extraction.CompactOutput.Bytes
