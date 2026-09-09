import Lanius.Extraction.CompactOutput.Word.Assign
import Lanius.Extraction.CompactOutput.Word.Chunks

namespace Lanius.Extraction.CompactOutput.Nodes

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

def tagWrite (wordId : FunctionId) : Expr := Word.assignCall wordId 8 (read 5) (read 6) (read 15)
def payloadWrite (wordId : FunctionId) : Expr :=
  Word.assignCall wordId 8 (read 5) (read 6) (read 16)
def childEncoding (first : Nat) (second : Nat) : List Nat :=
  hexDigits first 8 ++ hexDigits second 8

/-- Both writes execute, even when the first runs out of capacity. Their
effects compose to exactly the flat childEncoding, not merely an accepted buffer. -/
theorem write_child (word : Word.Checked program byte digit)
    (first second capacity : Nat) (position : Int)
    (wellFormed : StateWellFormed before)
    (firstFit : first ≤ 2147483647) (secondFit : second ≤ 2147483647)
    (capacityBound : capacity ≤ original.length) (capacityFit : capacity ≤ 2147483647)
    (cursor : (Assertion.localPointsTo 8 cursorCell (some (.signed .i32 position))).holds before)
    (outputRead : before.local? 5 = some (.slice i32 outputCell [] 0 original.length))
    (capacityRead : before.local? 6 = some (.signed .i32 capacity))
    (firstRead : before.local? 15 = some (.signed .i32 first))
    (secondRead : before.local? 16 = some (.signed .i32 second))
    (stable : ∀ id ∈ [5, 6, 16], ∀ cell, before.cellId? id = some cell → cell ≠ cursorCell)
    (backing : before.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values original)) }) :
    ∃ middle after,
      Evaluates program.core before (tagWrite word.source.function.id) .unit middle ∧
      Evaluates program.core middle (payloadWrite word.source.function.id) .unit after ∧
      (Assertion.localPointsTo 8 cursorCell
        (some (.signed .i32 (appendAll capacity (childEncoding first second) position original).position))).holds after ∧
      after.cellEntry? outputCell = some {
        id := outputCell, value := some (.array (signedI32Values
          (appendAll capacity (childEncoding first second) position original).contents)) } ∧
      CellEffect (CellSet.union (CellSet.singleton outputCell) (CellSet.singleton cursorCell)) before after := by
  obtain ⟨middle, firstRun, nextCursor, nextBacking, firstEffect⟩ := Word.assign_word word position capacity first
    wellFormed capacityBound capacityFit firstFit cursor backing (local_evaluates program.core outputRead)
    (local_evaluates program.core capacityRead) (local_evaluates program.core firstRead)
  have keep {id : VarId} {value : Value} (member : id ∈ [5, 6, 16])
      (found : before.local? id = some value) (different : value ≠ .array (signedI32Values original)) :
      middle.local? id = some value := by
    apply firstEffect.preserves_local wellFormed found
    intro cell binding changed
    rcases changed with output | cursor
    · exact local_cell_ne_of_distinct_value found backing different binding output
    · exact stable id member cell binding cursor
  have nextOutput : middle.local? 5 = some (.slice i32 outputCell [] 0
      (appendAll capacity (hexDigits first 8) position original).contents.length) := by
    simpa only [appendAll_length] using keep (by simp) outputRead (by intro same; cases same)
  have nextCapacity := keep (by simp) capacityRead (by intro same; cases same)
  have nextSecond := keep (by simp) secondRead (by intro same; cases same)
  obtain ⟨after, secondRun, finalCursor, finalBacking, secondEffect⟩ := Word.assign_word word
    (appendAll capacity (hexDigits first 8) position original).position capacity second
    firstEffect.wellFormed (by simpa only [appendAll_length] using capacityBound) capacityFit secondFit
    nextCursor nextBacking (local_evaluates program.core nextOutput)
    (local_evaluates program.core nextCapacity) (local_evaluates program.core nextSecond)
  have combined := Word.appendAll_following_word capacity second (hexDigits first 8) position original
  exact ⟨middle, after, firstRun, secondRun,
    by simpa only [childEncoding, combined] using finalCursor,
    by simpa only [childEncoding, combined] using finalBacking,
    firstEffect.trans secondEffect⟩

end Lanius.Extraction.CompactOutput.Nodes

