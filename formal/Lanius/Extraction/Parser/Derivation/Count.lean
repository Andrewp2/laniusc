import Lanius.Extraction.Parser.Derivation.Roots
import Lanius.Extraction.Parser.Derivation.EntryChecks

namespace Lanius.Extraction.ParserDerivation

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Compiler.Parser Lanius.Extraction.ParserRecognize

def ReaderRuntime.countContinuation (reader : ReaderRuntime)
    (stateIdLocal stateCountId capacityId countId productionId originId : VarId) : Stmt :=
  let reject := fun n => Stmt.sequence
    (.returnValue (some (.unary .negate (.value (.signed .i32 n))))) .skip
  .sequence (.ifThenElse (rangeCondition countId stateCountId) (reject 1) .skip)
      (.sequence (.ifThenElse (rangeCondition reader.offsetId capacityId) (reject 2) .skip)
        (.sequence (.ifThenElse (capacityCondition capacityId reader.offsetId countId) (reject 2) .skip)
          (reader.rootBody stateIdLocal countId productionId originId)))

def ReaderRuntime.countBody (reader : ReaderRuntime)
    (stateIdLocal stateCountId capacityId countId productionId originId : VarId) : Stmt :=
  .letLocal countId parserI32Type
    (.call extractedParserStateValueFunction.id
      [.local reader.stores.workspace, .local reader.stores.base, .local stateIdLocal, .constant 29])
    (reader.countContinuation stateIdLocal stateCountId capacityId countId productionId originId)

/-- The execution theorem and source checker describe the same statement. -/
theorem ReaderRuntime.countBody_source (reader : ReaderRuntime)
    (accessor : reader.stores.accessor = extractedParserStateValueFunction.id) :
    reader.countBody stateIdLocal stateCountId capacityId countId productionId originId =
      readerCount reader.stores reader.tail productionId originId reader.offsetId reader.tokenCountId
        countId stateIdLocal stateCountId capacityId 28 := by
  simp only [ReaderRuntime.countBody, ReaderRuntime.countContinuation, ReaderRuntime.rootBody,
    ReaderRuntime.walkBody, readerCount, readerRoots, accessor, parserI32Type]

/-- Read the child count from the actual workspace accessor, execute all
    three count/output guards, and emit the record. No saved-count premise
    or guard-execution premise is required. -/
theorem ReaderRuntime.BeforeCursor.execute_count {reader : ReaderRuntime}
    (entry : reader.BeforeCursor before)
    (accessor : reader.stores.accessor = extractedParserStateValueFunction.id)
    (selector : reader.stores.selector = 36)
    (sound : WorkspaceBackpointersSound grammar tokens reader.workspace)
    (found : reader.workspace.state? stateId = some root)
    (stateLocal : before.local? stateIdLocal = some (.signed .i32 (Int.ofNat stateId)))
    (stateCountLocal : before.local? stateCountId = some (.signed .i32 (Int.ofNat stateCount)))
    (stateBound : stateId < stateCount)
    (capacityLocal : before.local? capacityId = some (.signed .i32 (Int.ofNat reader.outputValues.length)))
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
        (reader.countBody stateIdLocal stateCountId capacityId countId productionId originId)
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
  have names : countId ∉ reader.readonlyLocals ∧ countId ≠ stateIdLocal ∧
      countId ≠ stateCountId ∧ countId ≠ capacityId := by simpa using countFresh
  have fits : reader.offset + 4 + root.dot * 3 ≤ reader.outputValues.length := by
    have length := congrArg List.length contents
    simp only [List.length_append, List.length_cons, List.length_nil] at length
    omega
  obtain ⟨after, execution, result, effect⟩ := entry.artifact.let_field (post := post)
    (body := reader.countContinuation stateIdLocal stateCountId capacityId countId productionId originId)
    entry.wellFormed found (field := 1) (selectorId := 29) (localId := countId) (by decide)
    entry.workspaceLocal entry.baseLocal stateLocal (by rfl) (by
      intro initialized readEffect _ _
      have held := (entry.after_read readEffect).bind names.1 (.signed .i32 (Int.ofNat root.dot))
      have preserve {localId : VarId} {value : Value} (different : countId ≠ localId)
          (localValue : before.local? localId = some value) :
          (initialized.bindLocal countId (.signed .i32 (Int.ofNat root.dot))).local? localId = some value :=
        (bindLocal_preserves_other_local readEffect.wellFormed different).trans
          (readEffect.empty_preserves_local entry.wellFormed localValue)
      have count := bindLocal_finds_local initialized countId (.signed .i32 (Int.ofNat root.dot)) readEffect.wellFormed
      have countGuard := range_guard_false (program := verifiedParserCore) count
        (preserve names.2.2.1 stateCountLocal) (Int.ofNat_nonneg _)
        (by have bound := sound.dot_le_stateId found; change (root.dot : Int) ≤ (stateCount : Int); omega)
      have offsetGuard := range_guard_false (program := verifiedParserCore) held.offsetLocal
        (preserve names.2.2.2 capacityLocal) (Int.ofNat_nonneg _)
        (by change (reader.offset : Int) ≤ (reader.outputValues.length : Int); omega)
      have capacityGuard := output_capacity_guard_false (program := verifiedParserCore)
        (preserve names.2.2.2 capacityLocal) held.offsetLocal count (Int.ofNat_nonneg _) (Int.ofNat_nonneg _)
        (by change (reader.offset : Int) + 4 + (root.dot : Int) * 3 ≤ (reader.outputValues.length : Int); omega)
        (by change (reader.outputValues.length : Int) ≤ 2147483647; omega)
      obtain ⟨children, completed, length, computed, roots, output, _, recordEffect⟩ :=
        held.execute_roots accessor selector sound found (preserve names.2.1 stateLocal) count
          productionFresh originFresh tokenCount distinctBuffers capacityBound different currentFresh
          remainingFresh metadataFresh freshSlot previousFresh tagFresh payloadFresh distinct contents offset pendingLength
      exact ⟨completed,
        executesSequence (executesIfFalse countGuard (executesSkip _ _))
          (executesSequence (executesIfFalse offsetGuard (executesSkip _ _))
            (executesSequence (executesIfFalse capacityGuard (executesSkip _ _)) roots)),
        ⟨children, length, computed, output⟩, recordEffect⟩)
  obtain ⟨children, length, computed, output⟩ := result
  refine ⟨children, after, length, computed, execution, output, ?_, effect⟩
  exact ⟨entry.artifact.workspaceLength, entry.artifact.workspaceEncoded,
    effect.preserves_entry entry.wellFormed entry.artifact.workspaceBacking (Ne.symm distinctBuffers)⟩

end Lanius.Extraction.ParserDerivation
