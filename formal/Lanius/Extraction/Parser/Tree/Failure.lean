import Lanius.Extraction.Parser.Tree.Caller
import Lanius.Extraction.Parser.Derivation.Failure

namespace Lanius.Extraction.ParserTreeSource

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.Compiler.Parser Lanius.Extraction.ParserRecognize Lanius.Extraction.ParserDerivation

private theorem local_read {id : Lanius.VarId} (found : before.local? id = some value) :
    Evaluates program before (.local id) value before :=
  ⟨1, evalLocal_of_local 0 program before id value found⟩

/-- Derive the failed reader call and execute the complete materializer body
    through its `-2` branch. All original output contents and counters survive. -/
theorem TreeRuntime.CallEntry.reader_full {runtime : TreeRuntime} {symbols : Core.Relocation.Symbols}
    (input : runtime.CallEntry layout workspace workspaceValues workspaceCell stateId depth before)
    (checked : CheckedVisit program) (linked : LinkedReader checked.reader allowed symbols)
    (inverseType : Lanius.TypeId → Lanius.TypeId) (inverse : Function.RightInverse inverseType symbols.typeId)
    (sound : WorkspaceBackpointersSound grammar tokens workspace)
    (found : workspace.state? stateId = some runtime.parent)
    (positive : 0 < depth) (room : runtime.nodeBase < runtime.offsets.length)
    (offsetBound : runtime.wordBase ≤ runtime.records.length)
    (recordsBound : runtime.records.length ≤ 2147483647)
    (full : runtime.records.length < runtime.wordBase + 4 + runtime.parent.dot * 3) :
    ∃ after, Executes program.core before (visitBody checked.symbols)
        (.returned (some (resultValue checked.symbols.resultType 2
          (Int.ofNat runtime.nodeBase) (Int.ofNat runtime.wordBase)))) after ∧
      CellEffect CellSet.empty before after := by
  obtain ⟨afterRead, read, readEffect⟩ := linked.call_full inverseType inverse sound found input.frame.wellFormed
    input.frame.artifact input.recordsBacking offsetBound recordsBound full (input.reader_arguments program.core)
  rw [← checked.identities.2.1] at read
  have depthGuard : Evaluates program.core before
      (.binary .lessEqual (.local 11) (.value (.signed .i32 0))) (.boolean false) before :=
    evaluatesEagerBinary (by decide) (by decide) (local_read input.frame.depthLocal) ⟨1, rfl⟩
      (by simp [evalBinaryValue, evalSignedBinary, Nat.ne_of_gt positive])
  have capacityGuard : Evaluates program.core before
      (.binary .greaterEqual (.local 9) (.local 8)) (.boolean false) before :=
    evaluatesEagerBinary (by decide) (by decide) (local_read input.nodesLocal) (local_read input.capacityLocal)
      (by simp [evalBinaryValue, evalSignedBinary, room])
  let bound := afterRead.bindLocal 12 (.signed .i32 (-2))
  have boundWF : StateWellFormed bound := bindLocal_preserves_well_formed _ _ _ readEffect.wellFormed
  have countLocal : bound.local? 12 = some (.signed .i32 (-2)) :=
    bindLocal_finds_local _ _ _ readEffect.wellFormed
  have nodesLocal : bound.local? 9 = some (.signed .i32 (Int.ofNat runtime.nodeBase)) :=
    (bindLocal_preserves_other_local readEffect.wellFormed (show (12 : Lanius.VarId) ≠ 9 by decide)).trans
      (readEffect.empty_preserves_local input.frame.wellFormed input.nodesLocal)
  have wordsLocal : bound.local? 10 = some (.signed .i32 (Int.ofNat runtime.wordBase)) :=
    (bindLocal_preserves_other_local readEffect.wellFormed (show (12 : Lanius.VarId) ≠ 10 by decide)).trans
      (readEffect.empty_preserves_local input.frame.wellFormed input.wordsLocal)
  have negativeTwo : Evaluates program.core bound (.unary .negate (.value (.signed .i32 2)))
      (.signed .i32 (-2)) bound := by
    apply evaluatesUnary (show Evaluates program.core bound (.value (.signed .i32 2)) (.signed .i32 2) bound from ⟨1, rfl⟩)
    simp [evalUnaryValue, wrapSigned, signedModulus, signedSignBit, SignedIntTy.bits]
  have countFull : Evaluates program.core bound
      (.binary .equal (.local 12) (.unary .negate (.value (.signed .i32 2)))) (.boolean true) bound :=
    evaluatesEagerBinary (by decide) (by decide) (local_read countLocal) negativeTwo rfl
  obtain ⟨completed, resultCall, resultEffect, completedWF⟩ := checked.constructor_call boundWF
    (.cons (evaluatesConstant checked.statuses.2.2.1) (.cons (local_read nodesLocal)
      (.cons (local_read wordsLocal) (.nil _ _))))
  refine ⟨restoreLocals afterRead completed, ?_, readEffect.trans
    (CellEffect.closeLocal afterRead 12 (.signed .i32 (-2)) readEffect.wellFormed
      (CellEffect.ofModifiesOnly resultEffect completedWF))⟩
  apply executesSequence (executesIfFalse depthGuard (executesSkip _ _))
  apply executesSequence (executesIfFalse capacityGuard (executesSkip _ _))
  apply executesLetLocal (afterInitializer := afterRead) (completed := completed) read
  exact executesSequenceReturned (executesIfTrue countFull (executesSequenceReturned (executesReturnValue resultCall)))

/-- A whole actual `visit` call rejects insufficient record storage, including
    at a nested call after earlier output. No failed-reader execution is assumed. -/
theorem CheckedVisit.record_full_call {symbols : Core.Relocation.Symbols}
    (checked : CheckedVisit program) (linked : LinkedReader checked.reader allowed symbols)
    (inverseType : Lanius.TypeId → Lanius.TypeId) (inverse : Function.RightInverse inverseType symbols.typeId)
    (sound : WorkspaceBackpointersSound grammar tokens workspace)
    (runtime : TreeRuntime) (stateId : Nat)
    (found : workspace.state? stateId = some runtime.parent)
    (wellFormed : StateWellFormed afterArguments)
    (artifact : RecognizerWorkspaceArtifact layout workspace workspaceValues workspaceCell afterArguments)
    (records : afterArguments.cellEntry? runtime.recordsCell = some {
      id := runtime.recordsCell, value := some (.array (signedI32Values runtime.records)) })
    (offsets : afterArguments.cellEntry? runtime.offsetsCell = some {
      id := runtime.offsetsCell, value := some (.array (signedI32Values runtime.offsets)) })
    (recordsSeparate : workspaceCell ≠ runtime.recordsCell) (offsetsSeparate : workspaceCell ≠ runtime.offsetsCell)
    (buffersDistinct : runtime.recordsCell ≠ runtime.offsetsCell)
    (depthBound : depth ≤ 2147483647) (positive : 0 < depth) (room : runtime.nodeBase < runtime.offsets.length)
    (offsetBound : runtime.wordBase ≤ runtime.records.length) (recordsBound : runtime.records.length ≤ 2147483647)
    (full : runtime.records.length < runtime.wordBase + 4 + runtime.parent.dot * 3)
    (argumentsResult : ArgumentsEvaluateTo program.core before arguments
      (runtime.visitValues workspaceValues workspaceCell layout.tokenCount workspace.states.length stateId depth)
      afterArguments) :
    ∃ after, Evaluates program.core before (.call checked.symbols.visit arguments)
        (resultValue checked.symbols.resultType 2 (Int.ofNat runtime.nodeBase) (Int.ofNat runtime.wordBase)) after ∧
      CellEffect CellSet.empty afterArguments after := by
  have input := runtime.enter (stateId := stateId) wellFormed artifact records offsets
    recordsSeparate offsetsSeparate buffersDistinct depthBound
  obtain ⟨completed, execution, effect⟩ := input.reader_full checked linked inverseType inverse sound found
    positive room offsetBound recordsBound full
  have identity : checked.source.function.id = checked.source.source.id := by
    simpa [Program.function?] using List.find?_some checked.source.found
  have functionFound : program.core.function? checked.source.function.id = some checked.source.function := by
    rw [identity]
    exact checked.source.found
  refine ⟨restoreLocals afterArguments completed, ?_, CellEffect.closeCall afterArguments _ wellFormed effect⟩
  rw [checked.identities.1]
  exact evaluatesCallReturned argumentsResult functionFound (checked.bind_parameters runtime) checked.bodyExact execution

/-- A failed child exits the entire iteration without additional parent-payload,
    counter, or sibling-cursor updates. The outer induction supplies the
    actual nested call; only its two output arrays can have changed. -/
theorem TreeRuntime.At.state_failure {runtime : TreeRuntime}
    (held : runtime.At trees (.state childId :: pending) before) (checked : CheckedVisit program)
    (call : Evaluates program.core (runtime.slotState trees before) (recursiveCall checked.symbols)
      (resultValue checked.symbols.resultType code nodes words) afterCall)
    (effect : CellEffect runtime.outputs (runtime.slotState trees before) afterCall)
    (failed : code ≠ 0) :
    ∃ after, Executes program.core before (childIteration checked.symbols)
        (.returned (some (resultValue checked.symbols.resultType code nodes words))) after ∧
      after.cells = (afterCall.bindLocal 17 (resultValue checked.symbols.resultType code nodes words)).cells ∧
      CellEffect runtime.outputs before after := by
  obtain ⟨slotEvaluation, tagEqual⟩ := held.state_entry checked
  let value := resultValue checked.symbols.resultType code nodes words
  let completed := afterCall.bindLocal 17 value
  have resultLocal : completed.local? 17 = some value := bindLocal_finds_local _ _ _ effect.wellFormed
  have completedWF : StateWellFormed completed := bindLocal_preserves_well_formed _ _ _ effect.wellFormed
  have nested : Executes program.core (runtime.slotState trees before) (childExpansion checked.symbols)
      (.returned (some value)) (restoreLocals afterCall completed) :=
    executesLetLocal (afterInitializer := afterCall) (completed := completed) call
      (checked.resume_failure resultLocal failed)
  have resultEffect : CellEffect CellSet.empty afterCall (restoreLocals afterCall completed) :=
    CellEffect.closeLocal afterCall 17 value effect.wellFormed (CellEffect.refl completedWF)
  exact ⟨restoreLocals before (restoreLocals afterCall completed),
    executesLetLocal slotEvaluation (executesSequenceReturned (executesIfTrue tagEqual nested)), rfl,
    CellEffect.closeLocal before 16 (.signed .i32 (Int.ofNat (runtime.wordBase + 4 + trees.length * 3)))
      held.wellFormed (effect.trans (resultEffect.weaken CellSet.empty_subset))⟩

end Lanius.Extraction.ParserTreeSource
