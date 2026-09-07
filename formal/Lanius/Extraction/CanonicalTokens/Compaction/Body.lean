import Lanius.Extraction.CanonicalTokens.Compaction.Composition

namespace Lanius.Extraction.CanonicalTokens.Compaction

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Compiler Lanius.Compiler.Lexer CanonicalizeModel

/-- The complete checked Lanius function body, not just its two loops.
Only the caller's record array may change; both cursors are fresh locals. -/
theorem CheckedSource.executes_body
    (checked : CheckedSource program functionId triviaId kindId keywordId matcher)
    (source : List Byte) (raw : List RawToken) (unused : List Int)
    (storage : Storage before sourceCell recordsCell (sourceIntegers source) (encodeTokens raw ++ unused))
    (sourceRecords : sourceCell ≠ recordsCell)
    (countLocal : before.local? 2 = some (.signed .i32 raw.length))
    (spans : ∀ token ∈ raw, token.start ≤ token.finish ∧ token.finish ≤ source.length) :
    ∃ after, Executes program before (body triviaId kindId checked.tokens)
        (.returned (some (.signed .i32 (canonicalizeTokens source raw).length))) after ∧
      after.cellEntry? recordsCell = some {
        id := recordsCell, value := some (.array (signedI32Values (compactedBuffer raw unused (canonicalizeTokens source raw)))) } ∧
      CellEffect (CellSet.singleton recordsCell) before after := by
  have sourceOld := StateWellFormed.cell_lt_next_of_entry storage.wellFormed storage.sourceContents
  have recordsOld := StateWellFormed.cell_lt_next_of_entry storage.wellFormed storage.recordsContents
  let request : Request := {
    source
    raw
    unused
    sourceCell
    recordsCell
    inputCell := before.nextCell
    outputCell := before.nextCell + 1
    recordsOutput := Nat.ne_of_lt (Nat.lt_succ_of_lt recordsOld)
    recordsInput := Nat.ne_of_lt recordsOld
    inputOutput := Nat.ne_of_lt (Nat.lt_succ_self _)
    sourceDistinct := ⟨sourceRecords, Nat.ne_of_lt (Nat.lt_succ_of_lt sourceOld), Nat.ne_of_lt sourceOld⟩
    sourceFits := by simpa [sourceIntegers] using storage.sourceFits
    recordsFit := by simpa only [List.length_append, encoded_length] using storage.recordsFit
    spans
  }
  let withInput := before.bindLocal 3 (.signed .i32 0)
  let ready := withInput.bindLocal 4 (.signed .i32 0)
  have inputStorage : Storage withInput sourceCell recordsCell (sourceIntegers source) (encodeTokens raw ++ unused) :=
    storage.bind 3 _ (by decide) (by decide)
  have readyStorage : Storage ready sourceCell recordsCell (sourceIntegers source) (encodeTokens raw ++ unused) :=
    inputStorage.bind 4 _ (by decide) (by decide)
  have inputAtInput := bindLocal_owns_fresh before 3 (.signed .i32 0) storage.wellFormed
  have inputReady := bindLocal_preserves_localPointsTo_of_ne withInput 4 3 (.signed .i32 0)
    before.nextCell _ inputStorage.wellFormed (by decide) inputAtInput
  have outputReady := bindLocal_owns_fresh withInput 4 (.signed .i32 0) inputStorage.wellFormed
  have countAtInput : withInput.local? 2 = some (.signed .i32 raw.length) :=
    (bindLocal_preserves_other_local storage.wellFormed (show (3 : VarId) ≠ 2 by decide)).trans countLocal
  have countReady : ready.local? 2 = some (.signed .i32 raw.length) :=
    (bindLocal_preserves_other_local inputStorage.wellFormed (show (4 : VarId) ≠ 2 by decide)).trans countAtInput
  have invariant : LoopState request [] ready := by
    refine ⟨readyStorage, inputReady, outputReady, countReady, ?_⟩
    intro id selected cell found
    have notInput : (3 : VarId) ≠ id := by rcases selected with rfl | rfl | rfl <;> decide
    have notOutput : (4 : VarId) ≠ id := by rcases selected with rfl | rfl | rfl <;> decide
    have oldBinding : before.cellId? id = some cell := by
      simpa [ready, withInput, State.bindLocal, State.bindCell, State.cellId?, notInput, notOutput] using found
    have old := StateWellFormed.cell_lt_next_of_local_binding id cell storage.wellFormed oldBinding
    have notRecords : cell ≠ recordsCell := by
      rcases selected with rfl | rfl | rfl
      · exact local_cell_ne_of_distinct_value storage.sourceLocal storage.recordsContents (by intro h; cases h) oldBinding
      · exact local_cell_ne_of_distinct_value storage.recordsLocal storage.recordsContents (by intro h; cases h) oldBinding
      · exact local_cell_ne_of_distinct_value countLocal storage.recordsContents (by intro h; cases h) oldBinding
    intro written
    rcases written with (records | output) | input
    · exact notRecords records
    · exact (Nat.ne_of_lt (Nat.lt_succ_of_lt old)) output
    · exact (Nat.ne_of_lt old) input
  let table : Range.Table program checked.tokens :=
    ⟨checked.rangeFound, checked.assignFound, checked.inclusiveFound⟩
  obtain ⟨completed, run, contents, effect⟩ := executes_passes checked.trivia checked.kind table request invariant
  have closeOutput := CellEffect.closeLocal withInput 4 (.signed .i32 0) inputStorage.wellFormed effect
  have closeInput := CellEffect.closeLocal before 3 (.signed .i32 0) storage.wellFormed closeOutput
  have visible : CellEffect (CellSet.singleton recordsCell) before (restoreLocals before (restoreLocals withInput completed)) :=
    closeInput.narrow (by
      intro cell old written
      rcases written with (records | output) | input
      · exact records
      · exact False.elim ((Nat.ne_of_lt (Nat.lt_succ_of_lt old)) output)
      · exact False.elim ((Nat.ne_of_lt old) input))
  exact ⟨_, executesLetLocal (show Evaluates program before (literal 0) (.signed .i32 0) before from ⟨1, rfl⟩)
    (executesLetLocal (show Evaluates program withInput (literal 0) (.signed .i32 0) withInput from ⟨1, rfl⟩) run), contents, visible⟩

end Lanius.Extraction.CanonicalTokens.Compaction
