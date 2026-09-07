import Lanius.Extraction.CanonicalTokens.Compaction.Range.Loop

namespace Lanius.Extraction.CanonicalTokens.Compaction.Range

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Compiler Lanius.Compiler.Lexer CanonicalizeModel

/-- Initialize the range cursor, execute the proved pass, return the retained
token count, and close the cursor's lexical scope. Only the records are written. -/
theorem executes_finish (table : Table program rangeTokens)
    (storage : Storage before sourceCell recordsCell source (buffer [] tokens unused))
    (sourceRecords : sourceCell ≠ recordsCell)
    (countLocal : before.local? 4 = some (.signed .i32 tokens.length)) :
    ∃ after, Executes program before (finish rangeTokens) (.returned (some (.signed .i32 tokens.length))) after ∧
      after.cellEntry? recordsCell = some {
        id := recordsCell, value := some (.array (signedI32Values (buffer [] (retagInclusiveRanges tokens) unused))) } ∧
      CellEffect (CellSet.singleton recordsCell) before after := by
  have sourceOld := StateWellFormed.cell_lt_next_of_entry storage.wellFormed storage.sourceContents
  have recordsOld := StateWellFormed.cell_lt_next_of_entry storage.wellFormed storage.recordsContents
  let request : Request := {
    source
    unused
    count := tokens.length
    sourceCell
    recordsCell
    cursorCell := before.nextCell
    distinct := Nat.ne_of_lt recordsOld
    sourceDistinct := ⟨sourceRecords, Nat.ne_of_lt sourceOld⟩
    sourceFits := storage.sourceFits
    recordsFit := by simpa only [buffer_length, List.length_nil, Nat.zero_add] using storage.recordsFit
  }
  let ready := before.bindLocal 10 (.signed .i32 0)
  have readyStorage : Storage ready sourceCell recordsCell source (buffer [] tokens unused) :=
    storage.bind 10 _ (by decide) (by decide)
  have cursorReady := bindLocal_owns_fresh before 10 (.signed .i32 0) storage.wellFormed
  have countReady : ready.local? 4 = some (.signed .i32 tokens.length) :=
    (bindLocal_preserves_other_local storage.wellFormed (show (10 : VarId) ≠ 4 by decide)).trans countLocal
  have invariant : LoopState request [] tokens ready := by
    refine ⟨readyStorage, cursorReady, countReady, by simp [request], ?_⟩
    intro id selected cell found
    have different : (10 : VarId) ≠ id := by rcases selected with rfl | rfl | rfl <;> decide
    have oldBinding : before.cellId? id = some cell := by
      simpa [ready, State.bindLocal, State.bindCell, State.cellId?, different] using found
    have old := StateWellFormed.cell_lt_next_of_local_binding id cell storage.wellFormed oldBinding
    have notRecords : cell ≠ recordsCell := by
      rcases selected with rfl | rfl | rfl
      · exact local_cell_ne_of_distinct_value storage.sourceLocal storage.recordsContents (by intro h; cases h) oldBinding
      · exact local_cell_ne_of_distinct_value storage.recordsLocal storage.recordsContents (by intro h; cases h) oldBinding
      · exact local_cell_ne_of_distinct_value countLocal storage.recordsContents (by intro h; cases h) oldBinding
    exact fun written => written.elim notRecords (Nat.ne_of_lt old)
  obtain ⟨completed, loop, finalStorage, finalCount, loopEffect⟩ := executes_loop table request [] tokens ready invariant
  have result : Evaluates program completed (.local 4) (.signed .i32 tokens.length) completed :=
    ⟨1, evalLocal_of_local 0 program completed 4 _ finalCount⟩
  have closed := CellEffect.closeLocal before 10 (.signed .i32 0) storage.wellFormed loopEffect
  have visible : CellEffect (CellSet.singleton recordsCell) before (restoreLocals before completed) :=
    closed.narrow (by
      intro cell old written
      rcases written with records | cursor
      · exact records
      · exact False.elim ((Nat.ne_of_lt old) cursor))
  exact ⟨restoreLocals before completed,
    executesLetLocal (show Evaluates program before (literal 0) (.signed .i32 0) before from ⟨1, rfl⟩)
      (executesSequence loop (executesSequenceReturned (executesReturnValue result))),
    finalStorage.recordsContents, visible⟩

end Lanius.Extraction.CanonicalTokens.Compaction.Range
