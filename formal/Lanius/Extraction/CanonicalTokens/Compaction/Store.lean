import Lanius.Extraction.CanonicalTokens.Compaction.Source
import Lanius.Extraction.CanonicalTokens.Compaction.Buffer
import Lanius.Separation.SliceStore

namespace Lanius.Extraction.CanonicalTokens.Compaction

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts

private theorem localResult (program : Program) (before : State) (id : VarId) (value : Value)
    (found : before.local? id = some value) : Evaluates program before (.local id) value before :=
  ⟨1, evalLocal_of_local 0 program before id value found⟩

/-- The first row write calls the proved classifier before updating the buffer.
Borrowed keyword storage may grow, but every other caller cell is preserved. -/
theorem executes_kind_store (checked : Kind.Checked program kindId keywordId matcher)
    (before : State) (sourceCell recordsCell : CellId) (source records : List Int)
    (rawKind : Int) (start width outputRow : Nat)
    (wellFormed : StateWellFormed before)
    (sourceLocal : before.local? 0 = some (.slice (.scalar (.signed .i32)) sourceCell [] 0 source.length))
    (recordsLocal : before.local? 1 = some (.slice (.scalar (.signed .i32)) recordsCell [] 0 records.length))
    (kindLocal : before.local? 6 = some (.signed .i32 rawKind))
    (startLocal : before.local? 7 = some (.signed .i32 start))
    (endLocal : before.local? 8 = some (.signed .i32 (start + width)))
    (rowLocal : before.local? 9 = some (.signed .i32 outputRow))
    (sourceContents : before.cellEntry? sourceCell = some {
      id := sourceCell, value := some (.array (signedI32Values source)) })
    (recordsContents : before.cellEntry? recordsCell = some {
      id := recordsCell, value := some (.array (signedI32Values records)) })
    (sourceBound : start + width ≤ source.length) (sourceFits : source.length ≤ 2147483647)
    (rowBound : outputRow < records.length) :
    ∃ after, Executes program before
        (store (.local 9) (.call kindId [.local 0, .local 6, .local 7, .local 8])) .next after ∧
      after.cellEntry? recordsCell = some { id := recordsCell, value := some (.array
        (signedI32Values (records.set outputRow (Kind.result source rawKind start width)))) } ∧
      CellEffect (CellSet.singleton recordsCell) before after := by
  have argumentsResult := ArgumentsEvaluateTo.cons (localResult program before 0 _ sourceLocal)
    (ArgumentsEvaluateTo.cons (localResult program before 6 _ kindLocal)
      (ArgumentsEvaluateTo.cons (localResult program before 7 _ startLocal)
        (ArgumentsEvaluateTo.singleton (localResult program before 8 _ endLocal))))
  obtain ⟨classified, classification, classificationEffect⟩ := checked.evaluates_call
    before sourceCell source rawKind start width _ wellFormed sourceContents argumentsResult sourceBound sourceFits
  obtain ⟨after, assignment, contents, effect⟩ := evaluatesSliceStore program before classified records
    1 (.local 9) _ recordsCell outputRow (Kind.result source rawKind start width)
    wellFormed rowBound recordsLocal (localResult program before 9 _ rowLocal)
    classification classificationEffect recordsContents
  exact ⟨after, executesExpression assignment, contents, effect⟩

private theorem executes_span_store (program : Program) (before : State) (recordsCell : CellId)
    (records : List Int) (outputRow offset : Nat) (valueId : VarId) (value : Int)
    (wellFormed : StateWellFormed before)
    (recordsLocal : before.local? 1 = some (.slice (.scalar (.signed .i32)) recordsCell [] 0 records.length))
    (rowLocal : before.local? 9 = some (.signed .i32 outputRow))
    (valueLocal : before.local? valueId = some (.signed .i32 value))
    (contents : before.cellEntry? recordsCell = some {
      id := recordsCell, value := some (.array (signedI32Values records)) })
    (bound : outputRow + offset < records.length) (fits : records.length ≤ 2147483647) :
    ∃ after, Executes program before
        (store (add (.local 9) (literal offset)) (.local valueId)) .next after ∧
      after.cellEntry? recordsCell = some { id := recordsCell, value := some (.array
        (signedI32Values (records.set (outputRow + offset) value))) } ∧
      CellEffect (CellSet.singleton recordsCell) before after := by
  have indexResult := evaluatesNatI32Add (localResult program before 9 _ rowLocal)
    (show Evaluates program before (literal offset) (.signed .i32 offset) before from ⟨1, rfl⟩) (by omega)
  obtain ⟨after, assignment, afterContents, effect⟩ := evaluatesSliceStore program before before records
    1 _ (.local valueId) recordsCell (outputRow + offset) value wellFormed bound recordsLocal indexResult
    (localResult program before valueId _ valueLocal) (CellEffect.refl wellFormed) contents
  exact ⟨after, executesExpression assignment, afterContents, effect⟩

/-- All three writes of a kept token, evaluated in source order. The result
includes the mathematical row update and the concrete caller-cell footprint. -/
theorem executes_row_stores (checked : Kind.Checked program kindId keywordId matcher)
    (before : State) (sourceCell recordsCell : CellId) (source records : List Int)
    (rawKind : Int) (start width outputRow : Nat)
    (wellFormed : StateWellFormed before)
    (sourceLocal : before.local? 0 = some (.slice (.scalar (.signed .i32)) sourceCell [] 0 source.length))
    (recordsLocal : before.local? 1 = some (.slice (.scalar (.signed .i32)) recordsCell [] 0 records.length))
    (kindLocal : before.local? 6 = some (.signed .i32 rawKind))
    (startLocal : before.local? 7 = some (.signed .i32 start))
    (endLocal : before.local? 8 = some (.signed .i32 (start + width)))
    (rowLocal : before.local? 9 = some (.signed .i32 outputRow))
    (sourceContents : before.cellEntry? sourceCell = some {
      id := sourceCell, value := some (.array (signedI32Values source)) })
    (recordsContents : before.cellEntry? recordsCell = some {
      id := recordsCell, value := some (.array (signedI32Values records)) })
    (sourceBound : start + width ≤ source.length) (sourceFits : source.length ≤ 2147483647)
    (rowBound : outputRow + 2 < records.length) (recordsFit : records.length ≤ 2147483647) :
    ∃ after, (∀ rest completion final, Executes program after rest completion final →
        Executes program before (rowStores kindId rest) completion final) ∧
      after.cellEntry? recordsCell = some { id := recordsCell, value := some (.array
        (signedI32Values (writeRow records outputRow (Kind.result source rawKind start width) start (start + width)))) } ∧
      CellEffect (CellSet.singleton recordsCell) before after := by
  obtain ⟨first, firstRun, firstContents, firstEffect⟩ := executes_kind_store checked before
    sourceCell recordsCell source records rawKind start width outputRow wellFormed sourceLocal recordsLocal
    kindLocal startLocal endLocal rowLocal sourceContents recordsContents sourceBound sourceFits (by omega)
  have firstRecords := firstEffect.preserves_local_of_distinct_value wellFormed recordsLocal recordsContents (by intro h; cases h)
  have firstRow := firstEffect.preserves_local_of_distinct_value wellFormed rowLocal recordsContents (by intro h; cases h)
  have firstStart := firstEffect.preserves_local_of_distinct_value wellFormed startLocal recordsContents (by intro h; cases h)
  obtain ⟨second, secondRun, secondContents, secondEffect⟩ := executes_span_store program first recordsCell
    (records.set outputRow (Kind.result source rawKind start width)) outputRow 1 7 start
    firstEffect.wellFormed (by simpa using firstRecords) firstRow firstStart firstContents
    (by simpa using (show outputRow + 1 < records.length by omega)) (by simpa using recordsFit)
  have throughSecond := firstEffect.trans secondEffect
  have secondRecords := throughSecond.preserves_local_of_distinct_value wellFormed recordsLocal recordsContents (by intro h; cases h)
  have secondRow := throughSecond.preserves_local_of_distinct_value wellFormed rowLocal recordsContents (by intro h; cases h)
  have secondEnd := throughSecond.preserves_local_of_distinct_value wellFormed endLocal recordsContents (by intro h; cases h)
  obtain ⟨after, thirdRun, thirdContents, thirdEffect⟩ := executes_span_store program second recordsCell
    ((records.set outputRow (Kind.result source rawKind start width)).set (outputRow + 1) start)
    outputRow 2 8 (start + width) secondEffect.wellFormed (by simpa using secondRecords) secondRow
    secondEnd secondContents (by simpa using rowBound) (by simpa using recordsFit)
  exact ⟨after, fun _ _ _ tailRun => executesSequence firstRun (executesSequence secondRun
    (executesSequence thirdRun tailRun)), thirdContents, throughSecond.trans thirdEffect⟩

end Lanius.Extraction.CanonicalTokens.Compaction
