import Lanius.Extraction.CanonicalTokens.Compaction.Storage

namespace Lanius.Extraction.CanonicalTokens.Compaction

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

theorem executes_writes_and_increment (checked : Kind.Checked program kindId keywordId matcher)
    (storage : Storage before sourceCell recordsCell source records)
    (rawKind : Int) (start width output : Nat) (outputCell : CellId)
    (kindLocal : before.local? 6 = some (.signed .i32 rawKind))
    (startLocal : before.local? 7 = some (.signed .i32 start))
    (endLocal : before.local? 8 = some (.signed .i32 (start + width)))
    (rowLocal : before.local? 9 = some (.signed .i32 (3 * output)))
    (outputOwned : (Assertion.localPointsTo 4 outputCell (some (.signed .i32 output))).holds before)
    (distinct : recordsCell ≠ outputCell)
    (sourceBound : start + width ≤ source.length) (rowBound : 3 * output + 2 < records.length) :
    ∃ after, Executes program before (rowStores kindId (statements [increment 4])) .next after ∧
      after.cellEntry? recordsCell = some { id := recordsCell, value := some (.array
        (signedI32Values (writeRow records (3 * output) (Kind.result source rawKind start width) start (start + width)))) } ∧
      (Assertion.localPointsTo 4 outputCell (some (.signed .i32 (output + 1 : Nat)))).holds after ∧
      CellEffect (CellSet.union (CellSet.singleton recordsCell) (CellSet.singleton outputCell)) before after := by
  obtain ⟨stored, stores, contents, storesEffect⟩ := executes_row_stores checked before sourceCell recordsCell
    source records rawKind start width (3 * output) storage.wellFormed storage.sourceLocal storage.recordsLocal
    kindLocal startLocal endLocal rowLocal storage.sourceContents storage.recordsContents sourceBound
    storage.sourceFits rowBound storage.recordsFit
  have ownedStill := storesEffect.preserves_localPointsTo storage.wellFormed outputOwned
    (by simpa [CellSet.singleton, eq_comm] using distinct)
  obtain ⟨after, incremented, afterWF, ownedAfter, incrementEffect⟩ := executesIncrementOwnedI32Local
    program stored 4 outputCell output storesEffect.wellFormed ownedStill (by have := storage.recordsFit; omega)
  have afterContents := incrementEffect.preserves_entry storesEffect.wellFormed contents
    (by simpa [CellSet.singleton] using distinct)
  have combined := (storesEffect.weaken CellSet.subset_union_left).trans
    ((CellEffect.ofModifiesOnly incrementEffect afterWF).weaken CellSet.subset_union_right)
  exact ⟨after, stores _ _ _ incremented,
    afterContents, ownedAfter, combined⟩

/-- The complete kept-token branch, including its three scoped temporaries. -/
theorem executes_kept_body (checked : Kind.Checked program kindId keywordId matcher)
    (storage : Storage before sourceCell recordsCell source records)
    (rawKind : Int) (start width inputRow output : Nat) (outputCell : CellId)
    (kindLocal : before.local? 6 = some (.signed .i32 rawKind))
    (inputLocal : before.local? 5 = some (.signed .i32 inputRow))
    (startSelected : records[inputRow + 1]? = some (Int.ofNat start))
    (endSelected : records[inputRow + 2]? = some (Int.ofNat (start + width)))
    (outputOwned : (Assertion.localPointsTo 4 outputCell (some (.signed .i32 output))).holds before)
    (distinct : recordsCell ≠ outputCell)
    (sourceBound : start + width ≤ source.length)
    (inputBound : inputRow + 2 < records.length) (rowBound : 3 * output + 2 < records.length) :
    ∃ after, Executes program before (keptBody kindId) .next after ∧
      after.cellEntry? recordsCell = some { id := recordsCell, value := some (.array
        (signedI32Values (writeRow records (3 * output) (Kind.result source rawKind start width) start (start + width)))) } ∧
      (Assertion.localPointsTo 4 outputCell (some (.signed .i32 (output + 1 : Nat)))).holds after ∧
      CellEffect (CellSet.union (CellSet.singleton recordsCell) (CellSet.singleton outputCell)) before after := by
  let withStart := before.bindLocal 7 (.signed .i32 start)
  let withEnd := withStart.bindLocal 8 (.signed .i32 (start + width))
  let ready := withEnd.bindLocal 9 (.signed .i32 (3 * output))
  have startStorage : Storage withStart sourceCell recordsCell source records :=
    storage.bind 7 _ (by decide) (by decide)
  have endStorage : Storage withEnd sourceCell recordsCell source records :=
    startStorage.bind 8 _ (by decide) (by decide)
  have readyStorage : Storage ready sourceCell recordsCell source records :=
    endStorage.bind 9 _ (by decide) (by decide)
  have startRead := storage.readLocal (program := program) 5 inputRow 1 start inputLocal (by omega) startSelected
  have inputStill : withStart.local? 5 = some (.signed .i32 inputRow) :=
    (bindLocal_preserves_other_local storage.wellFormed (show (7 : VarId) ≠ 5 by decide)).trans inputLocal
  have endRead := startStorage.readLocal (program := program) 5 inputRow 2 (start + width) inputStill inputBound endSelected
  have outputAtStart := bindLocal_preserves_localPointsTo_of_ne before 7 4
    (.signed .i32 start) outputCell _ storage.wellFormed (by decide) outputOwned
  have outputAtEnd := bindLocal_preserves_localPointsTo_of_ne withStart 8 4
    (.signed .i32 (start + width)) outputCell _ startStorage.wellFormed (by decide) outputAtStart
  have outputReady := bindLocal_preserves_localPointsTo_of_ne withEnd 9 4
    (.signed .i32 (3 * output)) outputCell _ endStorage.wellFormed (by decide) outputAtEnd
  have outputResult : Evaluates program withEnd (.local 4) (.signed .i32 output) withEnd :=
    ⟨1, evalLocal_of_local 0 program withEnd 4 _ (Assertion.localPointsTo_local _ _ _ _ outputAtEnd)⟩
  have rowRead : Evaluates program withEnd (row (.local 4)) (.signed .i32 (3 * output)) withEnd := by
    have multiplied := evaluatesNatI32Multiply (rightValue := 3) outputResult
      (show Evaluates program withEnd (literal 3) (.signed .i32 3) withEnd from ⟨1, rfl⟩)
      (by have := storage.recordsFit; omega)
    simpa [row, Int.ofNat_eq_natCast, Int.natCast_mul, Int.mul_comm] using multiplied
  have kindAtStart : withStart.local? 6 = some (.signed .i32 rawKind) :=
    (bindLocal_preserves_other_local storage.wellFormed (show (7 : VarId) ≠ 6 by decide)).trans kindLocal
  have kindAtEnd : withEnd.local? 6 = some (.signed .i32 rawKind) :=
    (bindLocal_preserves_other_local startStorage.wellFormed (show (8 : VarId) ≠ 6 by decide)).trans kindAtStart
  have kindReady : ready.local? 6 = some (.signed .i32 rawKind) :=
    (bindLocal_preserves_other_local endStorage.wellFormed (show (9 : VarId) ≠ 6 by decide)).trans kindAtEnd
  have startAtEnd : withEnd.local? 7 = some (.signed .i32 start) :=
    (bindLocal_preserves_other_local startStorage.wellFormed (show (8 : VarId) ≠ 7 by decide)).trans
      (bindLocal_finds_local before 7 _ storage.wellFormed)
  have startReady : ready.local? 7 = some (.signed .i32 start) :=
    (bindLocal_preserves_other_local endStorage.wellFormed (show (9 : VarId) ≠ 7 by decide)).trans startAtEnd
  have endReady : ready.local? 8 = some (.signed .i32 (start + width)) :=
    (bindLocal_preserves_other_local endStorage.wellFormed (show (9 : VarId) ≠ 8 by decide)).trans
      (bindLocal_finds_local withStart 8 _ startStorage.wellFormed)
  have rowReady : ready.local? 9 = some (.signed .i32 (3 * output)) :=
    bindLocal_finds_local withEnd 9 _ endStorage.wellFormed
  obtain ⟨completed, run, contents, owned, effect⟩ := executes_writes_and_increment checked readyStorage
    rawKind start width output outputCell kindReady startReady endReady rowReady outputReady distinct sourceBound rowBound
  have closeRow := CellEffect.closeLocal withEnd 9 (.signed .i32 (3 * output)) endStorage.wellFormed effect
  have closeEnd := CellEffect.closeLocal withStart 8 (.signed .i32 (start + width)) startStorage.wellFormed closeRow
  have closeStart := CellEffect.closeLocal before 7 (.signed .i32 start) storage.wellFormed closeEnd
  exact ⟨_, executesLetLocal startRead (executesLetLocal endRead (executesLetLocal rowRead run)),
    contents, ⟨outputOwned.1, owned.2⟩, closeStart⟩

end Lanius.Extraction.CanonicalTokens.Compaction
