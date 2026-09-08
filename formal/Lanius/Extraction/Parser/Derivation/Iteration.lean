import Lanius.Extraction.Parser.Derivation.Child

namespace Lanius.Extraction.ParserDerivation

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Compiler.Parser Lanius.Extraction.ParserRecognize

/-- Execute the entire inspected loop body from a sound logical cursor and
    a concrete reader frame. Every accessor, guard, initializer, and mutation
    is derived; no execution of a source substatement is a premise. This is
    the standalone-coordinate theorem to transport through the checked link. -/
theorem ReaderRuntime.At.execute_iteration {reader : ReaderRuntime}
    (held : reader.At stateId (remaining + 1) before)
    (accessor : reader.stores.accessor = extractedParserStateValueFunction.id)
    (selector : reader.stores.selector = 36)
    (sound : WorkspaceBackpointersSound grammar tokens reader.workspace)
    (cursor : DerivationCursor reader.workspace root state fuel stateId (remaining + 1) suffix children)
    (productionLocal : before.local? productionId = some (.signed .i32 (Int.ofNat root.production)))
    (originLocal : before.local? originId = some (.signed .i32 (Int.ofNat root.origin)))
    (tokenCount : reader.tokenCount = tokens.length)
    (distinctBuffers : reader.outputCell ≠ reader.workspaceCell)
    (distinctCursors : reader.currentCell ≠ reader.remainingCell)
    (fits : reader.offset + 4 + count * 3 ≤ reader.outputValues.length)
    (capacityBound : reader.outputValues.length ≤ 2147483647)
    (remainingBound : remaining + 1 ≤ count)
    (freshSlot : ∀ localId ∈ [reader.stores.output, reader.stores.workspace, reader.stores.base,
      reader.stores.tag, reader.stores.payload, reader.stores.current, reader.tail.remaining,
      reader.tail.previous], reader.stores.slot ≠ localId)
    (previousFresh : reader.tail.previous ∉ reader.liveLocals)
    (tagFresh : reader.stores.tag ∉ reader.liveLocals)
    (payloadFresh : reader.stores.payload ∉ reader.liveLocals)
    (distinct : reader.tail.previous ≠ reader.stores.tag ∧
      reader.tail.previous ≠ reader.stores.payload ∧ reader.stores.tag ≠ reader.stores.payload) :
    ∃ after, Executes verifiedParserCore before
      (iterationBody reader.stores reader.tail productionId originId reader.offsetId reader.tokenCountId 28)
      .next after ∧ reader.ChildCells state remaining after ∧
      CellEffect (CellSet.union (CellSet.singleton reader.outputCell)
        (CellSet.union (CellSet.singleton reader.currentCell) (CellSet.singleton reader.remainingCell)))
        before after := by
  obtain ⟨checked, metadata, _, readEffect⟩ := metadata_guard_executes cursor held.artifact
    held.wellFormed held.workspaceLocal held.baseLocal
    (Assertion.localPointsTo_local _ _ _ _ held.currentOwned)
    (Assertion.localPointsTo_local _ _ _ _ held.remainingOwned) productionLocal originLocal
  obtain ⟨after, child, result, childEffect⟩ := (held.after_read readEffect).execute_child accessor selector
    sound cursor.found (by rw [cursor.dot]; omega) tokenCount distinctBuffers distinctCursors
    fits capacityBound remainingBound freshSlot previousFresh tagFresh payloadFresh distinct
  refine ⟨after, ?_, result, (readEffect.weaken CellSet.empty_subset).trans childEffect⟩
  rw [iterationBody_guardedStores]
  simp only [accessor]
  exact executesSequence (executesIfFalse metadata (executesSkip verifiedParserCore checked)) child

end Lanius.Extraction.ParserDerivation
