import Lanius.Extraction.CompactOutput.Append
import Lanius.Extraction.CompactOutput.Bits

namespace Lanius.Extraction.CompactOutput

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core

def hexBytePosition (capacity : Nat) (position : Int) : Int :=
  nextPosition capacity (nextPosition capacity position)

def hexByteOutput (original : List Int) (capacity : Nat) (position : Int) (value : Nat) : List Int :=
  appended (appended original capacity position (hexDigit (value / 16))) capacity
    (nextPosition capacity position) (hexDigit (value % 16))

/-- The complete two-digit writer. Capacity failure may retain a high digit;
the second append sees the sticky sentinel and cannot write after failure. -/
theorem hexByte_body (byte : CheckedByte program) (digit : CheckedDigit program)
    (position : Int) (capacity value : Nat) (byteBound : value < 256)
    (wellFormed : StateWellFormed before)
    (capacityBound : capacity ≤ original.length) (capacityFit : capacity ≤ 2147483647)
    (sliceRead : before.local? 0 = some (.slice i32 outputCell [] 0 original.length))
    (capacityRead : before.local? 1 = some (.signed .i32 capacity))
    (positionRead : before.local? 2 = some (.signed .i32 position))
    (valueRead : before.local? 3 = some (.signed .i32 value))
    (backing : before.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values original)) }) :
    ∃ after, Executes program.core before (hexByteBody byte.source.function.id digit.source.function.id)
        (.returned (some (.signed .i32 (hexBytePosition capacity position)))) after ∧
      after.cellEntry? outputCell = some {
        id := outputCell, value := some (.array (signedI32Values (hexByteOutput original capacity position value))) } ∧
      CellEffect (CellSet.singleton outputCell) before after := by
  have negative : Evaluates program.core before (binary .lessEqual (read 3) negativeOne) (.boolean false) before := by
    apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates program.core valueRead)
      (negativeOne_evaluates program.core before)
    simp [evalBinaryValue, evalSignedBinary]
    omega
  have tooLarge : Evaluates program.core before (binary .greaterEqual (read 3) (number 256)) (.boolean false) before := by
    apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates program.core valueRead)
      (show Evaluates program.core before (number 256) (.signed .i32 256) before from ⟨1, rfl⟩)
    simp [evalBinaryValue, evalSignedBinary]
    omega
  have high : Evaluates program.core before (digitArgument (read 3) (number 4))
      (.signed .i32 (value / 16 : Nat)) before := by
    have read := nibble_evaluates value 4 (by omega) (by decide) (local_evaluates program.core valueRead)
      (show Evaluates program.core before (number 4) (.signed .i32 4) before from ⟨1, rfl⟩)
    simpa only [digitArgument, Nat.reducePow, Nat.mod_eq_of_lt (show value / 16 < 16 by omega)] using read
  obtain ⟨first, firstRun, firstContents, firstEffect⟩ := append_digit byte digit position capacity (value / 16)
    (by omega) wellFormed capacityBound capacityFit backing (local_evaluates program.core sliceRead)
    (local_evaluates program.core capacityRead) (local_evaluates program.core positionRead) high
  let firstOutput := appended original capacity position (hexDigit (value / 16))
  let scope := first.bindLocal 4 (.signed .i32 (nextPosition capacity position))
  have scopeWF : StateWellFormed scope := bindLocal_preserves_well_formed first _ _ firstEffect.wellFormed
  have stable {id : VarId} {v : Value} (found : before.local? id = some v)
      (different : v ≠ .array (signedI32Values original)) (notNext : (4 : VarId) ≠ id) : scope.local? id = some v :=
    (bindLocal_preserves_other_local firstEffect.wellFormed notNext).trans
      (firstEffect.preserves_local_of_distinct_value wellFormed found backing different)
  have scopeContents : scope.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values firstOutput)) } :=
    ((bindLocal_effect first 4 (.signed .i32 (nextPosition capacity position))).oldCells outputCell
      (StateWellFormed.cell_lt_next_of_entry firstEffect.wellFormed firstContents) (by simp [CellSet.empty])).trans firstContents
  have sliceAfter : scope.local? 0 = some (.slice i32 outputCell [] 0 firstOutput.length) := by
    simpa only [firstOutput, appended_length] using stable sliceRead (by intro same; cases same) (by decide)
  have capacityAfter := stable capacityRead (by intro same; cases same) (by decide)
  have valueAfter := stable valueRead (by intro same; cases same) (by decide)
  have positionAfter : scope.local? 4 = some (.signed .i32 (nextPosition capacity position)) :=
    bindLocal_finds_local first _ _ firstEffect.wellFormed
  have low : Evaluates program.core scope (binary .bitAnd (read 3) (number 15))
      (.signed .i32 (value % 16 : Nat)) scope :=
    evaluatesEagerBinary (by decide) (by decide) (local_evaluates program.core valueAfter)
      (show Evaluates program.core scope (number 15) (.signed .i32 15) scope from ⟨1, rfl⟩)
      (mask_nibble program.core.target value (by omega))
  obtain ⟨completed, secondRun, contents, effect⟩ := append_digit byte digit (nextPosition capacity position)
    capacity (value % 16) (by omega) scopeWF (by simpa only [firstOutput, appended_length] using capacityBound)
    capacityFit scopeContents (local_evaluates program.core sliceAfter) (local_evaluates program.core capacityAfter)
    (local_evaluates program.core positionAfter) low
  refine ⟨restoreLocals first completed, ?_, contents, ?_⟩
  · exact executesSequence (executesIfFalse (evaluatesPureLogicalOr negative tooLarge) (executesSkip _ _))
      (executesLetLocal firstRun (executesSequenceReturned (executesReturnValue secondRun)))
  · exact firstEffect.trans (CellEffect.closeLocal first 4 (.signed .i32 (nextPosition capacity position))
      firstEffect.wellFormed effect)

theorem CheckedHexByte.write (checked : CheckedHexByte program byte digit)
    (position : Int) (capacity value : Nat) (byteBound : value < 256)
    (wellFormed : StateWellFormed before)
    (capacityBound : capacity ≤ original.length) (capacityFit : capacity ≤ 2147483647)
    (backing : before.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values original)) })
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments
      (byteValues (.slice i32 outputCell [] 0 original.length) capacity position value) before) :
    ∃ after, Evaluates program.core caller (.call checked.source.function.id arguments)
        (.signed .i32 (hexBytePosition capacity position)) after ∧
      after.cellEntry? outputCell = some {
        id := outputCell, value := some (.array (signedI32Values (hexByteOutput original capacity position value))) } ∧
      CellEffect (CellSet.singleton outputCell) before after := by
  let bindings := byteBindings (.slice i32 outputCell [] 0 original.length) capacity position value
  have locals (index : Fin 4) : (enterCall before bindings).local? index.val = some
      ((byteValues (.slice i32 outputCell [] 0 original.length) capacity position value).get index) :=
    enterCall_parameterBindings_matches wellFormed index
  have calleeBacking := ((enterCall_effect before bindings).oldCells outputCell
    (StateWellFormed.cell_lt_next_of_entry wellFormed backing) (by simp [CellSet.empty])).trans backing
  obtain ⟨completed, run, contents, effect⟩ := hexByte_body byte digit position capacity value byteBound
    (enterCall_preserves_wellFormed wellFormed) capacityBound capacityFit
    (locals ⟨0, by decide⟩) (locals ⟨1, by decide⟩) (locals ⟨2, by decide⟩) (locals ⟨3, by decide⟩) calleeBacking
  have called := checked.call wellFormed argumentsResult (bindings := bindings) rfl run effect
  exact ⟨restoreLocals before completed, called.1, contents, called.2⟩

/-- Invalid byte values are rejected before reading even the output argument.
No backing allocation is needed for this branch. -/
theorem CheckedHexByte.reject (checked : CheckedHexByte program byte digit)
    (output : Value) (capacity position value : Int)
    (wellFormed : StateWellFormed before) (invalid : value < 0 ∨ 256 ≤ value)
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments (byteValues output capacity position value) before) :
    ∃ after, Evaluates program.core caller (.call checked.source.function.id arguments) (.signed .i32 (-1)) after ∧
      CellEffect CellSet.empty before after := by
  let bindings := byteBindings output capacity position value
  let callee := enterCall before bindings
  have locals (index : Fin 4) : callee.local? index.val = some ((byteValues output capacity position value).get index) :=
    enterCall_parameterBindings_matches wellFormed index
  have valueRead : callee.local? 3 = some (.signed .i32 value) := locals ⟨3, by decide⟩
  have negative : Evaluates program.core callee (binary .lessEqual (read 3) negativeOne)
      (.boolean (decide (value ≤ -1))) callee := by
    apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates program.core valueRead)
      (negativeOne_evaluates program.core callee)
    simp [evalBinaryValue, evalSignedBinary]
  have tooLarge : Evaluates program.core callee (binary .greaterEqual (read 3) (number 256))
      (.boolean (decide (256 ≤ value))) callee := by
    apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates program.core valueRead)
      (show Evaluates program.core callee (number 256) (.signed .i32 256) callee from ⟨1, rfl⟩)
    simp [evalBinaryValue, evalSignedBinary]
  have guard := evaluatesPureLogicalOr negative tooLarge
  have rejected : (decide (value ≤ -1) || decide (256 ≤ value)) = true := by
    rcases invalid with negative | large
    · have bad : value ≤ -1 := by omega
      simp [bad]
    · simp [large]
  rw [rejected] at guard
  have run : Executes program.core callee (hexByteBody byte.source.function.id digit.source.function.id)
      (.returned (some (.signed .i32 (-1)))) callee :=
    executesSequenceReturned (executesIfTrue guard
      (executesSequenceReturned (executesReturnValue (negativeOne_evaluates program.core callee))))
  exact ⟨restoreLocals before callee, checked.call wellFormed argumentsResult (bindings := bindings) rfl run
    (CellEffect.refl (enterCall_preserves_wellFormed wellFormed))⟩

theorem hexBytePosition_success (position capacity : Nat) (room : position + 2 ≤ capacity) :
    hexBytePosition capacity position = (position + 2 : Nat) := by
  have first : 0 ≤ (position : Int) ∧ (position : Int) < capacity := by omega
  have second : 0 ≤ (position : Int) + 1 ∧ (position : Int) + 1 < capacity := by omega
  simp only [hexBytePosition, nextPosition, if_pos first, if_pos second]
  omega

theorem hexByteOutput_length : (hexByteOutput original capacity position value).length = original.length := by
  simp only [hexByteOutput, appended_length]

end Lanius.Extraction.CompactOutput
