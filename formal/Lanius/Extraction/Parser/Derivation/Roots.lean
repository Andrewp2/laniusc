import Lanius.Extraction.Parser.Derivation.Preparation
import Lanius.Extraction.Parser.Derivation.Record

namespace Lanius.Extraction.ParserDerivation

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Compiler.Parser Lanius.Extraction.ParserRecognize

def ReaderRuntime.rootBody (reader : ReaderRuntime) (stateIdLocal countId productionId originId : VarId) : Stmt :=
  let readField := fun selector => Expr.call extractedParserStateValueFunction.id
    [.local reader.stores.workspace, .local reader.stores.base, .local stateIdLocal, .constant selector]
  .letLocal productionId parserI32Type (readField 28)
    (.letLocal originId parserI32Type (readField 30)
      (readerHeader reader.stores productionId originId reader.offsetId countId stateIdLocal 28
        (reader.walkBody stateIdLocal countId productionId originId)))

/-- Fetch root production and origin from the workspace, then emit the
    complete record. The saved metadata is no longer an execution premise. -/
theorem ReaderRuntime.BeforeCursor.execute_roots {reader : ReaderRuntime}
    (entry : reader.BeforeCursor before)
    (accessor : reader.stores.accessor = extractedParserStateValueFunction.id)
    (selector : reader.stores.selector = 36)
    (sound : WorkspaceBackpointersSound grammar tokens reader.workspace)
    (found : reader.workspace.state? stateId = some root)
    (stateLocal : before.local? stateIdLocal = some (.signed .i32 (Int.ofNat stateId)))
    (countLocal : before.local? countId = some (.signed .i32 (Int.ofNat root.dot)))
    (productionFresh : productionId ∉ reader.readonlyLocals ++ [stateIdLocal, countId])
    (originFresh : originId ∉ reader.readonlyLocals ++ [stateIdLocal, countId, productionId])
    (tokenCount : reader.tokenCount = tokens.length)
    (distinctBuffers : reader.outputCell ≠ reader.workspaceCell)
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
    (contents : reader.outputValues = leading ++ [oldProduction, oldOrigin, oldPosition, oldCount] ++ pending ++ trailing)
    (offset : leading.length = reader.offset) (pendingLength : pending.length = root.dot * 3) :
    ∃ children after, children.length = root.dot ∧
      derivationChildren? reader.workspace (stateId + 1) stateId = some children ∧
      Executes verifiedParserCore before (reader.rootBody stateIdLocal countId productionId originId)
        (.returned (some (.signed .i32 (Int.ofNat root.dot)))) after ∧
      after.cellEntry? reader.outputCell = some {
        id := reader.outputCell, value := some (.array (signedI32Values
          (leading ++ derivationRecordWords root children ++ trailing))) } ∧
      RecognizerWorkspaceArtifact reader.layout reader.workspace reader.workspaceValues reader.workspaceCell after ∧
      CellEffect (CellSet.singleton reader.outputCell) before after := by
  let post := fun runtime : State => ∃ children, children.length = root.dot ∧
    derivationChildren? reader.workspace (stateId + 1) stateId = some children ∧
    runtime.cellEntry? reader.outputCell = some {
      id := reader.outputCell, value := some (.array (signedI32Values
        (leading ++ derivationRecordWords root children ++ trailing))) }
  have productionNames : productionId ∉ reader.readonlyLocals ∧ productionId ≠ stateIdLocal ∧ productionId ≠ countId := by
    simpa using productionFresh
  have originNames : originId ∉ reader.readonlyLocals ∧ originId ≠ stateIdLocal ∧
      originId ≠ countId ∧ originId ≠ productionId := by simpa using originFresh
  obtain ⟨after, execution, result, effect⟩ := entry.artifact.let_field (post := post)
    entry.wellFormed found (field := 0) (selectorId := 28) (localId := productionId) (by decide)
    entry.workspaceLocal entry.baseLocal stateLocal (by rfl) (by
      intro first firstEffect _ _
      have entry1 := (entry.after_read firstEffect).bind productionNames.1 (.signed .i32 (Int.ofNat root.production))
      have state1 := (bindLocal_preserves_other_local (value := .signed .i32 (Int.ofNat root.production))
        firstEffect.wellFormed productionNames.2.1).trans
        (firstEffect.empty_preserves_local entry.wellFormed stateLocal)
      have count1 := (bindLocal_preserves_other_local (value := .signed .i32 (Int.ofNat root.production))
        firstEffect.wellFormed productionNames.2.2).trans
        (firstEffect.empty_preserves_local entry.wellFormed countLocal)
      have production1 := bindLocal_finds_local first productionId (.signed .i32 (Int.ofNat root.production)) firstEffect.wellFormed
      apply entry1.artifact.let_field (post := post) entry1.wellFormed found
        (field := 2) (selectorId := 30) (localId := originId) (by decide)
        entry1.workspaceLocal entry1.baseLocal state1 (by rfl)
      intro second secondEffect _ _
      have entry2 := (entry1.after_read secondEffect).bind originNames.1 (.signed .i32 (Int.ofNat root.origin))
      have preserve {localId : VarId} {value : Value} (different : originId ≠ localId)
          (localValue : (first.bindLocal productionId (.signed .i32 (Int.ofNat root.production))).local? localId = some value) :
          (second.bindLocal originId (.signed .i32 (Int.ofNat root.origin))).local? localId = some value :=
        (bindLocal_preserves_other_local secondEffect.wellFormed different).trans
          (secondEffect.empty_preserves_local entry1.wellFormed localValue)
      obtain ⟨children, completed, length, computed, record, output, _, recordEffect⟩ :=
        entry2.execute_record accessor selector sound found (preserve originNames.2.1 state1)
          (preserve originNames.2.2.1 count1) (preserve originNames.2.2.2 production1)
          (bindLocal_finds_local second originId (.signed .i32 (Int.ofNat root.origin)) secondEffect.wellFormed)
          tokenCount distinctBuffers capacityBound different currentFresh remainingFresh metadataFresh
          freshSlot previousFresh tagFresh payloadFresh distinct contents offset pendingLength
      exact ⟨completed, record, ⟨children, length, computed, output⟩, recordEffect⟩)
  obtain ⟨children, length, computed, output⟩ := result
  refine ⟨children, after, length, computed, execution, output, ?_, effect⟩
  exact ⟨entry.artifact.workspaceLength, entry.artifact.workspaceEncoded,
    effect.preserves_entry entry.wellFormed entry.artifact.workspaceBacking (Ne.symm distinctBuffers)⟩

end Lanius.Extraction.ParserDerivation
