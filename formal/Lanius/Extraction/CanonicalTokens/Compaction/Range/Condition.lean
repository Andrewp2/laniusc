import Lanius.Extraction.CanonicalTokens.Compaction.Storage

namespace Lanius.Extraction.CanonicalTokens.Compaction.Range

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

structure Table (program : Program) (tokens : RangeTokens) : Prop where
  rangeFound : Trivia.ConstantAt program tokens.range 182
  assignFound : Trivia.ConstantAt program tokens.assign 8
  inclusiveFound : Trivia.ConstantAt program tokens.inclusive 189

def isPair (currentKind nextKind nextStart currentEnd : Int) : Bool :=
  (currentKind == 182 && nextKind == 8) && nextStart == currentEnd

theorem constantResult (program : Program) (before : State) (id : ConstantId) (value : Int)
    (found : Trivia.ConstantAt program id value) :
    Evaluates program before (.constant id) (.signed .i32 value) before := by
  unfold Trivia.ConstantAt at found
  refine ⟨1, ?_⟩
  rw [evalExpr.eq_def]
  simp only [found]

/-- Adjacent rows form `..=` exactly when both tags and the shared byte
boundary match. The second row remains an assignment token. -/
theorem evaluates_condition (table : Table program tokens)
    (storage : Storage before sourceCell recordsCell source records)
    (currentRow nextRow : Nat) (currentKind nextKind nextStart currentEnd : Int)
    (currentLocal : before.local? 11 = some (.signed .i32 currentRow))
    (nextLocal : before.local? 12 = some (.signed .i32 nextRow))
    (currentBound : currentRow + 2 < records.length) (nextBound : nextRow + 1 < records.length)
    (currentSelected : records[currentRow]? = some currentKind)
    (nextSelected : records[nextRow]? = some nextKind)
    (nextStartSelected : records[nextRow + 1]? = some nextStart)
    (currentEndSelected : records[currentRow + 2]? = some currentEnd) :
    Evaluates program before (rangeCondition tokens) (.boolean (isPair currentKind nextKind nextStart currentEnd)) before := by
  have currentIndex : Evaluates program before (.local 11) (.signed .i32 currentRow) before :=
    ⟨1, evalLocal_of_local 0 program before 11 _ currentLocal⟩
  have nextIndex : Evaluates program before (.local 12) (.signed .i32 nextRow) before :=
    ⟨1, evalLocal_of_local 0 program before 12 _ nextLocal⟩
  have currentRead := storage.readIndex (.local 11) currentRow currentKind currentIndex (by omega) currentSelected
  have nextRead := storage.readIndex (.local 12) nextRow nextKind nextIndex (by omega) nextSelected
  have nextStartRead := storage.readLocal (program := program) 12 nextRow 1 nextStart nextLocal nextBound nextStartSelected
  have currentEndRead := storage.readLocal (program := program) 11 currentRow 2 currentEnd currentLocal currentBound currentEndSelected
  have currentEquals : Evaluates program before (.binary .equal (read (.local 11)) (.constant tokens.range))
      (.boolean (currentKind == 182)) before := evaluatesEagerBinary (by decide) (by decide) currentRead
    (constantResult program before tokens.range 182 table.rangeFound) (by rfl)
  have nextEquals : Evaluates program before (.binary .equal (read (.local 12)) (.constant tokens.assign))
      (.boolean (nextKind == 8)) before := evaluatesEagerBinary (by decide) (by decide) nextRead
    (constantResult program before tokens.assign 8 table.assignFound) (by rfl)
  have contiguous : Evaluates program before (.binary .equal
      (read (add (.local 12) (literal 1))) (read (add (.local 11) (literal 2))))
      (.boolean (nextStart == currentEnd)) before := evaluatesEagerBinary (by decide) (by decide)
    nextStartRead currentEndRead (by rfl)
  exact evaluatesPureLogicalAnd (evaluatesPureLogicalAnd currentEquals nextEquals) contiguous

end Lanius.Extraction.CanonicalTokens.Compaction.Range
