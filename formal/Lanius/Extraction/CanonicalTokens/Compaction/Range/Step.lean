import Lanius.Extraction.CanonicalTokens.Compaction.Range.Mark

namespace Lanius.Extraction.CanonicalTokens.Compaction.Range

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

/-- One complete second-pass iteration, with fresh row temporaries and the
owned scan cursor. Only the current tag and cursor may change. -/
theorem executes_body (table : Table program tokens)
    (storage : Storage before sourceCell recordsCell source records)
    (index : Nat) (cursorCell : CellId) (currentKind nextKind nextStart currentEnd : Int)
    (cursor : (Assertion.localPointsTo 10 cursorCell (some (.signed .i32 index))).holds before)
    (distinct : recordsCell ≠ cursorCell)
    (bound : 3 * index + 4 < records.length)
    (currentSelected : records[3 * index]? = some currentKind)
    (nextSelected : records[3 * index + 3]? = some nextKind)
    (nextStartSelected : records[3 * index + 4]? = some nextStart)
    (currentEndSelected : records[3 * index + 2]? = some currentEnd) :
    ∃ after, Executes program before (rangeBody tokens) .next after ∧
      after.cellEntry? recordsCell = some { id := recordsCell, value := some (.array
        (signedI32Values (marked records (3 * index) currentKind nextKind nextStart currentEnd))) } ∧
      (Assertion.localPointsTo 10 cursorCell (some (.signed .i32 (index + 1 : Nat)))).holds after ∧
      CellEffect (CellSet.union (CellSet.singleton recordsCell) (CellSet.singleton cursorCell)) before after := by
  let withCurrent := before.bindLocal 11 (.signed .i32 (3 * index : Nat))
  let ready := withCurrent.bindLocal 12 (.signed .i32 (3 * index + 3 : Nat))
  have currentStorage : Storage withCurrent sourceCell recordsCell source records :=
    storage.bind 11 _ (by decide) (by decide)
  have readyStorage : Storage ready sourceCell recordsCell source records :=
    currentStorage.bind 12 _ (by decide) (by decide)
  have cursorResult : Evaluates program before (.local 10) (.signed .i32 index) before :=
    ⟨1, evalLocal_of_local 0 program before 10 _ (Assertion.localPointsTo_local _ _ _ _ cursor)⟩
  have currentRead : Evaluates program before (row (.local 10)) (.signed .i32 (3 * index : Nat)) before := by
    have multiplied := evaluatesNatI32Multiply (rightValue := 3) cursorResult
      (show Evaluates program before (literal 3) (.signed .i32 3) before from ⟨1, rfl⟩)
      (by have := storage.recordsFit; omega)
    simpa [row, Int.ofNat_eq_natCast, Nat.mul_comm] using multiplied
  have currentLocal : withCurrent.local? 11 = some (.signed .i32 (3 * index : Nat)) :=
    bindLocal_finds_local before 11 _ storage.wellFormed
  have currentResult : Evaluates program withCurrent (.local 11) (.signed .i32 (3 * index : Nat)) withCurrent :=
    ⟨1, evalLocal_of_local 0 program withCurrent 11 _ currentLocal⟩
  have nextRead : Evaluates program withCurrent (add (.local 11) (literal 3))
      (.signed .i32 (3 * index + 3 : Nat)) withCurrent :=
    evaluatesNatI32Add currentResult (show Evaluates program withCurrent (literal 3) (.signed .i32 3) withCurrent from ⟨1, rfl⟩)
      (by have := storage.recordsFit; omega)
  have currentReady : ready.local? 11 = some (.signed .i32 (3 * index : Nat)) :=
    (bindLocal_preserves_other_local currentStorage.wellFormed (show (12 : VarId) ≠ 11 by decide)).trans currentLocal
  have nextReady : ready.local? 12 = some (.signed .i32 (3 * index + 3 : Nat)) :=
    bindLocal_finds_local withCurrent 12 _ currentStorage.wellFormed
  have cursorAtCurrent := bindLocal_preserves_localPointsTo_of_ne before 11 10
    (.signed .i32 (3 * index : Nat)) cursorCell _ storage.wellFormed (by decide) cursor
  have cursorReady := bindLocal_preserves_localPointsTo_of_ne withCurrent 12 10
    (.signed .i32 (3 * index + 3 : Nat)) cursorCell _ currentStorage.wellFormed (by decide) cursorAtCurrent
  obtain ⟨markedState, run, contents, markEffect⟩ := executes_mark table readyStorage
    (3 * index) (3 * index + 3) currentKind nextKind nextStart currentEnd currentReady nextReady
    (by omega) (by omega) currentSelected nextSelected (by simpa [Nat.add_assoc] using nextStartSelected) currentEndSelected
  have cursorStill := markEffect.preserves_localPointsTo readyStorage.wellFormed cursorReady
    (by simpa [CellSet.singleton, eq_comm] using distinct)
  obtain ⟨completed, incremented, completedWF, cursorAfter, incrementEffect⟩ := executesIncrementOwnedI32Local
    program markedState 10 cursorCell index markEffect.wellFormed cursorStill (by have := storage.recordsFit; omega)
  have afterContents := incrementEffect.preserves_entry markEffect.wellFormed contents
    (by simpa [CellSet.singleton] using distinct)
  have effect := (markEffect.weaken CellSet.subset_union_left).trans
    ((CellEffect.ofModifiesOnly incrementEffect completedWF).weaken CellSet.subset_union_right)
  have closeNext := CellEffect.closeLocal withCurrent 12 (.signed .i32 (3 * index + 3 : Nat)) currentStorage.wellFormed effect
  have closeCurrent := CellEffect.closeLocal before 11 (.signed .i32 (3 * index : Nat)) storage.wellFormed closeNext
  exact ⟨_, executesLetLocal currentRead (executesLetLocal nextRead (executesSequence run incremented)),
    afterContents, ⟨cursor.1, cursorAfter.2⟩, closeCurrent⟩

end Lanius.Extraction.CanonicalTokens.Compaction.Range
