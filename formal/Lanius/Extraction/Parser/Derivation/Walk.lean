import Lanius.Extraction.Parser.Derivation.Allocate
import Lanius.Extraction.Parser.Derivation.Loop
import Lanius.Extraction.Parser.Derivation.Exit

namespace Lanius.Extraction.ParserDerivation

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Compiler.Parser Lanius.Extraction.ParserRecognize

def ReaderRuntime.walkBody (reader : ReaderRuntime) (stateIdLocal countId productionId originId : VarId) : Stmt :=
  readerWalk reader.stores reader.tail productionId originId reader.offsetId reader.tokenCountId countId stateIdLocal 28

/-- Execute the entire post-header reader, from cursor allocation through
    return. No execution or continuation premise remains. Only the output
    buffer is caller-visible mutable storage. -/
theorem ReaderRuntime.BeforeCursor.execute_walk {reader : ReaderRuntime}
    (entry : reader.BeforeCursor before)
    (accessor : reader.stores.accessor = extractedParserStateValueFunction.id)
    (selector : reader.stores.selector = 36)
    (sound : WorkspaceBackpointersSound grammar tokens reader.workspace)
    (found : reader.workspace.state? stateId = some root)
    (stateLocal : before.local? stateIdLocal = some (.signed .i32 (Int.ofNat stateId)))
    (countLocal : before.local? countId = some (.signed .i32 (Int.ofNat root.dot)))
    (productionLocal : before.local? productionId = some (.signed .i32 (Int.ofNat root.production)))
    (originLocal : before.local? originId = some (.signed .i32 (Int.ofNat root.origin)))
    (tokenCount : reader.tokenCount = tokens.length)
    (distinctBuffers : reader.outputCell ≠ reader.workspaceCell)
    (fits : reader.offset + 4 + root.dot * 3 ≤ reader.outputValues.length)
    (capacityBound : reader.outputValues.length ≤ 2147483647)
    (different : reader.stores.current ≠ reader.tail.remaining)
    (currentFresh : reader.stores.current ∉ reader.readonlyLocals)
    (remainingFresh : reader.tail.remaining ∉ reader.readonlyLocals)
    (metadataFresh : ∀ localId ∈ [productionId, originId, countId],
      reader.stores.current ≠ localId ∧ reader.tail.remaining ≠ localId)
    (freshSlot : ∀ localId ∈ [reader.stores.output, reader.stores.workspace, reader.stores.base,
      reader.stores.tag, reader.stores.payload, reader.stores.current, reader.tail.remaining,
      reader.tail.previous], reader.stores.slot ≠ localId)
    (previousFresh : reader.tail.previous ∉ reader.liveLocals)
    (tagFresh : reader.stores.tag ∉ reader.liveLocals)
    (payloadFresh : reader.stores.payload ∉ reader.liveLocals)
    (distinct : reader.tail.previous ≠ reader.stores.tag ∧
      reader.tail.previous ≠ reader.stores.payload ∧ reader.stores.tag ≠ reader.stores.payload)
    (layout : reader.OutputLayout header trailing root.dot []) :
    ∃ children after, children.length = root.dot ∧
      derivationChildren? reader.workspace (stateId + 1) stateId = some children ∧
      Executes verifiedParserCore before (reader.walkBody stateIdLocal countId productionId originId)
        (.returned (some (.signed .i32 (Int.ofNat root.dot)))) after ∧
      after.cellEntry? reader.outputCell = some {
        id := reader.outputCell, value := some (.array (signedI32Values
          (header ++ children.flatMap derivationChildWords ++ trailing))) } ∧
      RecognizerWorkspaceArtifact reader.layout reader.workspace reader.workspaceValues reader.workspaceCell after ∧
      CellEffect (CellSet.singleton reader.outputCell) before after := by
  obtain ⟨children, length, initial⟩ := sound.reader_initial found (Nat.lt_succ_self stateId)
  have computed : derivationChildren? reader.workspace (stateId + 1) stateId = some children := by
    have output := initial.output
    simpa [derivationChildrenAcc_eq] using output
  let allocated := reader.allocatedCursors before
  let entered := before.bindLocals (reader.cursorBindings stateId root.dot)
  have preserved {localId : VarId} {value : Value} (member : localId ∈ [productionId, originId, countId])
      (localValue : before.local? localId = some value) : entered.local? localId = some value := by
    apply bindLocals_preserves_local before _ localId value entry.wellFormed localValue
    intro binding present
    simp only [ReaderRuntime.cursorBindings, List.mem_cons, List.not_mem_nil, or_false] at present
    rcases present with rfl | rfl
    · exact (metadataFresh localId member).1
    · exact (metadataFresh localId member).2
  have protectedLocal {localId : VarId} {cell : CellId} (member : localId ∈ [productionId, originId, countId])
      (binding : entered.cellId? localId = some cell) :
      cell ≠ allocated.currentCell ∧ cell ≠ allocated.remainingCell := by
    have old := reader.cursor_binding_old entry.wellFormed
      (metadataFresh localId member).1 (metadataFresh localId member).2 binding
    exact ⟨Nat.ne_of_lt old, Nat.ne_of_lt (Nat.lt_succ_of_lt old)⟩
  obtain ⟨after, execution, output, effect⟩ := entry.with_cursors
    (post := fun cells => ({ before with cells := cells } : State).cellEntry? reader.outputCell = some {
      id := reader.outputCell, value := some (.array (signedI32Values
        (header ++ children.flatMap derivationChildWords ++ trailing))) })
    different currentFresh remainingFresh stateLocal countLocal (metadataFresh countId (by simp)).1 (by
      dsimp only
      intro held stable distinctCells
      obtain ⟨middle, finalId, finalState, loop, finalHeld, finalFound, finalDot, finalProduction,
          finalOrigin, seedPrevious, seedChild, productionAfter, originAfter, loopEffect⟩ :=
        held.execute_loop accessor selector sound initial
          (preserved (by simp) productionLocal) (preserved (by simp) originLocal)
          tokenCount distinctBuffers distinctCells fits capacityBound (Nat.le_refl _)
          freshSlot previousFresh tagFresh payloadFresh distinct stable (by
            intro localId member cell binding
            apply protectedLocal (localId := localId) _ binding
            simp only [List.mem_cons, List.not_mem_nil, or_false] at member ⊢
            exact member.elim Or.inl (fun h => Or.inr (Or.inl h))) layout
      have savedCount : middle.local? countId = some (.signed .i32 (Int.ofNat root.dot)) := by
        have countEntered := preserved (by simp) countLocal
        apply loopEffect.preserves_local held.wellFormed countEntered
        intro cell binding written
        have bufferDifferent := local_cell_ne_of_distinct_value countEntered held.backing (by simp) binding
        have cursorDifferent := protectedLocal (localId := countId) (by simp) binding
        exact written.elim bufferDifferent (fun cursor => cursor.elim cursorDifferent.1 cursorDifferent.2)
      obtain ⟨completed, returned, completedHeld, exitEffect⟩ := finalHeld.execute_exit accessor finalFound
        finalDot finalProduction finalOrigin seedPrevious seedChild productionAfter originAfter savedCount
      exact ⟨completed, executesSequence loop returned, completedHeld.backing,
        loopEffect.trans (exitEffect.weaken CellSet.empty_subset)⟩)
  refine ⟨children, after, length, computed, execution, output, ?_, effect⟩
  exact ⟨entry.artifact.workspaceLength, entry.artifact.workspaceEncoded,
    effect.preserves_entry entry.wellFormed entry.artifact.workspaceBacking (Ne.symm distinctBuffers)⟩

end Lanius.Extraction.ParserDerivation
