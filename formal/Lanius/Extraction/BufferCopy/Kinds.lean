import Lanius.Extraction.BufferCopy.Entry
import Lanius.Extraction.BufferCopy.Tokens
import Lanius.Extraction.CanonicalTokens.Compaction.Specification
import Lanius.Extraction.CanonicalTokens.Compaction.Range.Specification
import Lanius.Separation.I32Prefix

namespace Lanius.Extraction.BufferCopy

open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Compiler Lanius.Compiler.Lexer
open Lanius.Extraction.CanonicalTokens CanonicalizeModel Compaction

theorem canonical_count_le (source : List Byte) (raw : List RawToken) :
    (canonicalizeTokens source raw).length ≤ raw.length := by
  rw [canonicalizeTokens, Range.retag_length]
  exact filtered_length source raw

theorem kind_prefix (tokens : List RawToken) (untouched : List Int)
    (capacity : tokens.length ≤ untouched.length)
    (contents : state.cellEntry? cell = some {
      id := cell, value := some (.array (signedI32Values
        (tokenKinds tokens ++ untouched.drop tokens.length))) }) :
    I32Prefix state cell untouched.length (tokenKinds tokens) := by
  refine ⟨untouched.drop tokens.length, ?_, contents⟩
  simp only [tokenKinds, List.length_map, List.length_drop]
  omega

/-- Extract parser kinds from the canonicalizer's actual buffer contract.
The copy-memory model, selection relation, fresh cursor, and loop invariant
are constructed here, rather than supplied as caller proof obligations. -/
theorem copy_kinds (program : Program) (before : State)
    (source : List Byte) (raw : List RawToken) (unused untouched : List Int)
    (sourceId destinationId cursorId countId : VarId) (sourceCell destinationCell : CellId)
    (wellFormed : StateWellFormed before)
    (distinct : sourceCell ≠ destinationCell)
    (cursorDistinct : ∀ id ∈ [sourceId, destinationId, countId], cursorId ≠ id)
    (sourceFits : 3 * raw.length + unused.length ≤ 2147483647)
    (destinationFits : untouched.length ≤ 2147483647)
    (capacity : (canonicalizeTokens source raw).length ≤ untouched.length)
    (sourceLocal : before.local? sourceId = some
      (.slice (.scalar (.signed .i32)) sourceCell [] 0 (3 * raw.length + unused.length)))
    (destinationLocal : before.local? destinationId = some
      (.slice (.scalar (.signed .i32)) destinationCell [] 0 untouched.length))
    (countLocal : before.local? countId = some (.signed .i32 (canonicalizeTokens source raw).length))
    (sourceContents : before.cellEntry? sourceCell = some {
      id := sourceCell, value := some (.array (signedI32Values
        (compactedBuffer raw unused (canonicalizeTokens source raw)))) })
    (destinationContents : before.cellEntry? destinationCell = some {
      id := destinationCell, value := some (.array (signedI32Values untouched)) }) :
    let locals : Locals := ⟨sourceId, destinationId, cursorId, countId, .triple, .plain⟩
    let tokens := canonicalizeTokens source raw
    ∃ after,
      (∀ rest completion final, Executes program after rest completion final →
        Executes program before
          (.letLocal cursorId (.scalar (.signed .i32)) (.value (.signed .i32 0))
            (.sequence locals.loop rest)) completion (restoreLocals before final)) ∧
      after.cellEntry? sourceCell = some {
        id := sourceCell, value := some (.array (signedI32Values (compactedBuffer raw unused tokens))) } ∧
      after.cellEntry? destinationCell = some {
        id := destinationCell, value := some (.array (signedI32Values
          (tokenKinds tokens ++ untouched.drop tokens.length))) } ∧
      after.local? destinationId = some
        (.slice (.scalar (.signed .i32)) destinationCell [] 0 untouched.length) ∧
      after.local? countId = some (.signed .i32 tokens.length) ∧
      StateWellFormed after ∧
      CellEffect (CellSet.union (CellSet.singleton destinationCell) (CellSet.singleton before.nextCell))
        (before.bindLocal cursorId (.signed .i32 0)) after := by
  dsimp only
  let tokens := canonicalizeTokens source raw
  let locals : Locals := ⟨sourceId, destinationId, cursorId, countId, .triple, .plain⟩
  have sourceLength := compactedBuffer_length raw tokens unused (canonical_count_le source raw)
  let memory : Memory locals := {
    sourceCell, destinationCell, cursorCell := before.nextCell,
    source := compactedBuffer raw unused tokens,
    untouched, values := tokenKinds tokens, count := tokens.length,
    countLength := by simp [locals, Scale.factor, tokenKinds],
    selected := kinds_selected raw tokens unused,
    capacity := by simpa [tokenKinds] using capacity,
    destinationFits,
    sourceFits := by simpa only [sourceLength] using sourceFits,
    source_destination := distinct,
    source_cursor := Nat.ne_of_lt (StateWellFormed.cell_lt_next_of_entry wellFormed sourceContents),
    destination_cursor := Nat.ne_of_lt (StateWellFormed.cell_lt_next_of_entry wellFormed destinationContents)
  }
  have entry : Entry memory before := {
    wellFormed,
    sourceLocal := by simpa only [memory, locals, sourceLength] using sourceLocal,
    destinationLocal, sourceContents, destinationContents,
    count := countLocal,
    cursorDistinct,
    cursorFresh := rfl
  }
  obtain ⟨after, loop, complete, effect⟩ := executes_loop program locals memory [] memory.values
    (before.bindLocal cursorId (.signed .i32 0)) rfl entry.initialize
  refine ⟨after, ?_, complete.sourceContents, ?_, complete.destinationLocal,
    complete.count, complete.wellFormed, effect⟩
  · intro rest completion final tailRun
    exact executesLetLocal
      (show Evaluates program before (.value (.signed .i32 0)) (.signed .i32 0) before from ⟨1, rfl⟩)
      (executesSequence loop tailRun)
  · simpa only [memory, buffer, tokenKinds, List.length_map] using complete.destinationContents

end Lanius.Extraction.BufferCopy
