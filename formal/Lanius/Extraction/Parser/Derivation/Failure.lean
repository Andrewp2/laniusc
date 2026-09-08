import Lanius.Extraction.Parser.Derivation.Recognition

namespace Lanius.Extraction.ParserDerivation

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.Compiler.Parser Lanius.Extraction.ParserRecognize

/-- A resident state's record does not fit. Read its actual child count,
    execute the guards, return `-2`, and leave all existing cells unchanged. -/
theorem ReaderRuntime.BeforeCursor.count_full {reader : ReaderRuntime}
    (entry : reader.BeforeCursor before)
    (sound : WorkspaceBackpointersSound grammar tokens reader.workspace)
    (found : reader.workspace.state? stateId = some root)
    (stateLocal : before.local? stateIdLocal = some (.signed .i32 (Int.ofNat stateId)))
    (stateCountLocal : before.local? stateCountId = some (.signed .i32 (Int.ofNat stateCount)))
    (stateBound : stateId < stateCount)
    (capacityLocal : before.local? capacityId = some (.signed .i32 (Int.ofNat reader.outputValues.length)))
    (countFresh : countId ∉ reader.readonlyLocals ++ [stateIdLocal, stateCountId, capacityId])
    (offsetBound : reader.offset ≤ reader.outputValues.length)
    (capacityBound : reader.outputValues.length ≤ 2147483647)
    (full : reader.outputValues.length < reader.offset + 4 + root.dot * 3) :
    ∃ after, Executes verifiedParserCore before
        (reader.countBody stateIdLocal stateCountId capacityId countId productionId originId)
        (.returned (some (.signed .i32 (-2)))) after ∧ CellEffect CellSet.empty before after := by
  have names : countId ∉ reader.readonlyLocals ∧ countId ≠ stateIdLocal ∧
      countId ≠ stateCountId ∧ countId ≠ capacityId := by simpa using countFresh
  obtain ⟨after, execution, _, effect⟩ := entry.artifact.let_field (post := fun _ => True) (writes := CellSet.empty)
    (body := reader.countContinuation stateIdLocal stateCountId capacityId countId productionId originId)
    entry.wellFormed found (field := 1) (selectorId := 29) (localId := countId) (by decide)
    entry.workspaceLocal entry.baseLocal stateLocal rfl (by
      intro initialized readEffect boundWF _
      have held := (entry.after_read readEffect).bind names.1 (.signed .i32 (Int.ofNat root.dot))
      have preserve {localId : VarId} {value : Value} (different : countId ≠ localId)
          (localValue : before.local? localId = some value) :
          (initialized.bindLocal countId (.signed .i32 (Int.ofNat root.dot))).local? localId = some value :=
        (bindLocal_preserves_other_local readEffect.wellFormed different).trans
          (readEffect.empty_preserves_local entry.wellFormed localValue)
      have count := bindLocal_finds_local initialized countId (.signed .i32 (Int.ofNat root.dot)) readEffect.wellFormed
      have capacity := preserve names.2.2.2 capacityLocal
      have countGuard := range_guard_false (program := verifiedParserCore) count
        (preserve names.2.2.1 stateCountLocal) (Int.ofNat_nonneg _)
        (by have bound := sound.dot_le_stateId found; change (root.dot : Int) ≤ (stateCount : Int); omega)
      have offsetGuard := range_guard_false (program := verifiedParserCore) held.offsetLocal capacity (Int.ofNat_nonneg _)
        (by change (reader.offset : Int) ≤ (reader.outputValues.length : Int); omega)
      have capacityGuard := output_capacity_guard_true (program := verifiedParserCore) capacity held.offsetLocal count
        (Int.ofNat_nonneg _) (by change (reader.offset : Int) ≤ (reader.outputValues.length : Int); omega)
        (by change (reader.outputValues.length : Int) < (reader.offset : Int) + 4 + (root.dot : Int) * 3; omega)
        (by change (reader.outputValues.length : Int) ≤ 2147483647; omega)
      have negativeTwo : Evaluates verifiedParserCore
          (initialized.bindLocal countId (.signed .i32 (Int.ofNat root.dot)))
          (.unary .negate (.value (.signed .i32 2))) (.signed .i32 (-2))
          (initialized.bindLocal countId (.signed .i32 (Int.ofNat root.dot))) := by
        apply evaluatesUnary (show Evaluates verifiedParserCore _ (.value (.signed .i32 2)) (.signed .i32 2) _ from ⟨1, rfl⟩)
        simp [evalUnaryValue, wrapSigned, signedModulus, signedSignBit, SignedIntTy.bits]
      exact ⟨_, executesSequence (executesIfFalse countGuard (executesSkip _ _))
        (executesSequence (executesIfFalse offsetGuard (executesSkip _ _))
          (executesSequenceReturned (executesIfTrue capacityGuard
            (executesSequenceReturned (executesReturnValue negativeTwo))))), trivial, CellEffect.refl boundWF⟩)
  exact ⟨after, execution, effect⟩

/-- Full reader-body capacity failure, including the shared entry checks and
    both fresh lexical scopes. No record header has been written on this path. -/
theorem ReaderRuntime.Entry.output_full {reader : ReaderRuntime}
    (entry : reader.Entry before)
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
    (offsetBound : reader.offset ≤ reader.outputValues.length)
    (capacityBound : reader.outputValues.length ≤ 2147483647)
    (full : reader.outputValues.length < reader.offset + 4 + root.dot * 3) :
    ∃ after, Executes verifiedParserCore before
        (reader.entryBody workspaceLengthId stateIdLocal stateCountId capacityId countId productionId originId)
        (.returned (some (.signed .i32 (-2)))) after ∧ CellEffect CellSet.empty before after := by
  obtain ⟨after, execution, _, effect⟩ := entry.with_checked_count (post := fun _ => True)
    (productionId := productionId) (originId := originId)
    layoutTokens workspaceLengthLocal stateLocal stateCountLocal stateBound statesFit capacityLocal baseFresh (by
      intro initialized held current states capacity
      obtain ⟨completed, execution, effect⟩ := held.count_full sound found current states stateBound capacity countFresh
        offsetBound capacityBound full
      exact ⟨completed, execution, trivial, effect⟩)
  exact ⟨after, execution, effect⟩

/-- Construct the full reader's capacity failure from ordinary caller storage.
    No private locals, count read, or failed body execution are assumed. -/
theorem CheckedReader.execute_full (reader : CheckedReader program)
    (sound : WorkspaceBackpointersSound grammar tokens workspace)
    (found : workspace.state? stateId = some state)
    (wellFormed : StateWellFormed caller)
    (artifact : RecognizerWorkspaceArtifact layout workspace workspaceValues workspaceCell caller)
    (output : caller.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values outputValues)) })
    (offsetBound : offset ≤ outputValues.length) (capacityBound : outputValues.length ≤ 2147483647)
    (full : outputValues.length < offset + 4 + state.dot * 3) :
    ∃ after, Executes verifiedParserCore
        (readerCallee caller workspaceValues outputValues workspaceCell outputCell
          layout.tokenCount workspace.states.length stateId offset)
        reader.standaloneBody (.returned (some (.signed .i32 (-2)))) after ∧
      CellEffect CellSet.empty
        (readerCallee caller workspaceValues outputValues workspaceCell outputCell
          layout.tokenCount workspace.states.length stateId offset) after := by
  have entry := reader.enter (offset := offset) (stateCount := workspace.states.length) (stateId := stateId)
    wellFormed artifact output
  have parameters := reader_parameters (workspaceValues := workspaceValues) (outputValues := outputValues)
    (workspaceCell := workspaceCell) (outputCell := outputCell) (tokenCount := layout.tokenCount)
    (stateCount := workspace.states.length) (stateId := stateId) (offset := offset) wellFormed
  have names := reader.namesDistinct
  have workspaceParameter := reader.bufferParameters.1
  have outputParameter := reader.bufferParameters.2
  simp only [readerLocals, List.nodup_cons] at names
  obtain ⟨after, execution, effect⟩ := entry.output_full (countId := 9) (productionId := 10) (originId := 11)
    sound found rfl (parameters ⟨1, by decide⟩) (parameters ⟨4, by decide⟩) (parameters ⟨3, by decide⟩)
    (getElem?_some_implies_bound found) artifact.workspaceEncoded.stateCountFits (parameters ⟨6, by decide⟩)
    (by simp_all [CheckedReader.runtime, CheckedReader.standaloneStores, ne_comm])
    (by simp_all [CheckedReader.runtime, CheckedReader.standaloneStores, ReaderRuntime.readonlyLocals, ne_comm])
    offsetBound capacityBound full
  refine ⟨after, ?_, effect⟩
  rw [← reader.runtime_body (layout := layout) (workspace := workspace)
    (workspaceValues := workspaceValues) (outputValues := outputValues)
    (workspaceCell := workspaceCell) (outputCell := outputCell) (offset := offset)]
  exact execution

/-- The actual linked reader call returns `-2` without changing any existing
    caller cell. The inverse type map permits arbitrary unrelated caller values. -/
theorem LinkedReader.call_full {symbols : Core.Relocation.Symbols} {reader : CheckedReader program}
    (checked : LinkedReader reader allowed symbols)
    (inverseType : Lanius.TypeId → Lanius.TypeId) (inverse : Function.RightInverse inverseType symbols.typeId)
    (sound : WorkspaceBackpointersSound grammar tokens workspace)
    (found : workspace.state? stateId = some state)
    (wellFormed : StateWellFormed caller)
    (artifact : RecognizerWorkspaceArtifact layout workspace workspaceValues workspaceCell caller)
    (output : caller.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values outputValues)) })
    (offsetBound : offset ≤ outputValues.length) (capacityBound : outputValues.length ≤ 2147483647)
    (full : outputValues.length < offset + 4 + state.dot * 3)
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments
      (readerValues workspaceValues outputValues workspaceCell outputCell layout.tokenCount
        workspace.states.length stateId offset) caller) :
    ∃ after, Evaluates program.core caller (.call reader.source.function.id arguments) (.signed .i32 (-2)) after ∧
      CellEffect CellSet.empty caller after := by
  let unrelocate : Core.Relocation.Symbols := ⟨inverseType, id, id⟩
  have restored : Semantics.Relocation.state symbols (Semantics.Relocation.state unrelocate caller) = caller :=
    Semantics.Relocation.state_leftInverse symbols unrelocate inverse caller
  obtain ⟨completed, execution, effect⟩ := reader.execute_full sound found
    (Semantics.Relocation.state_wellFormed unrelocate wellFormed)
    (relocate_workspace unrelocate artifact) (relocate_words unrelocate output) offsetBound capacityBound full
  have body := checked.executes execution
  rw [readerCallee_relocated, restored] at body
  have linkedEffect := effect.relocate symbols
  rw [readerCallee_relocated, restored] at linkedEffect
  exact ⟨restoreLocals caller (Semantics.Relocation.state symbols completed),
    reader.call_returns argumentsResult body, CellEffect.closeCall caller _ wellFormed linkedEffect⟩

end Lanius.Extraction.ParserDerivation
