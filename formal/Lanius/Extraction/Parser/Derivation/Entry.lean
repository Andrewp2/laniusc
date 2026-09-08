import Lanius.Extraction.Parser.Derivation.Setup

namespace Lanius.Extraction.ParserDerivation

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Compiler.Parser Lanius.Extraction.ParserRecognize

def ReaderRuntime.workspaceBody (reader : ReaderRuntime)
    (workspaceLengthId stateIdLocal stateCountId capacityId countId productionId originId : VarId) : Stmt :=
  .sequence (.ifThenElse (workspaceCondition reader.stores.base workspaceLengthId stateCountId 27)
    (.sequence (.returnValue (some (.unary .negate (.value (.signed .i32 1))))) .skip) .skip)
    (reader.countBody stateIdLocal stateCountId capacityId countId productionId originId)

def ReaderRuntime.entryBody (reader : ReaderRuntime)
    (workspaceLengthId stateIdLocal stateCountId capacityId countId productionId originId : VarId) : Stmt :=
  .sequence (.ifThenElse (inputCondition reader.tokenCountId workspaceLengthId stateCountId stateIdLocal)
    (.sequence (.returnValue (some (.unary .negate (.value (.signed .i32 1))))) .skip) .skip)
    (.letLocal reader.stores.base parserI32Type reader.baseExpression
      (reader.workspaceBody workspaceLengthId stateIdLocal stateCountId capacityId countId productionId originId))

theorem ReaderRuntime.entryBody_source (reader : ReaderRuntime)
    (accessor : reader.stores.accessor = extractedParserStateValueFunction.id) :
    reader.entryBody workspaceLengthId stateIdLocal stateCountId capacityId countId productionId originId =
      readerEntry reader.stores reader.tail productionId originId reader.offsetId reader.tokenCountId
        countId stateIdLocal stateCountId capacityId workspaceLengthId 28 := by
  simp only [ReaderRuntime.entryBody, ReaderRuntime.workspaceBody, readerEntry,
    ReaderRuntime.baseExpression, reader.countBody_source accessor, parserI32Type]

/-- Run the shared input/workspace checks and base allocation, then the actual
    count component. Success and capacity failure share this entry proof. -/
theorem ReaderRuntime.Entry.with_checked_count {reader : ReaderRuntime} {post : List Cell → Prop}
    (entry : reader.Entry before)
    (layoutTokens : reader.layout.tokenCount = reader.tokenCount)
    (workspaceLengthLocal : before.local? workspaceLengthId = some (.signed .i32 (Int.ofNat reader.workspaceValues.length)))
    (stateLocal : before.local? stateIdLocal = some (.signed .i32 (Int.ofNat stateId)))
    (stateCountLocal : before.local? stateCountId = some (.signed .i32 (Int.ofNat stateCount)))
    (stateBound : stateId < stateCount) (statesFit : stateCount ≤ reader.layout.capacity)
    (capacityLocal : before.local? capacityId = some (.signed .i32 (Int.ofNat reader.outputValues.length)))
    (baseFresh : reader.stores.base ∉ [reader.stores.output, reader.stores.workspace, reader.offsetId,
      reader.tokenCountId, workspaceLengthId, stateIdLocal, stateCountId, capacityId])
    (continuation : ∀ initialized, reader.BeforeCursor initialized →
      initialized.local? stateIdLocal = some (.signed .i32 (Int.ofNat stateId)) →
      initialized.local? stateCountId = some (.signed .i32 (Int.ofNat stateCount)) →
      initialized.local? capacityId = some (.signed .i32 (Int.ofNat reader.outputValues.length)) →
      ∃ completed, Executes verifiedParserCore initialized
        (reader.countBody stateIdLocal stateCountId capacityId countId productionId originId) completion completed ∧
        post completed.cells ∧ CellEffect writes initialized completed) :
    ∃ after, Executes verifiedParserCore before
      (reader.entryBody workspaceLengthId stateIdLocal stateCountId capacityId countId productionId originId)
      completion after ∧ post after.cells ∧ CellEffect writes before after := by
  have tokenBound : reader.tokenCount ≤ maxTokenCount := layoutTokens ▸ reader.layout.tokenBound
  have initial := input_guard_false (program := verifiedParserCore) entry.tokenCountLocal
    workspaceLengthLocal stateCountLocal stateLocal (Int.ofNat_nonneg _)
    (by change (reader.tokenCount : Int) < 536870912; have bound : reader.tokenCount ≤ 536870911 := tokenBound; omega)
    (Int.ofNat_nonneg _) (Int.ofNat_nonneg _)
    (by change (stateId : Int) < (stateCount : Int); omega)
  have names : reader.stores.base ≠ reader.stores.output ∧ reader.stores.base ≠ reader.stores.workspace ∧
      reader.stores.base ≠ reader.offsetId ∧ reader.stores.base ≠ reader.tokenCountId ∧
      reader.stores.base ≠ workspaceLengthId ∧ reader.stores.base ≠ stateIdLocal ∧
      reader.stores.base ≠ stateCountId ∧ reader.stores.base ≠ capacityId := by simpa using baseFresh
  obtain ⟨after, execution, result, effect⟩ := entry.with_base (post := post)
    (body := reader.workspaceBody workspaceLengthId stateIdLocal stateCountId capacityId countId productionId originId)
    layoutTokens tokenBound (by simp; exact ⟨names.1, names.2.1, names.2.2.1, names.2.2.2.1⟩) (by
      intro held
      have preserve {localId : VarId} {value : Value} (different : reader.stores.base ≠ localId)
          (found : before.local? localId = some value) :
          (before.bindLocal reader.stores.base reader.baseValue).local? localId = some value :=
        (bindLocal_preserves_other_local entry.wellFormed different).trans found
      have workspaceLength := preserve names.2.2.2.2.1 workspaceLengthLocal
      have stateCountValue := preserve names.2.2.2.2.2.2.1 stateCountLocal
      have baseFits : stateBase reader.layout.tokenCount ≤ reader.workspaceValues.length := by
        rw [entry.artifact.workspaceLength]; exact reader.layout.baseFits
      have workspaceBound : reader.workspaceValues.length ≤ 2147483647 := by
        rw [entry.artifact.workspaceLength]; exact reader.layout.workspaceI32
      have countFits : (stateCount : Int) ≤
          ((reader.workspaceValues.length : Int) - (stateBase reader.layout.tokenCount : Int)) / 9 := by
        have capacityWords := stateCapacity_words_le_suffix reader.layout.tokenCount reader.layout.workspaceLength
        change stateCount ≤ stateCapacity reader.layout.tokenCount reader.layout.workspaceLength at statesFit
        rw [← entry.artifact.workspaceLength] at statesFit capacityWords
        change stateCapacity reader.layout.tokenCount reader.workspaceValues.length * 9 ≤
          reader.workspaceValues.length - stateBase reader.layout.tokenCount at capacityWords
        omega
      have guard := workspace_guard_false workspaceLength held.baseLocal stateCountValue
        (Int.ofNat_nonneg _) (by change (stateBase reader.layout.tokenCount : Int) ≤ (reader.workspaceValues.length : Int); omega)
        (by change (reader.workspaceValues.length : Int) ≤ 2147483647; omega) countFits
      obtain ⟨completed, countExecution, result, countEffect⟩ := continuation _ held
        (preserve names.2.2.2.2.2.1 stateLocal) stateCountValue (preserve names.2.2.2.2.2.2.2 capacityLocal)
      exact ⟨completed, executesSequence (executesIfFalse guard (executesSkip _ _)) countExecution, result, countEffect⟩)
  exact ⟨after, executesSequence (executesIfFalse initial (executesSkip _ _)) execution, result, effect⟩

/-- Complete success-path execution, starting with caller buffers and
    arguments. Every internal initializer, guard, loop, and store is derived.
    Source linkage and call transport are separate from this execution proof. -/
theorem ReaderRuntime.Entry.execute {reader : ReaderRuntime}
    (entry : reader.Entry before)
    (accessor : reader.stores.accessor = extractedParserStateValueFunction.id)
    (selector : reader.stores.selector = 36)
    (sound : WorkspaceBackpointersSound grammar tokens reader.workspace)
    (found : reader.workspace.state? stateId = some root)
    (layoutTokens : reader.layout.tokenCount = reader.tokenCount)
    (workspaceLengthLocal : before.local? workspaceLengthId = some (.signed .i32 (Int.ofNat reader.workspaceValues.length)))
    (stateLocal : before.local? stateIdLocal = some (.signed .i32 (Int.ofNat stateId)))
    (stateCountLocal : before.local? stateCountId = some (.signed .i32 (Int.ofNat stateCount)))
    (stateBound : stateId < stateCount) (statesFit : stateCount ≤ reader.layout.capacity)
    (capacityLocal : before.local? capacityId = some (.signed .i32 (Int.ofNat reader.outputValues.length)))
    (baseFresh : reader.stores.base ∉ [reader.stores.output, reader.stores.workspace, reader.offsetId,
      reader.tokenCountId, workspaceLengthId, stateIdLocal, stateCountId, capacityId])
    (countFresh : countId ∉ reader.readonlyLocals ++ [stateIdLocal, stateCountId, capacityId])
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
      Executes verifiedParserCore before
        (reader.entryBody workspaceLengthId stateIdLocal stateCountId capacityId countId productionId originId)
        (.returned (some (.signed .i32 (Int.ofNat root.dot)))) after ∧
      after.cellEntry? reader.outputCell = some {
        id := reader.outputCell, value := some (.array (signedI32Values
          (leading ++ derivationRecordWords root children ++ trailing))) } ∧
      RecognizerWorkspaceArtifact reader.layout reader.workspace reader.workspaceValues reader.workspaceCell after ∧
      CellEffect (CellSet.singleton reader.outputCell) before after := by
  let post := fun cells : List Cell => ∃ children, children.length = root.dot ∧
    derivationChildren? reader.workspace (stateId + 1) stateId = some children ∧
    ({before with cells := cells} : State).cellEntry? reader.outputCell = some {
      id := reader.outputCell, value := some (.array (signedI32Values
        (leading ++ derivationRecordWords root children ++ trailing))) }
  obtain ⟨after, execution, result, effect⟩ := entry.with_checked_count (post := post)
    layoutTokens workspaceLengthLocal stateLocal stateCountLocal stateBound statesFit capacityLocal baseFresh (by
      intro initialized held current stateCountValue capacity
      obtain ⟨children, completed, length, computed, countExecution, output, _, countEffect⟩ :=
        held.execute_count accessor selector sound found current
          stateCountValue stateBound capacity countFresh productionFresh
          originFresh tokenCount distinctBuffers capacityBound different currentFresh remainingFresh metadataFresh
          freshSlot previousFresh tagFresh payloadFresh distinct contents offset pendingLength
      exact ⟨completed, countExecution,
        ⟨children, length, computed, output⟩, countEffect⟩)
  obtain ⟨children, length, computed, output⟩ := result
  refine ⟨children, after, length, computed,
    execution, output, ?_, effect⟩
  exact ⟨entry.artifact.workspaceLength, entry.artifact.workspaceEncoded,
    effect.preserves_entry entry.wellFormed entry.artifact.workspaceBacking (Ne.symm distinctBuffers)⟩

end Lanius.Extraction.ParserDerivation
