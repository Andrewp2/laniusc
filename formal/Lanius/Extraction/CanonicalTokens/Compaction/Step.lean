import Lanius.Extraction.CanonicalTokens.Compaction.Filter

namespace Lanius.Extraction.CanonicalTokens.Compaction

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

def stepWrites (recordsCell outputCell inputCell : CellId) : CellSet :=
  CellSet.union (CellSet.union (CellSet.singleton recordsCell) (CellSet.singleton outputCell))
    (CellSet.singleton inputCell)

/-- One complete source iteration, including both scoped reads and the input
cursor update. Bounds cover the actual capacity, not an exact-size buffer. -/
theorem executes_input_body (trivia : Trivia.Checked program triviaId)
    (kind : Kind.Checked program kindId keywordId matcher)
    (storage : Storage before sourceCell recordsCell source records)
    (rawKind : Int) (start width input output : Nat) (inputCell outputCell : CellId)
    (kindSelected : records[3 * input]? = some rawKind)
    (startSelected : records[3 * input + 1]? = some (Int.ofNat start))
    (endSelected : records[3 * input + 2]? = some (Int.ofNat (start + width)))
    (inputOwned : (Assertion.localPointsTo 3 inputCell (some (.signed .i32 input))).holds before)
    (outputOwned : (Assertion.localPointsTo 4 outputCell (some (.signed .i32 output))).holds before)
    (recordsOutput : recordsCell ≠ outputCell) (recordsInput : recordsCell ≠ inputCell)
    (inputOutput : inputCell ≠ outputCell)
    (sourceBound : start + width ≤ source.length)
    (inputBound : 3 * input + 2 < records.length) (rowBound : 3 * output + 2 < records.length) :
    ∃ after, Executes program before (inputBody triviaId kindId) .next after ∧
      after.cellEntry? recordsCell = some { id := recordsCell, value := some (.array
        (signedI32Values (filteredRecords source records rawKind start width output))) } ∧
      (Assertion.localPointsTo 3 inputCell (some (.signed .i32 (input + 1 : Nat)))).holds after ∧
      (Assertion.localPointsTo 4 outputCell (some (.signed .i32 (filteredCount rawKind output)))).holds after ∧
      CellEffect (stepWrites recordsCell outputCell inputCell) before after := by
  let withRow := before.bindLocal 5 (.signed .i32 (3 * input : Nat))
  let ready := withRow.bindLocal 6 (.signed .i32 rawKind)
  have rowStorage : Storage withRow sourceCell recordsCell source records :=
    storage.bind 5 _ (by decide) (by decide)
  have readyStorage : Storage ready sourceCell recordsCell source records :=
    rowStorage.bind 6 _ (by decide) (by decide)
  have inputResult : Evaluates program before (.local 3) (.signed .i32 input) before :=
    ⟨1, evalLocal_of_local 0 program before 3 _ (Assertion.localPointsTo_local _ _ _ _ inputOwned)⟩
  have rowRead : Evaluates program before (row (.local 3)) (.signed .i32 (3 * input : Nat)) before := by
    have multiplied := evaluatesNatI32Multiply (rightValue := 3) inputResult
      (show Evaluates program before (literal 3) (.signed .i32 3) before from ⟨1, rfl⟩)
      (by have := storage.recordsFit; omega)
    simpa [row, Int.ofNat_eq_natCast, Nat.mul_comm] using multiplied
  have rowLocal : withRow.local? 5 = some (.signed .i32 (3 * input : Nat)) :=
    bindLocal_finds_local before 5 _ storage.wellFormed
  have sliceResult : Evaluates program withRow (.local 1)
      (.slice (.scalar (.signed .i32)) recordsCell [] 0 records.length) withRow :=
    ⟨1, evalLocal_of_local 0 program withRow 1 _ rowStorage.recordsLocal⟩
  have indexResult : Evaluates program withRow (.local 5) (.signed .i32 (3 * input : Nat)) withRow :=
    ⟨1, evalLocal_of_local 0 program withRow 5 _ rowLocal⟩
  have kindRead : Evaluates program withRow (read (.local 5)) (.signed .i32 rawKind) withRow := by
    have bound : 3 * input < records.length := by omega
    have readResult := evaluatesSignedI32SliceIndex program withRow withRow withRow records
      (.local 1) (.local 5) recordsCell (3 * input) bound sliceResult indexResult rowStorage.recordsContents
    have actual : records.get ⟨3 * input, bound⟩ = rawKind := by
      simpa only [List.getElem?_eq_getElem bound, Option.some.injEq, List.get_eq_getElem] using kindSelected
    simpa only [read, actual] using readResult
  have rowReady : ready.local? 5 = some (.signed .i32 (3 * input : Nat)) :=
    (bindLocal_preserves_other_local rowStorage.wellFormed (show (6 : VarId) ≠ 5 by decide)).trans rowLocal
  have kindReady : ready.local? 6 = some (.signed .i32 rawKind) :=
    bindLocal_finds_local withRow 6 _ rowStorage.wellFormed
  have inputAtRow := bindLocal_preserves_localPointsTo_of_ne before 5 3
    (.signed .i32 (3 * input : Nat)) inputCell _ storage.wellFormed (by decide) inputOwned
  have inputReady := bindLocal_preserves_localPointsTo_of_ne withRow 6 3
    (.signed .i32 rawKind) inputCell _ rowStorage.wellFormed (by decide) inputAtRow
  have outputAtRow := bindLocal_preserves_localPointsTo_of_ne before 5 4
    (.signed .i32 (3 * input : Nat)) outputCell _ storage.wellFormed (by decide) outputOwned
  have outputReady := bindLocal_preserves_localPointsTo_of_ne withRow 6 4
    (.signed .i32 rawKind) outputCell _ rowStorage.wellFormed (by decide) outputAtRow
  obtain ⟨filtered, branch, contents, outputFiltered, filterEffect⟩ := executes_filter trivia kind readyStorage
    rawKind start width (3 * input) output outputCell kindReady rowReady startSelected endSelected
    outputReady recordsOutput sourceBound inputBound rowBound
  have inputStill := filterEffect.preserves_localPointsTo readyStorage.wellFormed inputReady
    (by simpa [CellSet.union, CellSet.singleton, eq_comm] using And.intro recordsInput inputOutput)
  obtain ⟨completed, incremented, completedWF, inputAfter, incrementEffect⟩ := executesIncrementOwnedI32Local
    program filtered 3 inputCell input filterEffect.wellFormed inputStill (by have := storage.recordsFit; omega)
  have afterContents := incrementEffect.preserves_entry filterEffect.wellFormed contents
    (by simpa [CellSet.singleton] using recordsInput)
  have outputAfter := incrementEffect.preserves_localPointsTo filterEffect.wellFormed outputFiltered
    (by simpa [CellSet.singleton, eq_comm] using inputOutput)
  have effect : CellEffect (stepWrites recordsCell outputCell inputCell) ready completed :=
    (filterEffect.weaken CellSet.subset_union_left).trans
      ((CellEffect.ofModifiesOnly incrementEffect completedWF).weaken CellSet.subset_union_right)
  have closeKind := CellEffect.closeLocal withRow 6 (.signed .i32 rawKind) rowStorage.wellFormed effect
  have closeRow := CellEffect.closeLocal before 5 (.signed .i32 (3 * input : Nat)) storage.wellFormed closeKind
  exact ⟨_, executesLetLocal rowRead (executesLetLocal kindRead (executesSequence branch incremented)),
    afterContents, ⟨inputOwned.1, inputAfter.2⟩, ⟨outputOwned.1, outputAfter.2⟩, closeRow⟩

end Lanius.Extraction.CanonicalTokens.Compaction
