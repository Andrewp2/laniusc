import Lanius.Extraction.CanonicalTokens.Compaction.Kept

namespace Lanius.Extraction.CanonicalTokens.Compaction

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

def filteredRecords (source records : List Int) (rawKind : Int) (start width output : Nat) : List Int :=
  if Trivia.result rawKind then records
  else writeRow records (3 * output) (Kind.result source rawKind start width) start (start + width)

def filteredCount (rawKind : Int) (output : Nat) : Nat :=
  if Trivia.result rawKind then output else output + 1

/-- The actual filtering branch either preserves a trivia row's storage or
executes the proved kept-token branch. No abstract callee behavior is assumed. -/
theorem executes_filter (trivia : Trivia.Checked program triviaId)
    (kind : Kind.Checked program kindId keywordId matcher)
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
    ∃ after, Executes program before (filterBranch triviaId kindId) .next after ∧
      after.cellEntry? recordsCell = some { id := recordsCell, value := some (.array
        (signedI32Values (filteredRecords source records rawKind start width output))) } ∧
      (Assertion.localPointsTo 4 outputCell (some (.signed .i32 (filteredCount rawKind output)))).holds after ∧
      CellEffect (CellSet.union (CellSet.singleton recordsCell) (CellSet.singleton outputCell)) before after := by
  have argument : Evaluates program before (.local 6) (.signed .i32 rawKind) before :=
    ⟨1, evalLocal_of_local 0 program before 6 _ kindLocal⟩
  obtain ⟨tested, called, callEffect⟩ := trivia.evaluates_call before rawKind (.local 6) storage.wellFormed argument
  have guardResult : Evaluates program before (.unary .logicalNot (.call triviaId [.local 6]))
      (.boolean (!(Trivia.result rawKind))) tested := evaluatesUnary called (by rfl)
  have testedStorage := storage.preserved callEffect
  have outputStill := callEffect.preserves_localPointsTo storage.wellFormed outputOwned (by simp [CellSet.empty])
  cases selected : Trivia.result rawKind with
  | true =>
      have guardFalse : Evaluates program before (.unary .logicalNot (.call triviaId [.local 6]))
          (.boolean false) tested := by simpa only [selected, Bool.not_true] using guardResult
      refine ⟨tested, executesIfFalse guardFalse (executesSkip program tested), ?_, ?_,
        callEffect.weaken CellSet.empty_subset⟩
      · simpa only [filteredRecords, selected, Bool.true_eq, if_true] using testedStorage.recordsContents
      · simpa only [filteredCount, selected, Bool.true_eq, if_true] using outputStill
  | false =>
      have guardTrue : Evaluates program before (.unary .logicalNot (.call triviaId [.local 6]))
          (.boolean true) tested := by simpa only [selected, Bool.not_false] using guardResult
      obtain ⟨after, kept, contents, owned, effect⟩ := executes_kept_body kind testedStorage
        rawKind start width inputRow output outputCell
        (callEffect.empty_preserves_local storage.wellFormed kindLocal)
        (callEffect.empty_preserves_local storage.wellFormed inputLocal)
        startSelected endSelected outputStill distinct sourceBound inputBound rowBound
      refine ⟨after, executesIfTrue guardTrue kept, ?_, ?_,
        (callEffect.weaken CellSet.empty_subset).trans effect⟩
      · simpa only [filteredRecords, selected, Bool.false_eq_true, if_false] using contents
      · simpa only [filteredCount, selected, Bool.false_eq_true, if_false] using owned

end Lanius.Extraction.CanonicalTokens.Compaction
