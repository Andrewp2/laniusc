import Lanius.Extraction.Parser.Tree.Source
import Lanius.CallContracts
import Lanius.ExecutionRules
import Lanius.FunctionalViewCoreSimulation
import Lanius.Separation.CellEffect
import Lanius.Separation.SliceStore

namespace Lanius.Extraction.ParserTreeSource

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView
open Lanius.FunctionalView.Core

def resultValue (typeId : Lanius.TypeId) (status nodes words : Int) : Value :=
  .structure typeId [.signed .i32 status, .signed .i32 nodes, .signed .i32 words]

private theorem readLocal {id : Lanius.VarId} (found : before.local? id = some value) :
    Evaluates program before (.local id) value before :=
  Lanius.Semantics.evaluatesLocal found

private theorem checkedSourceFunction_found
    (checked : Lanius.Extraction.CoreSynthesis.Program.CheckedSourceFunction
      program modulePath name) :
    program.core.function? checked.function.id = some checked.function := by
  rw [show checked.function.id = checked.source.id by
    simpa [Program.function?] using List.find?_some checked.found]
  exact checked.found

/-- The checked constructor packages its three actual argument values and
    has no caller-visible writes. No constructor execution is assumed. -/
theorem CheckedVisit.constructor_call (checked : CheckedVisit program)
    (wellFormed : StateWellFormed afterArguments)
    (argumentsResult : ArgumentsEvaluateTo program.core before arguments
      [.signed .i32 status, .signed .i32 nodes, .signed .i32 words] afterArguments) :
    ∃ after, Evaluates program.core before (.call checked.symbols.result arguments)
      (resultValue checked.symbols.resultType status nodes words) after ∧
      ModifiesOnly CellSet.empty afterArguments after ∧ StateWellFormed after := by
  let environment : Env 3
    | ⟨0, _⟩ => .signed .i32 status
    | ⟨1, _⟩ => .signed .i32 nodes
    | ⟨2, _⟩ => .signed .i32 words
  let bindings := parameterBindings environment
  let callee := enterCall afterArguments bindings
  have localAt : ∀ index : Fin 3,
      callee.local? index.val = some (environment index) :=
    enterCall_parameterBindings_matches (environment := environment) wellFormed
  have body : Executes program.core callee (resultBody checked.symbols.resultType)
      (.returned (some (resultValue checked.symbols.resultType status nodes words))) callee :=
    executesSequenceReturned (executesReturnValue (evaluatesStructValue
      (ArgumentsEvaluateTo.cons
        (readLocal (by simpa [environment] using localAt ⟨0, by decide⟩))
        (ArgumentsEvaluateTo.cons
          (readLocal (by simpa [environment] using localAt ⟨1, by decide⟩))
          (ArgumentsEvaluateTo.cons
            (readLocal (by simpa [environment] using localAt ⟨2, by decide⟩))
            (ArgumentsEvaluateTo.nil _ _))))))
  have bound : bindParameters checked.constructor.function.parameters
      [.signed .i32 status, .signed .i32 nodes, .signed .i32 words] = some bindings := by
    rw [checked.constructorSignature.1]
    rfl
  have entered := enterCall_effect afterArguments bindings
  refine ⟨restoreLocals afterArguments callee, ?_, entered.restoreLocals,
    entered.restoreLocals_wellFormed wellFormed (enterCall_preserves_wellFormed wellFormed)⟩
  simpa only [checked.identities.2.2] using evaluatesCallReturned argumentsResult
    (checkedSourceFunction_found checked.constructor) bound checked.constructorBody body

private theorem CheckedVisit.failure_result (checked : CheckedVisit program)
    (wellFormed : StateWellFormed before)
    (status : constantValue program.core (checked.symbols.statusBase + tag) code)
    (nodesLocal : before.local? 9 = some (.signed .i32 nodes))
    (wordsLocal : before.local? 10 = some (.signed .i32 words)) :
    ∃ after, Evaluates program.core before (resultCall checked.symbols tag (.local 9) (.local 10))
      (resultValue checked.symbols.resultType code nodes words) after ∧
      ModifiesOnly CellSet.empty before after ∧ StateWellFormed after := by
  exact checked.constructor_call wellFormed
    (ArgumentsEvaluateTo.cons (evaluatesConstant status)
      (ArgumentsEvaluateTo.cons (readLocal nodesLocal)
        (ArgumentsEvaluateTo.cons (readLocal wordsLocal) (ArgumentsEvaluateTo.nil _ _))))

/-- Depth exhaustion returns before the reader or either output buffer is touched. -/
theorem CheckedVisit.depth_limit (checked : CheckedVisit program)
    (wellFormed : StateWellFormed before)
    (depthLocal : before.local? 11 = some (.signed .i32 depth))
    (nodesLocal : before.local? 9 = some (.signed .i32 nodes))
    (wordsLocal : before.local? 10 = some (.signed .i32 words))
    (exhausted : depth ≤ 0) :
    ∃ after, Executes program.core before (visitBody checked.symbols)
      (.returned (some (resultValue checked.symbols.resultType 3 nodes words))) after ∧
      ModifiesOnly CellSet.empty before after ∧ StateWellFormed after := by
  obtain ⟨after, returned, effect, afterWF⟩ := checked.failure_result wellFormed
    checked.statuses.2.2.2 nodesLocal wordsLocal
  refine ⟨after, ?_, effect, afterWF⟩
  apply executesSequenceReturned
  apply executesIfTrue (afterCondition := before)
  · exact evaluatesEagerBinary (by decide) (by decide) (readLocal depthLocal)
      (show Evaluates program.core before (.value (.signed .i32 0)) (.signed .i32 0) before from Lanius.Semantics.evaluatesValue)
      (by simp [evalBinaryValue, evalSignedBinary, exhausted])
  · exact executesSequenceReturned (executesReturnValue returned)

/-- An exhausted node table is detected before reading a derivation record.
    This distinguishes capacity failure from the preceding depth guard. -/
theorem CheckedVisit.output_full (checked : CheckedVisit program)
    (wellFormed : StateWellFormed before)
    (depthLocal : before.local? 11 = some (.signed .i32 depth))
    (capacityLocal : before.local? 8 = some (.signed .i32 capacity))
    (nodesLocal : before.local? 9 = some (.signed .i32 nodes))
    (wordsLocal : before.local? 10 = some (.signed .i32 words))
    (hasDepth : 0 < depth) (full : capacity ≤ nodes) :
    ∃ after, Executes program.core before (visitBody checked.symbols)
      (.returned (some (resultValue checked.symbols.resultType 2 nodes words))) after ∧
      ModifiesOnly CellSet.empty before after ∧ StateWellFormed after := by
  obtain ⟨after, returned, effect, afterWF⟩ := checked.failure_result wellFormed
    checked.statuses.2.2.1 nodesLocal wordsLocal
  refine ⟨after, ?_, effect, afterWF⟩
  apply executesSequence (middle := before)
  · apply executesIfFalse (afterCondition := before)
    · exact evaluatesEagerBinary (by decide) (by decide) (readLocal depthLocal)
        (show Evaluates program.core before (.value (.signed .i32 0)) (.signed .i32 0) before from Lanius.Semantics.evaluatesValue)
        (by simp [evalBinaryValue, evalSignedBinary, Int.not_le.mpr hasDepth])
    · exact executesSkip _ _
  · apply executesSequenceReturned
    apply executesIfTrue (afterCondition := before)
    · exact evaluatesEagerBinary (by decide) (by decide) (readLocal nodesLocal) (readLocal capacityLocal)
        (by simp [evalBinaryValue, evalSignedBinary, full])
    · exact executesSequenceReturned (executesReturnValue returned)

/-- A complete call-entry failure contract. Earlier arguments are unconstrained
    because these guards do not inspect the workspace, records, or offsets.
    The four scalar guard/cursor parameters come from ordinary call binding. -/
theorem CheckedVisit.failure_call (checked : CheckedVisit program)
    (wellFormed : StateWellFormed afterArguments)
    (argumentsResult : ArgumentsEvaluateTo program.core before arguments
      [workspace, workspaceLength, tokenCount, stateCount, stateId, records, recordsLength, offsets,
        .signed .i32 capacity, .signed .i32 nodes, .signed .i32 words, .signed .i32 depth] afterArguments)
    (failure : depth ≤ 0 ∨ capacity ≤ nodes) :
    ∃ after, Evaluates program.core before (.call checked.source.function.id arguments)
      (resultValue checked.symbols.resultType (if depth ≤ 0 then 3 else 2) nodes words) after ∧
      ModifiesOnly CellSet.empty afterArguments after ∧ StateWellFormed after := by
  let environment : Env 12
    | ⟨0, _⟩ => workspace
    | ⟨1, _⟩ => workspaceLength
    | ⟨2, _⟩ => tokenCount
    | ⟨3, _⟩ => stateCount
    | ⟨4, _⟩ => stateId
    | ⟨5, _⟩ => records
    | ⟨6, _⟩ => recordsLength
    | ⟨7, _⟩ => offsets
    | ⟨8, _⟩ => .signed .i32 capacity
    | ⟨9, _⟩ => .signed .i32 nodes
    | ⟨10, _⟩ => .signed .i32 words
    | ⟨11, _⟩ => .signed .i32 depth
  let bindings := parameterBindings environment
  let callee := enterCall afterArguments bindings
  have calleeWF : StateWellFormed callee := enterCall_preserves_wellFormed wellFormed
  have localAt : ∀ index : Fin 12,
      callee.local? index.val = some (environment index) :=
    enterCall_parameterBindings_matches (environment := environment) wellFormed
  have execution : ∃ completed, Executes program.core callee (visitBody checked.symbols)
      (.returned (some (resultValue checked.symbols.resultType (if depth ≤ 0 then 3 else 2) nodes words))) completed ∧
      ModifiesOnly CellSet.empty callee completed ∧ StateWellFormed completed := by
    by_cases exhausted : depth ≤ 0
    · simpa only [if_pos exhausted] using checked.depth_limit calleeWF
        (by simpa [environment] using localAt ⟨11, by decide⟩)
        (by simpa [environment] using localAt ⟨9, by decide⟩)
        (by simpa [environment] using localAt ⟨10, by decide⟩) exhausted
    · simpa only [if_neg exhausted] using checked.output_full calleeWF
        (by simpa [environment] using localAt ⟨11, by decide⟩)
        (by simpa [environment] using localAt ⟨8, by decide⟩)
        (by simpa [environment] using localAt ⟨9, by decide⟩)
        (by simpa [environment] using localAt ⟨10, by decide⟩)
        (Int.not_le.mp exhausted) (failure.resolve_left exhausted)
  obtain ⟨completed, executed, bodyEffect, completedWF⟩ := execution
  have bound : bindParameters checked.source.function.parameters
      [workspace, workspaceLength, tokenCount, stateCount, stateId, records, recordsLength, offsets,
        .signed .i32 capacity, .signed .i32 nodes, .signed .i32 words, .signed .i32 depth] = some bindings := by
    rw [checked.signature.1]
    rfl
  have effect := (enterCall_effect afterArguments bindings).trans_same bodyEffect.toStoreEffect
  exact ⟨restoreLocals afterArguments completed,
    evaluatesCallReturned argumentsResult
      (checkedSourceFunction_found checked.source) bound checked.bodyExact executed,
    effect.restoreLocals, effect.restoreLocals_wellFormed wellFormed completedWF⟩

/-- Complete any successfully expanded node. The only visible write is its
    postorder offset-table slot; record storage and unrelated buffers are framed. -/
theorem CheckedVisit.finish (checked : CheckedVisit program)
    (wellFormed : StateWellFormed before)
    (offsetsLocal : before.local? 7 = some
      (.slice (.scalar (.signed .i32)) offsetsCell [] 0 offsets.length))
    (offsetsBacking : before.cellEntry? offsetsCell = some {
      id := offsetsCell, value := some (.array (signedI32Values offsets)) })
    (capacityLocal : before.local? 8 = some (.signed .i32 (Int.ofNat offsets.length)))
    (parentLocal : before.local? 10 = some (.signed .i32 (Int.ofNat parentWord)))
    (wordsLocal : before.local? 13 = some (.signed .i32 (Int.ofNat words)))
    (nodesLocal : before.local? 14 = some (.signed .i32 (Int.ofNat nodes)))
    (room : nodes < offsets.length) (bounded : offsets.length ≤ 2147483647) :
    ∃ after, Executes program.core before (visitExit checked.symbols)
      (.returned (some (resultValue checked.symbols.resultType 0 (Int.ofNat (nodes + 1)) (Int.ofNat words)))) after ∧
      after.cellEntry? offsetsCell = some {
        id := offsetsCell, value := some (.array (signedI32Values (offsets.set nodes (Int.ofNat parentWord)))) } ∧
      CellEffect (CellSet.singleton offsetsCell) before after := by
  obtain ⟨written, store, backing, storeEffect, storeHeapFrame, _⟩ := evaluatesSliceStore program.core before before offsets
    7 (.local 14) (.local 10) offsetsCell nodes (Int.ofNat parentWord) wellFormed room offsetsLocal
    (readLocal nodesLocal) (readLocal parentLocal) (CellEffect.refl wellFormed) offsetsBacking
  have nodesAfter := storeEffect.preserves_local_of_distinct_value wellFormed nodesLocal offsetsBacking (by intro impossible; cases impossible)
  have wordsAfter := storeEffect.preserves_local_of_distinct_value wellFormed wordsLocal offsetsBacking (by intro impossible; cases impossible)
  have increment : Evaluates program.core written
      (.binary .add (.local 14) (.value (.signed .i32 1)))
      (.signed .i32 (Int.ofNat (nodes + 1))) written :=
    evaluatesNatI32Add (readLocal nodesAfter) Lanius.Semantics.evaluatesValue (by omega)
  obtain ⟨after, returned, resultEffect, afterWF⟩ := checked.constructor_call storeEffect.wellFormed
    (ArgumentsEvaluateTo.cons (evaluatesConstant checked.statuses.1)
      (ArgumentsEvaluateTo.cons increment (ArgumentsEvaluateTo.cons (readLocal wordsAfter) (ArgumentsEvaluateTo.nil _ _))))
  refine ⟨after, ?_, resultEffect.empty_preserves_entry storeEffect.wellFormed backing,
    storeEffect.trans ((CellEffect.ofModifiesOnly resultEffect afterWF).weaken CellSet.empty_subset)⟩
  apply executesSequence (middle := before)
  · apply executesIfFalse (afterCondition := before)
    · exact evaluatesEagerBinary (by decide) (by decide) (readLocal nodesLocal) (readLocal capacityLocal)
        (by simp [evalBinaryValue, evalSignedBinary, room])
    · exact executesSkip _ _
  · exact executesSequence (executesExpression store) (executesSequenceReturned (executesReturnValue returned))

/-- Expansion can consume the last available offset slot before the parent is
    allocated. The final guard returns the advanced counters without storing it. -/
theorem CheckedVisit.finish_full (checked : CheckedVisit program)
    (wellFormed : StateWellFormed before)
    (capacityLocal : before.local? 8 = some (.signed .i32 capacity))
    (wordsLocal : before.local? 13 = some (.signed .i32 words))
    (nodesLocal : before.local? 14 = some (.signed .i32 nodes))
    (full : capacity ≤ nodes) :
    ∃ after, Executes program.core before (visitExit checked.symbols)
      (.returned (some (resultValue checked.symbols.resultType 2 nodes words))) after ∧
      ModifiesOnly CellSet.empty before after ∧ StateWellFormed after := by
  obtain ⟨after, returned, effect, afterWF⟩ := checked.constructor_call wellFormed
    (ArgumentsEvaluateTo.cons (evaluatesConstant checked.statuses.2.2.1)
      (ArgumentsEvaluateTo.cons (readLocal nodesLocal) (ArgumentsEvaluateTo.cons (readLocal wordsLocal) (ArgumentsEvaluateTo.nil _ _))))
  refine ⟨after, ?_, effect, afterWF⟩
  apply executesSequenceReturned
  apply executesIfTrue (afterCondition := before)
  · exact evaluatesEagerBinary (by decide) (by decide) (readLocal nodesLocal) (readLocal capacityLocal)
      (by simp [evalBinaryValue, evalSignedBinary, full])
  · exact executesSequenceReturned (executesReturnValue returned)

end Lanius.Extraction.ParserTreeSource
