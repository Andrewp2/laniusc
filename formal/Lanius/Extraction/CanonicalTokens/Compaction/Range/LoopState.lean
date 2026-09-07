import Lanius.Extraction.CanonicalTokens.Compaction.Range.Step
import Lanius.Extraction.CanonicalTokens.Compaction.Range.Specification

namespace Lanius.Extraction.CanonicalTokens.Compaction.Range

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Compiler Lanius.Compiler.Lexer CanonicalizeModel

structure Request where
  source : List Int
  unused : List Int
  count : Nat
  sourceCell : CellId
  recordsCell : CellId
  cursorCell : CellId
  distinct : recordsCell ≠ cursorCell
  sourceDistinct : sourceCell ≠ recordsCell ∧ sourceCell ≠ cursorCell
  sourceFits : source.length ≤ 2147483647
  recordsFit : 3 * count + unused.length ≤ 2147483647

def Request.writes (request : Request) : CellSet :=
  CellSet.union (CellSet.singleton request.recordsCell) (CellSet.singleton request.cursorCell)

structure LoopState (request : Request) (completed remaining : List RawToken) (state : State) : Prop where
  storage : Storage state request.sourceCell request.recordsCell request.source (buffer completed remaining request.unused)
  cursor : (Assertion.localPointsTo 10 request.cursorCell (some (.signed .i32 completed.length))).holds state
  count : state.local? 4 = some (.signed .i32 request.count)
  length : completed.length + remaining.length = request.count
  stable : ∀ id, id = 0 ∨ id = 1 ∨ id = 4 → ∀ cell, state.cellId? id = some cell → ¬ request.writes cell

theorem LoopState.advance (invariant : LoopState request completed remaining before)
    (nextCompleted nextRemaining : List RawToken)
    (nextLength : nextCompleted.length + nextRemaining.length = request.count)
    (effect : CellEffect request.writes before after)
    (contents : after.cellEntry? request.recordsCell = some {
      id := request.recordsCell
      value := some (.array (signedI32Values (buffer nextCompleted nextRemaining request.unused))) })
    (cursor : (Assertion.localPointsTo 10 request.cursorCell (some (.signed .i32 nextCompleted.length))).holds after) :
    LoopState request nextCompleted nextRemaining after := by
  have sourceLocal := effect.preserves_local invariant.storage.wellFormed invariant.storage.sourceLocal (invariant.stable 0 (by simp))
  have recordsLocal := effect.preserves_local invariant.storage.wellFormed invariant.storage.recordsLocal (invariant.stable 1 (by simp))
  have countLocal := effect.preserves_local invariant.storage.wellFormed invariant.count (invariant.stable 4 (by simp))
  have sourceContents := effect.preserves_entry invariant.storage.wellFormed invariant.storage.sourceContents
    (by simpa [Request.writes, CellSet.union, CellSet.singleton] using request.sourceDistinct)
  refine ⟨⟨effect.wellFormed, sourceLocal, ?_, sourceContents, contents, request.sourceFits, ?_⟩,
    cursor, countLocal, nextLength, ?_⟩
  · simpa only [buffer_length, invariant.length, nextLength] using recordsLocal
  · rw [buffer_length, nextLength]
    exact request.recordsFit
  · intro id selected cell found
    apply invariant.stable id selected cell
    simpa only [State.cellId?, effect.locals] using found

end Lanius.Extraction.CanonicalTokens.Compaction.Range
