import Lanius.Extraction.CanonicalTokens.Compaction.Range.Condition

namespace Lanius.Extraction.CanonicalTokens.Compaction.Range

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

def marked (records : List Int) (currentRow : Nat) (currentKind nextKind nextStart currentEnd : Int) : List Int :=
  if isPair currentKind nextKind nextStart currentEnd then records.set currentRow 189 else records

theorem executes_mark (table : Table program tokens)
    (storage : Storage before sourceCell recordsCell source records)
    (currentRow nextRow : Nat) (currentKind nextKind nextStart currentEnd : Int)
    (currentLocal : before.local? 11 = some (.signed .i32 currentRow))
    (nextLocal : before.local? 12 = some (.signed .i32 nextRow))
    (currentBound : currentRow + 2 < records.length) (nextBound : nextRow + 1 < records.length)
    (currentSelected : records[currentRow]? = some currentKind)
    (nextSelected : records[nextRow]? = some nextKind)
    (nextStartSelected : records[nextRow + 1]? = some nextStart)
    (currentEndSelected : records[currentRow + 2]? = some currentEnd) :
    ∃ after, Executes program before (rangeMark tokens) .next after ∧
      after.cellEntry? recordsCell = some { id := recordsCell, value := some (.array
        (signedI32Values (marked records currentRow currentKind nextKind nextStart currentEnd))) } ∧
      CellEffect (CellSet.singleton recordsCell) before after := by
  have condition := evaluates_condition table storage currentRow nextRow currentKind nextKind nextStart currentEnd
    currentLocal nextLocal currentBound nextBound currentSelected nextSelected nextStartSelected currentEndSelected
  cases selected : isPair currentKind nextKind nextStart currentEnd with
  | false =>
      have no : Evaluates program before (rangeCondition tokens) (.boolean false) before := by
        simpa only [selected] using condition
      refine ⟨before, executesIfFalse no (executesSkip program before), ?_, CellEffect.refl storage.wellFormed⟩
      simpa only [marked, selected, Bool.false_eq_true, if_false] using storage.recordsContents
  | true =>
      have yes : Evaluates program before (rangeCondition tokens) (.boolean true) before := by
        simpa only [selected] using condition
      have indexResult : Evaluates program before (.local 11) (.signed .i32 currentRow) before :=
        ⟨1, evalLocal_of_local 0 program before 11 _ currentLocal⟩
      obtain ⟨after, assignment, contents, effect⟩ := evaluatesSliceStore program before before records
        1 (.local 11) (.constant tokens.inclusive) recordsCell currentRow 189 storage.wellFormed (by omega)
        storage.recordsLocal indexResult (constantResult program before tokens.inclusive 189 table.inclusiveFound)
        (CellEffect.refl storage.wellFormed) storage.recordsContents
      refine ⟨after, executesIfTrue yes (executesSequence (executesExpression assignment) (executesSkip program after)), ?_, effect⟩
      simpa only [marked, selected, Bool.true_eq, if_true] using contents

end Lanius.Extraction.CanonicalTokens.Compaction.Range
