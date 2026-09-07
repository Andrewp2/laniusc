import Lanius.Extraction.CanonicalTokens.Compaction.Step
import Lanius.Extraction.CanonicalTokens.Compaction.Specification

namespace Lanius.Extraction.CanonicalTokens.Compaction

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Compiler Lanius.Compiler.Lexer CanonicalizeModel

structure Request where
  source : List Byte
  raw : List RawToken
  unused : List Int
  sourceCell : CellId
  recordsCell : CellId
  inputCell : CellId
  outputCell : CellId
  recordsOutput : recordsCell ≠ outputCell
  recordsInput : recordsCell ≠ inputCell
  inputOutput : inputCell ≠ outputCell
  sourceDistinct : sourceCell ≠ recordsCell ∧ sourceCell ≠ outputCell ∧ sourceCell ≠ inputCell
  sourceFits : source.length ≤ 2147483647
  recordsFit : 3 * raw.length + unused.length ≤ 2147483647
  spans : ∀ token ∈ raw, token.start ≤ token.finish ∧ token.finish ≤ source.length

def Request.writes (request : Request) : CellSet :=
  stepWrites request.recordsCell request.outputCell request.inputCell

def Request.output (request : Request) (processed : List RawToken) : List RawToken :=
  filterRetagTokens request.source processed

def Request.buffer (request : Request) (processed : List RawToken) : List Int :=
  compactedBuffer request.raw request.unused (request.output processed)

theorem Request.output_step (request : Request) (processed : List RawToken) (token : RawToken) :
    request.output (processed ++ [token]) =
      request.output processed ++ (canonicalizeToken request.source token).toList := by
  simp only [Request.output, filtered_append, filterRetagTokens]
  cases canonicalizeToken request.source token <;> rfl

structure LoopState (request : Request) (processed : List RawToken) (state : State) : Prop where
  storage : Storage state request.sourceCell request.recordsCell (sourceIntegers request.source) (request.buffer processed)
  input : (Assertion.localPointsTo 3 request.inputCell (some (.signed .i32 processed.length))).holds state
  output : (Assertion.localPointsTo 4 request.outputCell (some (.signed .i32 (request.output processed).length))).holds state
  count : state.local? 2 = some (.signed .i32 request.raw.length)
  stable : ∀ id, id = 0 ∨ id = 1 ∨ id = 2 → ∀ cell, state.cellId? id = some cell → ¬ request.writes cell

theorem Request.buffer_length (request : Request) (processed : List RawToken)
    (prefixBound : processed.length ≤ request.raw.length) :
    (request.buffer processed).length = 3 * request.raw.length + request.unused.length := by
  apply compactedBuffer_length
  exact Nat.le_trans (filtered_length request.source processed) prefixBound

/-- Preserve the loop's read-only parameters while replacing the buffer and
advancing the two owned cursors. Temporary-cell allocation is hidden. -/
theorem LoopState.advance (invariant : LoopState request processed before)
    (next : List RawToken) (oldBound : processed.length ≤ request.raw.length) (nextBound : next.length ≤ request.raw.length)
    (effect : CellEffect request.writes before after)
    (contents : after.cellEntry? request.recordsCell = some {
      id := request.recordsCell, value := some (.array (signedI32Values (request.buffer next))) })
    (input : (Assertion.localPointsTo 3 request.inputCell (some (.signed .i32 next.length))).holds after)
    (output : (Assertion.localPointsTo 4 request.outputCell (some (.signed .i32 (request.output next).length))).holds after) :
    LoopState request next after := by
  have sourceLocal := effect.preserves_local invariant.storage.wellFormed invariant.storage.sourceLocal
    (invariant.stable 0 (by simp))
  have recordsLocal := effect.preserves_local invariant.storage.wellFormed invariant.storage.recordsLocal
    (invariant.stable 1 (by simp))
  have countLocal := effect.preserves_local invariant.storage.wellFormed invariant.count
    (invariant.stable 2 (by simp))
  have sourceContents := effect.preserves_entry invariant.storage.wellFormed invariant.storage.sourceContents
    (by simpa [Request.writes, stepWrites, CellSet.union, CellSet.singleton, and_assoc] using request.sourceDistinct)
  refine ⟨⟨effect.wellFormed, sourceLocal, ?_, sourceContents, contents,
    invariant.storage.sourceFits, ?_⟩, input, output, countLocal, ?_⟩
  · simpa only [request.buffer_length processed oldBound, request.buffer_length next nextBound] using recordsLocal
  · rw [request.buffer_length next nextBound]
    exact request.recordsFit
  · intro id selected cell found
    apply invariant.stable id selected cell
    simpa only [State.cellId?, effect.locals] using found

end Lanius.Extraction.CanonicalTokens.Compaction
