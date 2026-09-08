import Lanius.Extraction.Parser.Derivation.Output

namespace Lanius.Extraction.ParserDerivation

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Compiler.Parser Lanius.Extraction.ParserRecognize

/-- Execute the complete reader loop with exact output contents and seed
    metadata at exit. Entry/header setup and the final source guard remain
    outside this theorem. -/
theorem ReaderRuntime.At.execute_loop {reader : ReaderRuntime}
    (held : reader.At stateId remaining before)
    (accessor : reader.stores.accessor = extractedParserStateValueFunction.id)
    (selector : reader.stores.selector = 36)
    (sound : WorkspaceBackpointersSound grammar tokens reader.workspace)
    (cursor : DerivationCursor reader.workspace root state fuel stateId remaining suffix children)
    (productionLocal : before.local? productionId = some (.signed .i32 (Int.ofNat root.production)))
    (originLocal : before.local? originId = some (.signed .i32 (Int.ofNat root.origin)))
    (tokenCount : reader.tokenCount = tokens.length)
    (distinctBuffers : reader.outputCell ≠ reader.workspaceCell)
    (distinctCursors : reader.currentCell ≠ reader.remainingCell)
    (fits : reader.offset + 4 + count * 3 ≤ reader.outputValues.length)
    (capacityBound : reader.outputValues.length ≤ 2147483647)
    (remainingBound : remaining ≤ count)
    (freshSlot : ∀ localId ∈ [reader.stores.output, reader.stores.workspace, reader.stores.base,
      reader.stores.tag, reader.stores.payload, reader.stores.current, reader.tail.remaining,
      reader.tail.previous], reader.stores.slot ≠ localId)
    (previousFresh : reader.tail.previous ∉ reader.liveLocals)
    (tagFresh : reader.stores.tag ∉ reader.liveLocals)
    (payloadFresh : reader.stores.payload ∉ reader.liveLocals)
    (distinct : reader.tail.previous ≠ reader.stores.tag ∧
      reader.tail.previous ≠ reader.stores.payload ∧ reader.stores.tag ≠ reader.stores.payload)
    (stable : reader.StableLocals before)
    (metadataStable : ∀ localId ∈ [productionId, originId], ∀ cell,
      before.cellId? localId = some cell → cell ≠ reader.currentCell ∧ cell ≠ reader.remainingCell)
    (layout : reader.OutputLayout header trailing remaining suffix) :
    ∃ after finalId finalState,
      Executes verifiedParserCore before
        (readerLoop reader.stores reader.tail productionId originId reader.offsetId reader.tokenCountId 28)
        .next after ∧
      ({ reader with outputValues := header ++ children.flatMap derivationChildWords ++ trailing }).At
        finalId 0 after ∧
      reader.workspace.state? finalId = some finalState ∧
      finalState.dot = 0 ∧ finalState.production = root.production ∧ finalState.origin = root.origin ∧
      finalState.previous = none ∧ finalState.child = .none ∧
      after.local? productionId = some (.signed .i32 (Int.ofNat root.production)) ∧
      after.local? originId = some (.signed .i32 (Int.ofNat root.origin)) ∧
      CellEffect (CellSet.union (CellSet.singleton reader.outputCell)
        (CellSet.union (CellSet.singleton reader.currentCell) (CellSet.singleton reader.remainingCell)))
        before after := by
  induction fuel generalizing reader before stateId remaining state suffix with
  | zero =>
    have impossible := cursor.output
    simp [derivationChildrenAcc?] at impossible
  | succ fuel ih =>
    have localRead := Assertion.localPointsTo_local _ _ _ _ held.remainingOwned
    have read : Evaluates verifiedParserCore before (.local reader.tail.remaining)
        (.signed .i32 (Int.ofNat remaining)) before :=
      ⟨1, evalLocal_of_local 0 verifiedParserCore before _ _ localRead⟩
    cases remaining with
    | zero =>
      have guard : Evaluates verifiedParserCore before
          (.binary .notEqual (.local reader.tail.remaining) (.value (.signed .i32 0)))
          (.boolean false) before := by
        apply evaluatesEagerBinary (by decide) (by decide) read
          (show Evaluates verifiedParserCore before (.value (.signed .i32 0)) (.signed .i32 0) before from ⟨1, rfl⟩)
        rfl
      obtain ⟨suffixDone, seedPrevious, seedChild⟩ := cursor.finish sound
      have contents := layout.finish
      rw [suffixDone] at contents
      have finalReader : { reader with outputValues := header ++ children.flatMap derivationChildWords ++ trailing } =
          reader := by rw [← contents]
      refine ⟨before, stateId, state, executesWhileFalse guard, ?_, cursor.found,
        cursor.dot, cursor.production, cursor.origin, seedPrevious, seedChild,
        productionLocal, originLocal, CellEffect.refl held.wellFormed⟩
      simpa only [finalReader] using held
    | succ remaining =>
      have guard : Evaluates verifiedParserCore before
          (.binary .notEqual (.local reader.tail.remaining) (.value (.signed .i32 0)))
          (.boolean true) before := by
        apply evaluatesEagerBinary (by decide) (by decide) read
          (show Evaluates verifiedParserCore before (.value (.signed .i32 0)) (.signed .i32 0) before from ⟨1, rfl⟩)
        simp [evalBinaryValue, scalarEqual]
        omega
      obtain ⟨middle, iteration, result, effect⟩ := held.execute_iteration accessor selector sound cursor
        productionLocal originLocal tokenCount distinctBuffers distinctCursors fits capacityBound remainingBound
        freshSlot previousFresh tagFresh payloadFresh distinct
      obtain ⟨previous, previousState, _, nextCursor, nextHeld, nextStable⟩ :=
        held.advance_cursor stable cursor sound result effect
      have preserve {localId : VarId} {word : Int} (member : localId ∈ [productionId, originId])
          (found : before.local? localId = some (.signed .i32 word)) :
          middle.local? localId = some (.signed .i32 word) := by
        apply effect.preserves_local held.wellFormed found
        intro cell binding written
        have bufferDifferent := local_cell_ne_of_distinct_value found held.backing (by simp) binding
        have cursorDifferent := metadataStable localId member cell binding
        exact written.elim bufferDifferent (fun cursor => cursor.elim cursorDifferent.1 cursorDifferent.2)
      have nextMetadata : ∀ localId ∈ [productionId, originId], ∀ cell,
          middle.cellId? localId = some cell → cell ≠ reader.currentCell ∧ cell ≠ reader.remainingCell := by
        intro localId member cell binding
        apply metadataStable localId member cell
        simpa only [State.cellId?, effect.locals] using binding
      obtain ⟨after, finalId, finalState, loop, finalHeld, foundFinal, dotFinal, productionFinal,
          originFinal, previousFinal, childFinal, productionAfter, originAfter, restEffect⟩ :=
        ih nextHeld accessor selector sound nextCursor
          (preserve (by simp) productionLocal) (preserve (by simp) originLocal)
          tokenCount distinctBuffers distinctCursors
          (by simpa only [ReaderRuntime.writeChild, List.length_set] using fits)
          (by simpa only [ReaderRuntime.writeChild_length] using capacityBound)
          (by omega) freshSlot previousFresh tagFresh payloadFresh distinct nextStable nextMetadata
          (layout.advance state.child)
      exact ⟨after, finalId, finalState, executesWhileTrue guard iteration loop, finalHeld,
        foundFinal, dotFinal, productionFinal, originFinal, previousFinal, childFinal,
        productionAfter, originAfter, effect.trans restEffect⟩

end Lanius.Extraction.ParserDerivation
