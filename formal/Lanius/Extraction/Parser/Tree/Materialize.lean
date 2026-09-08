import Lanius.Extraction.Parser.Tree.Call
import Lanius.Extraction.Parser.Tree.Total
import Lanius.Extraction.Parser.Tree.MaterializeSource

namespace Lanius.Extraction.ParserTreeSource

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.Compiler.Parser Lanius.Extraction.ParserRecognize Lanius.Extraction.ParserDerivation
open Lanius.Extraction.ParserTreeLayout Lanius.FunctionalView.Core

private theorem local_read {id : Lanius.VarId} (found : before.local? id = some value) :
    Evaluates program before (.local id) value before :=
  ⟨1, evalLocal_of_local 0 program before id value found⟩

/-- Recover the exact selected tree from the successful recognizer result.
    No independent materialization computation is supplied by its consumer. -/
private theorem selected_root_tree (root : RecognizerRootResult grammar tokens workspace parsed) :
    ∃ productionBound : root.root.production < grammar.productionCount,
      ∃ children, materializeStatePrefix? grammar workspace (workspace.states.length + 1) root.rootState = some children ∧
        root.stored.tree = .nonterminal root.root.production
          (grammar.productionAt ⟨root.root.production, productionBound⟩).lhs
          root.root.origin root.root.position children := by
  have computed := root.stored.rootComputed
  simp only [materializeRoot?, root.found, bind, Option.bind] at computed
  split at computed
  · rename_i productionBound
    split at computed
    · cases computed
    · cases childrenEq : materializeStatePrefix? grammar workspace (workspace.states.length + 1) root.rootState with
      | none => simp only [childrenEq] at computed; cases computed
      | some children =>
        simp only [childrenEq, Option.some.injEq] at computed
        exact ⟨productionBound, children, rfl, computed.symm⟩
  · cases computed

def materializeValues (parsedType : Lanius.TypeId) (workspaceValues records offsets : List Int)
    (workspaceCell recordsCell offsetsCell : CellId) (tokenCount stateCount rootState depth : Nat) : List Value :=
  [.structure parsedType [.signed .i32 0, .signed .i32 (Int.ofNat stateCount),
      .signed .i32 (Int.ofNat rootState), .signed .i32 0],
    .slice (.scalar (.signed .i32)) workspaceCell [] 0 workspaceValues.length,
    .signed .i32 (Int.ofNat workspaceValues.length), .signed .i32 (Int.ofNat tokenCount),
    .slice (.scalar (.signed .i32)) recordsCell [] 0 records.length,
    .signed .i32 (Int.ofNat records.length),
    .slice (.scalar (.signed .i32)) offsetsCell [] 0 offsets.length,
    .signed .i32 (Int.ofNat offsets.length), .signed .i32 (Int.ofNat depth)]

def materializeRuntime (parent : EarleyState) (records offsets : List Int)
    (recordsCell offsetsCell : CellId) : TreeRuntime :=
  ⟨parent, 0, 0, records, offsets, recordsCell, offsetsCell, 0, 0, 0⟩

/-- Shared public-call plumbing: derive the guard, parser accessors, and all
    visit arguments once. The two public contracts below discharge `run` with
    the complete success or bounded-outcome theorem, respectively. -/
private theorem CheckedMaterialize.with_visit {visit : CheckedVisit program}
    (checked : CheckedMaterialize visit)
    (root : RecognizerRootResult grammar tokens workspace parsed)
    (wellFormed : StateWellFormed afterArguments)
    (artifact : RecognizerWorkspaceArtifact layout workspace workspaceValues workspaceCell afterArguments)
    (records : afterArguments.cellEntry? recordsCell = some {
      id := recordsCell, value := some (.array (signedI32Values recordValues)) })
    (offsets : afterArguments.cellEntry? offsetsCell = some {
      id := offsetsCell, value := some (.array (signedI32Values offsetValues)) })
    (recordsSeparate : workspaceCell ≠ recordsCell) (offsetsSeparate : workspaceCell ≠ offsetsCell)
    (post : Int → Nat → Nat → List Cell → Prop)
    (run : ∀ {caller exprs current}, StateWellFormed current →
      RecognizerWorkspaceArtifact layout workspace workspaceValues workspaceCell current →
      current.cellEntry? recordsCell = some {
        id := recordsCell, value := some (.array (signedI32Values recordValues)) } →
      current.cellEntry? offsetsCell = some {
        id := offsetsCell, value := some (.array (signedI32Values offsetValues)) } →
      ArgumentsEvaluateTo program.core caller exprs
        ((materializeRuntime root.root recordValues offsetValues recordsCell offsetsCell).visitValues
          workspaceValues workspaceCell layout.tokenCount workspace.states.length root.rootState depth) current →
      ∃ code nodes words after, Evaluates program.core caller (.call visit.symbols.visit exprs)
          (resultValue visit.symbols.resultType code (Int.ofNat nodes) (Int.ofNat words)) after ∧
        post code nodes words after.cells ∧
        CellEffect (CellSet.union (CellSet.singleton recordsCell) (CellSet.singleton offsetsCell)) current after)
    (argumentsResult : ArgumentsEvaluateTo program.core before arguments
      (materializeValues checked.parsedType workspaceValues recordValues offsetValues workspaceCell recordsCell offsetsCell
        layout.tokenCount workspace.states.length root.rootState depth) afterArguments) :
    ∃ code nodes words after, Evaluates program.core before (.call checked.source.function.id arguments)
        (resultValue visit.symbols.resultType code (Int.ofNat nodes) (Int.ofNat words)) after ∧
      post code nodes words after.cells ∧
      RecognizerWorkspaceArtifact layout workspace workspaceValues workspaceCell after ∧
      CellEffect (CellSet.union (CellSet.singleton recordsCell) (CellSet.singleton offsetsCell)) afterArguments after := by
  let values := materializeValues checked.parsedType workspaceValues recordValues offsetValues workspaceCell recordsCell
    offsetsCell layout.tokenCount workspace.states.length root.rootState depth
  let bindings := parameterBindings (fun index : Fin 9 => values.get index)
  let callee := enterCall afterArguments bindings
  have calleeWF : StateWellFormed callee := enterCall_preserves_wellFormed wellFormed
  have parameters (index : Fin 9) : callee.local? index.val = some (values.get index) :=
    enterCall_parameterBindings_matches wellFormed index
  have preserve {cell : CellId} {value : Value}
      (found : afterArguments.cellEntry? cell = some { id := cell, value := some value }) :
      callee.cellEntry? cell = some { id := cell, value := some value } :=
    ((enterCall_effect afterArguments bindings).oldCells cell
      (StateWellFormed.cell_lt_next_of_entry wellFormed found) (by simp [CellSet.empty])).trans found
  obtain ⟨afterStatus, statusCall, statusEffect⟩ := checked.status.call calleeWF
    (.cons (local_read (parameters ⟨0, by decide⟩)) (.nil _ _)) rfl
  have afterStatusParameters (index : Fin 9) : afterStatus.local? index.val = some (values.get index) :=
    statusEffect.preserves_local calleeWF (parameters index) (by simp [CellSet.empty])
  have statusFalse : Evaluates program.core callee
      (.binary .notEqual (.call checked.status.source.function.id [.local 0]) (.constant checked.parseSuccess))
      (.boolean false) afterStatus :=
    evaluatesEagerBinary (by decide) (by decide) statusCall (evaluatesConstant checked.success) rfl
  have recordsFalse := nonnegative_check_false (program := program.core)
    (afterStatusParameters ⟨5, by decide⟩) (Int.natCast_nonneg recordValues.length)
  have offsetsFalse := nonnegative_check_false (program := program.core)
    (afterStatusParameters ⟨7, by decide⟩) (Int.natCast_nonneg offsetValues.length)
  have guardFalse := evaluatesLogicalOrFalse (evaluatesLogicalOrFalse statusFalse recordsFalse) offsetsFalse
  obtain ⟨afterCount, countCall, countEffect⟩ := checked.stateCount.call statusEffect.wellFormed
    (.cons (local_read (afterStatusParameters ⟨0, by decide⟩)) (.nil _ _)) rfl
  have countParameters (index : Fin 9) : afterCount.local? index.val = some (values.get index) :=
    countEffect.preserves_local statusEffect.wellFormed (afterStatusParameters index) (by simp [CellSet.empty])
  obtain ⟨afterRoot, rootCall, rootEffect⟩ := checked.rootState.call countEffect.wellFormed
    (.cons (local_read (countParameters ⟨0, by decide⟩)) (.nil _ _)) rfl
  have callsEffect := statusEffect.trans (countEffect.trans rootEffect)
  have rootParameters (index : Fin 9) : afterRoot.local? index.val = some (values.get index) :=
    rootEffect.preserves_local countEffect.wellFormed (countParameters index) (by simp [CellSet.empty])
  let runtime := materializeRuntime root.root recordValues offsetValues recordsCell offsetsCell
  have visitArguments : ArgumentsEvaluateTo program.core afterStatus
      [.local 1, .local 2, .local 3, .call checked.stateCount.source.function.id [.local 0],
        .call checked.rootState.source.function.id [.local 0], .local 4, .local 5, .local 6, .local 7,
        .value (.signed .i32 0), .value (.signed .i32 0), .local 8]
      (runtime.visitValues workspaceValues workspaceCell layout.tokenCount workspace.states.length root.rootState depth)
      afterRoot := by
    refine .cons (local_read (afterStatusParameters ⟨1, by decide⟩)) ?_
    refine .cons (local_read (afterStatusParameters ⟨2, by decide⟩)) ?_
    refine .cons (local_read (afterStatusParameters ⟨3, by decide⟩)) ?_
    refine .cons countCall (.cons rootCall ?_)
    refine .cons (local_read (rootParameters ⟨4, by decide⟩)) ?_
    refine .cons (local_read (rootParameters ⟨5, by decide⟩)) ?_
    refine .cons (local_read (rootParameters ⟨6, by decide⟩)) ?_
    refine .cons (local_read (rootParameters ⟨7, by decide⟩)) ?_
    exact .cons ⟨1, rfl⟩ (.cons ⟨1, rfl⟩ (.cons (local_read (rootParameters ⟨8, by decide⟩)) (.nil _ _)))
  have currentArtifact : RecognizerWorkspaceArtifact layout workspace workspaceValues workspaceCell afterRoot :=
    ⟨artifact.workspaceLength, artifact.workspaceEncoded,
      callsEffect.empty_preserves_entry calleeWF (preserve artifact.workspaceBacking)⟩
  obtain ⟨code, nodes, words, completed, visited, result, visitEffect⟩ :=
    run callsEffect.wellFormed currentArtifact
      (callsEffect.empty_preserves_entry calleeWF (preserve records))
      (callsEffect.empty_preserves_entry calleeWF (preserve offsets))
      visitArguments
  have retained : RecognizerWorkspaceArtifact layout workspace workspaceValues workspaceCell completed :=
    ⟨currentArtifact.workspaceLength, currentArtifact.workspaceEncoded,
      visitEffect.preserves_entry callsEffect.wellFormed currentArtifact.workspaceBacking
        (fun written => written.elim recordsSeparate offsetsSeparate)⟩
  have body : Executes program.core callee
      (materializeBody visit.symbols checked.status.source.function.id checked.stateCount.source.function.id
        checked.rootState.source.function.id checked.parseSuccess)
      (.returned (some (resultValue visit.symbols.resultType code (Int.ofNat nodes) (Int.ofNat words)))) completed := by
    apply executesSequence (executesIfFalse guardFalse (executesSkip _ _))
    apply executesSequenceReturned
    apply executesReturnValue
    exact visited
  have identity : checked.source.function.id = checked.source.source.id := by
    simpa [Program.function?] using List.find?_some checked.source.found
  have functionFound : program.core.function? checked.source.function.id = some checked.source.function := by
    rw [identity]
    exact checked.source.found
  have parametersBound : bindParameters checked.source.function.parameters values = some bindings := by
    rw [checked.signature.1]
    rfl
  have bodyEffect := (callsEffect.weaken (by intro cell member; exact False.elim member)).trans visitEffect
  exact ⟨code, nodes, words, restoreLocals afterArguments completed,
    evaluatesCallReturned argumentsResult functionFound parametersBound checked.body body, result,
    retained.transfer_cells rfl, CellEffect.closeCall afterArguments bindings wellFormed bodyEffect⟩

/-- The public materializer consumes the successful recognizer's selected root
    and returns that tree's exact serialized buffers. Parser projections and the
    entire recursive visit are executed here, not premises of the contract. -/
theorem CheckedMaterialize.call {symbols : Core.Relocation.Symbols} {visit : CheckedVisit program}
    (checked : CheckedMaterialize visit) (linked : LinkedReader visit.reader allowed symbols)
    (inverseType : Lanius.TypeId → Lanius.TypeId) (inverse : Function.RightInverse inverseType symbols.typeId)
    (root : RecognizerRootResult grammar tokens workspace parsed)
    (wellFormed : StateWellFormed afterArguments)
    (artifact : RecognizerWorkspaceArtifact layout workspace workspaceValues workspaceCell afterArguments)
    (layoutTokens : layout.tokenCount = tokens.length)
    (records : afterArguments.cellEntry? recordsCell = some {
      id := recordsCell, value := some (.array (signedI32Values recordValues)) })
    (offsets : afterArguments.cellEntry? offsetsCell = some {
      id := offsetsCell, value := some (.array (signedI32Values offsetValues)) })
    (recordsSeparate : workspaceCell ≠ recordsCell) (offsetsSeparate : workspaceCell ≠ offsetsCell)
    (buffersDistinct : recordsCell ≠ offsetsCell)
    (recordsBound : recordValues.length ≤ 2147483647) (offsetsBound : offsetValues.length ≤ 2147483647)
    (depthBound : depth ≤ 2147483647) (depthEnough : treeDepth root.stored.tree ≤ depth)
    (wordsFit : (treeFrom 0 0 root.stored.tree).words.length ≤ recordValues.length)
    (nodesFit : (treeFrom 0 0 root.stored.tree).offsets.length ≤ offsetValues.length)
    (argumentsResult : ArgumentsEvaluateTo program.core before arguments
      (materializeValues checked.parsedType workspaceValues recordValues offsetValues workspaceCell recordsCell offsetsCell
        layout.tokenCount workspace.states.length root.rootState depth) afterArguments) :
    let serialized := treeFrom 0 0 root.stored.tree
    ∃ after, Evaluates program.core before (.call checked.source.function.id arguments)
        (resultValue visit.symbols.resultType 0 (Int.ofNat serialized.offsets.length) (Int.ofNat serialized.words.length)) after ∧
      after.cellEntry? recordsCell = some { id := recordsCell, value := some (.array (signedI32Values
        (serialized.words ++ recordValues.drop serialized.words.length))) } ∧
      after.cellEntry? offsetsCell = some { id := offsetsCell, value := some (.array (signedI32Values
        (serialized.offsets.map Int.ofNat ++ offsetValues.drop serialized.offsets.length))) } ∧
      RecognizerWorkspaceArtifact layout workspace workspaceValues workspaceCell after ∧
      CellEffect (CellSet.union (CellSet.singleton recordsCell) (CellSet.singleton offsetsCell)) afterArguments after := by
  dsimp only
  let runtime := materializeRuntime root.root recordValues offsetValues recordsCell offsetsCell
  let serialized := treeFrom 0 0 root.stored.tree
  let post (code : Int) (nodes words : Nat) (cells : List Cell) : Prop :=
    code = 0 ∧ nodes = serialized.offsets.length ∧ words = serialized.words.length ∧
      ({ cells := cells } : State).cellEntry? recordsCell = some {
        id := recordsCell, value := some (.array (signedI32Values
          (serialized.words ++ recordValues.drop serialized.words.length))) } ∧
      ({ cells := cells } : State).cellEntry? offsetsCell = some {
        id := offsetsCell, value := some (.array (signedI32Values
          (serialized.offsets.map Int.ofNat ++ offsetValues.drop serialized.offsets.length))) }
  obtain ⟨code, nodes, words, after, called, result, retained, effect⟩ :=
    checked.with_visit root wellFormed artifact records offsets recordsSeparate offsetsSeparate post
      (fun currentWF currentArtifact currentRecords currentOffsets evaluated => by
        obtain ⟨productionBound, children, computed, selected⟩ := selected_root_tree root
        obtain ⟨completed, visited, writtenRecords, writtenOffsets, _, visitEffect⟩ :=
          visit.call_state linked inverseType inverse root.stored.backpointersSound runtime root.rootState root.found
            productionBound (Nat.lt_succ_of_lt root.root_lt_stateCount) computed currentWF currentArtifact layoutTokens
            currentRecords currentOffsets recordsSeparate offsetsSeparate buffersDistinct recordsBound offsetsBound depthBound
            (by simpa only [selected, treeDepth] using depthEnough)
            (by simpa only [selected, runtime, materializeRuntime, Nat.zero_add] using wordsFit)
            (by simpa only [selected, runtime, materializeRuntime, Nat.zero_add] using nodesFit) evaluated
        refine ⟨0, serialized.offsets.length, serialized.words.length, completed, ?_, ⟨rfl, rfl, rfl, ?_, ?_⟩, visitEffect⟩
        · simpa only [runtime, materializeRuntime, serialized, Nat.zero_add, ← selected] using visited
        · simpa only [runtime, materializeRuntime, serialized, ← selected, Nat.zero_add,
            List.take_zero, List.nil_append, State.cellEntry?] using writtenRecords
        · simpa only [runtime, materializeRuntime, serialized, ← selected, Nat.zero_add,
            List.take_zero, List.nil_append, State.cellEntry?] using writtenOffsets) argumentsResult
  obtain ⟨rfl, rfl, rfl, writtenRecords, writtenOffsets⟩ := result
  exact ⟨after, called, writtenRecords, writtenOffsets, retained, effect⟩


/-- The actual public materializer terminates on a valid selected workspace,
    even when depth or output capacity is insufficient. A zero status certifies
    the exact tree; a resource failure carries bounded partial-output counters.
    The entire recursive execution and all wrapper calls are derived here. -/
theorem CheckedMaterialize.call_bounded {symbols : Core.Relocation.Symbols} {visit : CheckedVisit program}
    (checked : CheckedMaterialize visit) (linked : LinkedReader visit.reader allowed symbols)
    (inverseType : Lanius.TypeId → Lanius.TypeId) (inverse : Function.RightInverse inverseType symbols.typeId)
    (root : RecognizerRootResult grammar tokens workspace parsed)
    (wellFormed : StateWellFormed afterArguments)
    (artifact : RecognizerWorkspaceArtifact layout workspace workspaceValues workspaceCell afterArguments)
    (layoutTokens : layout.tokenCount = tokens.length)
    (records : afterArguments.cellEntry? recordsCell = some {
      id := recordsCell, value := some (.array (signedI32Values recordValues)) })
    (offsets : afterArguments.cellEntry? offsetsCell = some {
      id := offsetsCell, value := some (.array (signedI32Values offsetValues)) })
    (recordsSeparate : workspaceCell ≠ recordsCell) (offsetsSeparate : workspaceCell ≠ offsetsCell)
    (buffersDistinct : recordsCell ≠ offsetsCell)
    (recordsBound : recordValues.length ≤ 2147483647) (offsetsBound : offsetValues.length ≤ 2147483647)
    (depthBound : depth ≤ 2147483647)
    (argumentsResult : ArgumentsEvaluateTo program.core before arguments
      (materializeValues checked.parsedType workspaceValues recordValues offsetValues workspaceCell recordsCell offsetsCell
        layout.tokenCount workspace.states.length root.rootState depth) afterArguments) :
    ∃ code nodes words after, Evaluates program.core before (.call checked.source.function.id arguments)
        (resultValue visit.symbols.resultType code (Int.ofNat nodes) (Int.ofNat words)) after ∧
      (materializeRuntime root.root recordValues offsetValues recordsCell offsetsCell).Result
        root.stored.tree code nodes words after.cells ∧
      RecognizerWorkspaceArtifact layout workspace workspaceValues workspaceCell after ∧
      CellEffect (CellSet.union (CellSet.singleton recordsCell) (CellSet.singleton offsetsCell)) afterArguments after := by
  let runtime := materializeRuntime root.root recordValues offsetValues recordsCell offsetsCell
  apply checked.with_visit root wellFormed artifact records offsets recordsSeparate offsetsSeparate
    (runtime.Result root.stored.tree) ?_ argumentsResult
  intro caller exprs current currentWF currentArtifact currentRecords currentOffsets evaluated
  obtain ⟨productionBound, children, computed, selected⟩ := selected_root_tree root
  obtain ⟨code, nodes, words, after, called, result, effect⟩ :=
    visit.call_bounded linked inverseType inverse root.stored.backpointersSound runtime root.rootState root.found
      productionBound (Nat.lt_succ_of_lt root.root_lt_stateCount) computed currentWF currentArtifact layoutTokens
      currentRecords currentOffsets recordsSeparate offsetsSeparate buffersDistinct recordsBound offsetsBound
      (Nat.zero_le _) (Nat.zero_le _) depthBound evaluated
  exact ⟨code, nodes, words, after, called, selected ▸ result, effect⟩

/-- A rejected parser result or negative supplied output length is rejected by
    the public guard before any workspace/buffer access or recursive visit.
    Unused arguments need no storage or semantic-workspace assumptions. -/
theorem CheckedMaterialize.reject {visit : CheckedVisit program}
    (checked : CheckedMaterialize visit)
    (wellFormed : StateWellFormed afterArguments)
    (statusField : parsedFields[0]? = some (.signed .i32 parserStatus))
    (invalid : parserStatus ≠ 0 ∨ recordsLength < 0 ∨ offsetsLength < 0)
    (argumentsResult : ArgumentsEvaluateTo program.core before arguments
      [.structure checked.parsedType parsedFields, workspaceValue, workspaceLength, tokenCount,
        recordsValue, .signed .i32 recordsLength, offsetsValue, .signed .i32 offsetsLength, depthValue] afterArguments) :
    ∃ after, Evaluates program.core before (.call checked.source.function.id arguments)
        (resultValue visit.symbols.resultType 1 0 0) after ∧
      CellEffect CellSet.empty afterArguments after := by
  let values : List Value := [.structure checked.parsedType parsedFields, workspaceValue, workspaceLength, tokenCount,
    recordsValue, .signed .i32 recordsLength, offsetsValue, .signed .i32 offsetsLength, depthValue]
  let bindings := parameterBindings (fun index : Fin 9 => values.get index)
  let callee := enterCall afterArguments bindings
  have calleeWF : StateWellFormed callee := enterCall_preserves_wellFormed wellFormed
  have parameters (index : Fin 9) : callee.local? index.val = some (values.get index) :=
    enterCall_parameterBindings_matches wellFormed index
  obtain ⟨afterStatus, statusCall, statusEffect⟩ := checked.status.call calleeWF
    (.cons (local_read (parameters ⟨0, by decide⟩)) (.nil _ _)) statusField
  have afterParameters (index : Fin 9) : afterStatus.local? index.val = some (values.get index) :=
    statusEffect.preserves_local calleeWF (parameters index) (by simp [CellSet.empty])
  have negativeOne : Evaluates program.core afterStatus (.unary .negate (.value (.signed .i32 1)))
      (.signed .i32 (-1)) afterStatus := by
    apply evaluatesUnary
      (show Evaluates program.core afterStatus (.value (.signed .i32 1)) (.signed .i32 1) afterStatus from ⟨1, rfl⟩)
    simp [evalUnaryValue, wrapSigned, signedModulus, signedSignBit, Core.SignedIntTy.bits]
  have negativeCheck {id : Lanius.VarId} {value : Int}
      (found : afterStatus.local? id = some (.signed .i32 value)) (negative : value < 0) :
      Evaluates program.core afterStatus
        (.binary .lessEqual (.local id) (.unary .negate (.value (.signed .i32 1)))) (.boolean true) afterStatus := by
    apply evaluatesEagerBinary (by decide) (by decide) (local_read found) negativeOne
    simp [evalBinaryValue, evalSignedBinary, show value ≤ -1 by omega]
  have guardTrue : Evaluates program.core callee
      (.binary .logicalOr
        (.binary .logicalOr
          (.binary .notEqual (.call checked.status.source.function.id [.local 0]) (.constant checked.parseSuccess))
          (.binary .lessEqual (.local 5) (.unary .negate (.value (.signed .i32 1)))))
        (.binary .lessEqual (.local 7) (.unary .negate (.value (.signed .i32 1)))))
      (.boolean true) afterStatus := by
    by_cases rejected : parserStatus ≠ 0
    · apply evaluatesLogicalOrTrue
      apply evaluatesLogicalOrTrue
      exact evaluatesEagerBinary (by decide) (by decide) statusCall (evaluatesConstant checked.success)
        (by simp [evalBinaryValue, scalarEqual, rejected])
    · have accepted : parserStatus = 0 := by omega
      have statusFalse : Evaluates program.core callee
          (.binary .notEqual (.call checked.status.source.function.id [.local 0]) (.constant checked.parseSuccess))
          (.boolean false) afterStatus :=
        evaluatesEagerBinary (by decide) (by decide) statusCall (evaluatesConstant checked.success)
          (by simp [evalBinaryValue, scalarEqual, accepted])
      by_cases short : recordsLength < 0
      · exact evaluatesLogicalOrTrue (evaluatesLogicalOrFalse statusFalse
          (negativeCheck (afterParameters ⟨5, by decide⟩) short))
      · exact evaluatesLogicalOrFalse (evaluatesLogicalOrFalse statusFalse
          (nonnegative_check_false (afterParameters ⟨5, by decide⟩) (by omega)))
          (negativeCheck (afterParameters ⟨7, by decide⟩) (by omega))
  have zero : Evaluates program.core afterStatus (.value (.signed .i32 0)) (.signed .i32 0) afterStatus := ⟨1, rfl⟩
  obtain ⟨completed, returned, constructorEffect, completedWF⟩ := visit.constructor_call statusEffect.wellFormed
    (.cons (evaluatesConstant visit.statuses.2.1) (.cons zero (.cons zero (.nil _ _))))
  have body : Executes program.core callee
      (materializeBody visit.symbols checked.status.source.function.id checked.stateCount.source.function.id
        checked.rootState.source.function.id checked.parseSuccess)
      (.returned (some (resultValue visit.symbols.resultType 1 0 0))) completed := by
    exact executesSequenceReturned (executesIfTrue guardTrue (executesSequenceReturned (executesReturnValue returned)))
  have identity : checked.source.function.id = checked.source.source.id := by
    simpa [Program.function?] using List.find?_some checked.source.found
  have functionFound : program.core.function? checked.source.function.id = some checked.source.function := by
    rw [identity]
    exact checked.source.found
  have parametersBound : bindParameters checked.source.function.parameters values = some bindings := by
    rw [checked.signature.1]
    rfl
  exact ⟨restoreLocals afterArguments completed,
    evaluatesCallReturned argumentsResult functionFound parametersBound checked.body body,
    CellEffect.closeCall afterArguments bindings wellFormed
      (statusEffect.trans (CellEffect.ofModifiesOnly constructorEffect completedWF))⟩

end Lanius.Extraction.ParserTreeSource
