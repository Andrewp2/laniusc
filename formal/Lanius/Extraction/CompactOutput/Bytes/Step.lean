import Lanius.Extraction.CompactOutput.Bytes.Read
import Lanius.Separation.LocalCall

namespace Lanius.Extraction.CompactOutput.Bytes

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

/-- One effectful cursor assignment, with the logical input and its spare
allocation preserved. Local/array separation follows from their values. -/
theorem assign_byte (hex : CheckedHexByte program byte digit)
    (values : List Nat) (index capacity : Nat) (position : Int)
    (wellFormed : StateWellFormed before)
    (input : I32PrefixLocal before 0 inputCell (values.map Int.ofNat))
    (indexBound : index < values.length) (byteBound : values[index] < 256)
    (indexOwned : (Assertion.localPointsTo 6 indexCell (some (.signed .i32 index))).holds before)
    (cursorOwned : (Assertion.localPointsTo 5 cursorCell (some (.signed .i32 position))).holds before)
    (distinctLocals : cursorCell ≠ indexCell) (distinctBuffers : outputCell ≠ inputCell)
    (inputLocalStable : ∀ cell, before.cellId? 0 = some cell → cell ≠ cursorCell)
    (outputRead : before.local? 2 = some (.slice i32 outputCell [] 0 original.length))
    (capacityRead : before.local? 3 = some (.signed .i32 capacity))
    (capacityBound : capacity ≤ original.length) (capacityFit : capacity ≤ 2147483647)
    (backing : before.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values original)) }) :
    ∃ after, Evaluates program.core before (assignment hex.source.function.id) .unit after ∧
      (Assertion.localPointsTo 5 cursorCell (some (.signed .i32 (hexBytePosition capacity position)))).holds after ∧
      (Assertion.localPointsTo 6 indexCell (some (.signed .i32 index))).holds after ∧
      I32PrefixLocal after 0 inputCell (values.map Int.ofNat) ∧
      after.cellEntry? outputCell = some {
        id := outputCell, value := some (.array (signedI32Values
          (hexByteOutput original capacity position values[index]))) } ∧
      CellEffect (CellSet.union (CellSet.singleton outputCell) (CellSet.singleton cursorCell)) before after := by
  have outputCursor : outputCell ≠ cursorCell := by
    intro same
    rw [same, cursorOwned.2] at backing
    cases backing
  have outputIndex : outputCell ≠ indexCell := by
    intro same
    rw [same, indexOwned.2] at backing
    cases backing
  have inputCursor : inputCell ≠ cursorCell := by
    intro same
    obtain ⟨unused, _, inputBacking⟩ := input.exists_unused
    rw [same, cursorOwned.2] at inputBacking
    cases inputBacking
  obtain ⟨written, call, contents, writeEffect⟩ := read_write hex values index capacity position
    wellFormed input indexBound byteBound (Assertion.localPointsTo_local _ _ _ _ indexOwned)
    outputRead capacityRead (Assertion.localPointsTo_local _ _ _ _ cursorOwned)
    capacityBound capacityFit backing
  have cursorStill := writeEffect.preserves_localPointsTo wellFormed cursorOwned
    (by simpa only [CellSet.singleton] using Ne.symm outputCursor)
  obtain ⟨after, assigned, cursor, effect, assignmentEffect⟩ :=
    evaluatesOwnedLocalSet cursorOwned call writeEffect cursorStill
  have indexAfter := effect.preserves_localPointsTo wellFormed indexOwned (by
    intro changed
    rcases changed with output | cursor
    · exact outputIndex output.symm
    · exact distinctLocals cursor.symm)
  have outputAfter := assignmentEffect.preserves_entry writeEffect.wellFormed contents
    (by simpa only [CellSet.singleton] using outputCursor)
  have inputAfter : I32PrefixLocal after 0 inputCell (values.map Int.ofNat) := by
    apply input.transport
    · intro physical found
      apply effect.preserves_local wellFormed found
      intro cell binding changed
      rcases changed with output | cursor
      · exact local_cell_ne_of_distinct_value found backing (by intro same; cases same) binding output
      · exact inputLocalStable cell binding cursor
    · intro stored found
      apply effect.preserves_entry wellFormed found
      intro changed
      rcases changed with output | cursor
      · exact distinctBuffers output.symm
      · exact inputCursor cursor
  exact ⟨after, assigned, cursor, indexAfter, inputAfter, outputAfter, effect⟩

end Lanius.Extraction.CompactOutput.Bytes
