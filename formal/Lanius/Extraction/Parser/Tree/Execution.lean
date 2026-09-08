import Lanius.Extraction.Parser.Tree.Source
import Lanius.CallContracts
import Lanius.ExecutionRules
import Lanius.Separation.CellEffect
import Lanius.Separation.SliceStore

namespace Lanius.Extraction.ParserTreeSource

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts

def resultValue (typeId : Lanius.TypeId) (status nodes words : Int) : Value :=
  .structure typeId [.signed .i32 status, .signed .i32 nodes, .signed .i32 words]

def resultBindings (status nodes words : Int) : List (Lanius.VarId × Value) :=
  [(0, .signed .i32 status), (1, .signed .i32 nodes), (2, .signed .i32 words)]

private theorem readLocal {id : Lanius.VarId} (found : before.local? id = some value) :
    Evaluates program before (.local id) value before :=
  ⟨1, evalLocal_of_local 0 program before id value found⟩

/-- The checked constructor packages its three actual argument values and
    has no caller-visible writes. No constructor execution is assumed. -/
theorem CheckedVisit.constructor_call (checked : CheckedVisit program)
    (wellFormed : StateWellFormed afterArguments)
    (argumentsResult : ArgumentsEvaluateTo program.core before arguments
      [.signed .i32 status, .signed .i32 nodes, .signed .i32 words] afterArguments) :
    ∃ after, Evaluates program.core before (.call checked.symbols.result arguments)
      (resultValue checked.symbols.resultType status nodes words) after ∧
      ModifiesOnly CellSet.empty afterArguments after ∧ StateWellFormed after := by
  let bindings := resultBindings status nodes words
  let callee := enterCall afterArguments bindings
  have statusLocal : callee.local? 0 = some (.signed .i32 status) := by
    exact enterCall_local_of_binding afterArguments []
      [(1, .signed .i32 nodes), (2, .signed .i32 words)] 0 (.signed .i32 status)
      wellFormed (by simp)
  have nodesLocal : callee.local? 1 = some (.signed .i32 nodes) := by
    exact enterCall_local_of_binding afterArguments [(0, .signed .i32 status)]
      [(2, .signed .i32 words)] 1 (.signed .i32 nodes) wellFormed (by simp)
  have wordsLocal : callee.local? 2 = some (.signed .i32 words) := by
    exact enterCall_local_of_binding afterArguments
      [(0, .signed .i32 status), (1, .signed .i32 nodes)] [] 2 (.signed .i32 words)
      wellFormed (by simp)
  have body : Executes program.core callee (resultBody checked.symbols.resultType)
      (.returned (some (resultValue checked.symbols.resultType status nodes words))) callee :=
    executesSequenceReturned (executesReturnValue (evaluatesStructValue
      (ArgumentsEvaluateTo.cons (readLocal statusLocal) (ArgumentsEvaluateTo.cons (readLocal nodesLocal)
        (ArgumentsEvaluateTo.cons (readLocal wordsLocal) (ArgumentsEvaluateTo.nil _ _))))))
  have identity : checked.constructor.function.id = checked.constructor.source.id := by
    simpa [Program.function?] using List.find?_some checked.constructor.found
  have found : program.core.function? checked.constructor.function.id = some checked.constructor.function := by
    rw [identity]
    exact checked.constructor.found
  have bound : bindParameters checked.constructor.function.parameters
      [.signed .i32 status, .signed .i32 nodes, .signed .i32 words] = some bindings := by
    rw [checked.constructorSignature.1]
    rfl
  have entered := enterCall_effect afterArguments bindings
  refine ⟨restoreLocals afterArguments callee, ?_, entered.restoreLocals,
    entered.restoreLocals_wellFormed wellFormed (enterCall_preserves_wellFormed wellFormed)⟩
  rw [checked.identities.2.2]
  exact evaluatesCallReturned argumentsResult found bound checked.constructorBody body

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
      (show Evaluates program.core before (.value (.signed .i32 0)) (.signed .i32 0) before from ⟨1, rfl⟩)
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
        (show Evaluates program.core before (.value (.signed .i32 0)) (.signed .i32 0) before from ⟨1, rfl⟩)
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
  let leading : List (Lanius.VarId × Value) :=
    [(0, workspace), (1, workspaceLength), (2, tokenCount), (3, stateCount),
      (4, stateId), (5, records), (6, recordsLength), (7, offsets)]
  let bindings := leading ++ [(8, .signed .i32 capacity), (9, .signed .i32 nodes),
    (10, .signed .i32 words), (11, .signed .i32 depth)]
  let callee := enterCall afterArguments bindings
  have calleeWF : StateWellFormed callee := enterCall_preserves_wellFormed wellFormed
  have capacityLocal : callee.local? 8 = some (.signed .i32 capacity) :=
    enterCall_local_of_binding afterArguments leading
      [(9, .signed .i32 nodes), (10, .signed .i32 words), (11, .signed .i32 depth)]
      8 (.signed .i32 capacity) wellFormed (by simp)
  have nodesLocal : callee.local? 9 = some (.signed .i32 nodes) := by
    exact enterCall_local_of_binding afterArguments (leading.append [(8, .signed .i32 capacity)])
        [(10, .signed .i32 words), (11, .signed .i32 depth)] 9 (.signed .i32 nodes) wellFormed (by simp)
  have wordsLocal : callee.local? 10 = some (.signed .i32 words) := by
    exact enterCall_local_of_binding afterArguments (leading.append [(8, .signed .i32 capacity), (9, .signed .i32 nodes)])
        [(11, .signed .i32 depth)] 10 (.signed .i32 words) wellFormed (by simp)
  have depthLocal : callee.local? 11 = some (.signed .i32 depth) := by
    exact enterCall_local_of_binding afterArguments (leading.append [(8, .signed .i32 capacity),
        (9, .signed .i32 nodes), (10, .signed .i32 words)]) [] 11 (.signed .i32 depth) wellFormed (by simp)
  have execution : ∃ completed, Executes program.core callee (visitBody checked.symbols)
      (.returned (some (resultValue checked.symbols.resultType (if depth ≤ 0 then 3 else 2) nodes words))) completed ∧
      ModifiesOnly CellSet.empty callee completed ∧ StateWellFormed completed := by
    by_cases exhausted : depth ≤ 0
    · simpa only [if_pos exhausted] using checked.depth_limit calleeWF depthLocal nodesLocal wordsLocal exhausted
    · simpa only [if_neg exhausted] using checked.output_full calleeWF depthLocal capacityLocal nodesLocal wordsLocal
        (Int.not_le.mp exhausted) (failure.resolve_left exhausted)
  obtain ⟨completed, executed, bodyEffect, completedWF⟩ := execution
  have identity : checked.source.function.id = checked.source.source.id := by
    simpa [Program.function?] using List.find?_some checked.source.found
  have found : program.core.function? checked.source.function.id = some checked.source.function := by
    rw [identity]
    exact checked.source.found
  have bound : bindParameters checked.source.function.parameters
      [workspace, workspaceLength, tokenCount, stateCount, stateId, records, recordsLength, offsets,
        .signed .i32 capacity, .signed .i32 nodes, .signed .i32 words, .signed .i32 depth] = some bindings := by
    rw [checked.signature.1]
    rfl
  have effect := (enterCall_effect afterArguments bindings).trans_same bodyEffect.toStoreEffect
  exact ⟨restoreLocals afterArguments completed,
    evaluatesCallReturned argumentsResult found bound checked.bodyExact executed,
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
  obtain ⟨written, store, backing, storeEffect⟩ := evaluatesSliceStore program.core before before offsets
    7 (.local 14) (.local 10) offsetsCell nodes (Int.ofNat parentWord) wellFormed room offsetsLocal
    (readLocal nodesLocal) (readLocal parentLocal) (CellEffect.refl wellFormed) offsetsBacking
  have nodesAfter := storeEffect.preserves_local_of_distinct_value wellFormed nodesLocal offsetsBacking (by intro impossible; cases impossible)
  have wordsAfter := storeEffect.preserves_local_of_distinct_value wellFormed wordsLocal offsetsBacking (by intro impossible; cases impossible)
  have increment : Evaluates program.core written
      (.binary .add (.local 14) (.value (.signed .i32 1)))
      (.signed .i32 (Int.ofNat (nodes + 1))) written :=
    evaluatesNatI32Add (readLocal nodesAfter) ⟨1, rfl⟩ (by omega)
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
