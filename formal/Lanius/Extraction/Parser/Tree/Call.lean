import Lanius.Extraction.Parser.Tree.Caller

namespace Lanius.Extraction.ParserTreeSource

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.Compiler.Parser Lanius.Extraction.ParserRecognize Lanius.Extraction.ParserDerivation
open Lanius.Extraction.ParserTreeLayout Lanius.Extraction.ParserTreeDerivation

/-- Execute the actual checked `visit` call for a resident state. The selected
    semantic tree determines the exact depth and storage requirements. Recursive
    calls are proved by strictly decreasing workspace state IDs, not assumed.
    Arguments may have effects; the storage contract starts after their ordinary
    evaluation. Private parameter and cursor cells are allocated by the call. -/
theorem CheckedVisit.call_state {symbols : Core.Relocation.Symbols}
    (checked : CheckedVisit program) (linked : LinkedReader checked.reader allowed symbols)
    (inverseType : Lanius.TypeId → Lanius.TypeId)
    (inverse : Function.RightInverse inverseType symbols.typeId)
    (sound : WorkspaceBackpointersSound grammar tokens workspace)
    (runtime : TreeRuntime) (stateId : Nat)
    (found : workspace.state? stateId = some runtime.parent)
    (productionBound : runtime.parent.production < grammar.productionCount)
    (treeEnough : stateId < treeFuel)
    (materialized : materializeStatePrefix? grammar workspace treeFuel stateId = some trees)
    (wellFormed : StateWellFormed afterArguments)
    (artifact : RecognizerWorkspaceArtifact layout workspace workspaceValues workspaceCell afterArguments)
    (layoutTokens : layout.tokenCount = tokens.length)
    (records : afterArguments.cellEntry? runtime.recordsCell = some {
      id := runtime.recordsCell, value := some (.array (signedI32Values runtime.records)) })
    (offsets : afterArguments.cellEntry? runtime.offsetsCell = some {
      id := runtime.offsetsCell, value := some (.array (signedI32Values runtime.offsets)) })
    (recordsSeparate : workspaceCell ≠ runtime.recordsCell)
    (offsetsSeparate : workspaceCell ≠ runtime.offsetsCell)
    (buffersDistinct : runtime.recordsCell ≠ runtime.offsetsCell)
    (recordsBound : runtime.records.length ≤ 2147483647)
    (offsetsBound : runtime.offsets.length ≤ 2147483647)
    (depthBound : depth ≤ 2147483647)
    (depthEnough : forestDepth trees + 1 ≤ depth)
    (wordsFit : runtime.wordBase + (treeFrom runtime.nodeBase runtime.wordBase
      (.nonterminal runtime.parent.production (grammar.productionAt ⟨runtime.parent.production, productionBound⟩).lhs
        runtime.parent.origin runtime.parent.position trees)).words.length ≤ runtime.records.length)
    (nodesFit : runtime.nodeBase + (treeFrom runtime.nodeBase runtime.wordBase
      (.nonterminal runtime.parent.production (grammar.productionAt ⟨runtime.parent.production, productionBound⟩).lhs
        runtime.parent.origin runtime.parent.position trees)).offsets.length ≤ runtime.offsets.length)
    (argumentsResult : ArgumentsEvaluateTo program.core before arguments
      (runtime.visitValues workspaceValues workspaceCell layout.tokenCount workspace.states.length stateId depth)
      afterArguments) :
    let tree := Lanius.Compiler.Parser.ParseTree.nonterminal runtime.parent.production
      (grammar.productionAt ⟨runtime.parent.production, productionBound⟩).lhs
      runtime.parent.origin runtime.parent.position trees
    let serialized := treeFrom runtime.nodeBase runtime.wordBase tree
    ∃ after, Evaluates program.core before (.call checked.symbols.visit arguments)
        (resultValue checked.symbols.resultType 0
          (Int.ofNat (runtime.nodeBase + serialized.offsets.length))
          (Int.ofNat (runtime.wordBase + serialized.words.length))) after ∧
      after.cellEntry? runtime.recordsCell = some {
        id := runtime.recordsCell, value := some (.array (signedI32Values
          (runtime.records.take runtime.wordBase ++ serialized.words ++
            runtime.records.drop (runtime.wordBase + serialized.words.length)))) } ∧
      after.cellEntry? runtime.offsetsCell = some {
        id := runtime.offsetsCell, value := some (.array (signedI32Values
          (runtime.offsets.take runtime.nodeBase ++ serialized.offsets.map Int.ofNat ++
            runtime.offsets.drop (runtime.nodeBase + serialized.offsets.length)))) } ∧
      RecognizerWorkspaceArtifact layout workspace workspaceValues workspaceCell after ∧
      CellEffect runtime.outputs afterArguments after := by
  dsimp only
  obtain ⟨references, readReferences, referenceCount⟩ :=
    sound.derivationChildren_complete found (Nat.lt_succ_self stateId)
  have treeCount := (children_match sound found (Nat.lt_succ_self stateId)
    treeEnough readReferences materialized).length.symm.trans referenceCount
  have wordCount : (treeFrom runtime.nodeBase runtime.wordBase
      (.nonterminal runtime.parent.production (grammar.productionAt ⟨runtime.parent.production, productionBound⟩).lhs
        runtime.parent.origin runtime.parent.position trees)).words.length =
      4 + runtime.parent.dot * 3 + (runtime.done trees).words.length := by
    simp only [treeFrom, List.length_append, recordHeader, List.length_cons, List.length_nil,
      child_words_length, forest_roots_length, treeCount, TreeRuntime.done]
  have nodeCount : (treeFrom runtime.nodeBase runtime.wordBase
      (.nonterminal runtime.parent.production (grammar.productionAt ⟨runtime.parent.production, productionBound⟩).lhs
        runtime.parent.origin runtime.parent.position trees)).offsets.length =
      (runtime.done trees).offsets.length + 1 := by
    simp only [treeFrom, List.length_append, List.length_singleton, treeCount, TreeRuntime.done]
  rw [wordCount] at wordsFit
  rw [nodeCount] at nodesFit
  have positive : 0 < depth := by omega
  have room : runtime.nodeBase < runtime.offsets.length := by omega
  have input := runtime.enter (stateId := stateId) wellFormed artifact records offsets
    recordsSeparate offsetsSeparate buffersDistinct depthBound
  obtain ⟨children, afterRead, count, _, readChildren, matched, earlier, reader, entry, framed, readEffect⟩ :=
    input.read checked linked inverseType inverse sound found treeEnough materialized layoutTokens
      recordsBound (by omega) (Nat.le_of_lt room) offsetsBound
  let counted := afterRead.bindLocal 12 (.signed .i32 (Int.ofNat runtime.parent.dot))
  let fresh := runtime.freshCursors counted
  let frame := fresh.Frame layout workspace workspaceValues workspaceCell depth
  have recursive : fresh.EarlierCalls checked stateId trees frame grammar workspace := by
    intro processed pending childId child state held current smaller expansion member childWordsFit childNodesFit
    cases expansion with
    | @state _ childState childFuel childTrees childFound childProductionBound complete enough computed =>
      let child := Lanius.Compiler.Parser.ParseTree.nonterminal childState.production
        (grammar.productionAt ⟨childState.production, childProductionBound⟩).lhs
        childState.origin childState.position childTrees
      let nested : TreeRuntime := { fresh with
        parent := childState
        nodeBase := fresh.nextNode processed
        wordBase := fresh.nextWord processed
        records := fresh.recordValues processed (.state childId :: pending)
        offsets := fresh.offsetValues processed }
      have doneNext : fresh.done (processed ++ [child]) = appendTree (fresh.done processed)
          (treeFrom (fresh.nextNode processed) (fresh.nextWord processed) child) :=
        forest_snoc processed child _ _
      have wordsNext : fresh.nextWord (processed ++ [child]) = fresh.nextWord processed +
          (treeFrom (fresh.nextNode processed) (fresh.nextWord processed) child).words.length := by
        simp only [TreeRuntime.nextWord, doneNext, appendTree, List.length_append, Nat.add_assoc]
      have nodesNext : fresh.nextNode (processed ++ [child]) = fresh.nextNode processed +
          (treeFrom (fresh.nextNode processed) (fresh.nextWord processed) child).offsets.length := by
        simp only [TreeRuntime.nextNode, doneNext, appendTree, List.length_append, Nat.add_assoc]
      change fresh.nextWord (processed ++ [child]) ≤ fresh.records.length at childWordsFit
      change fresh.nextNode (processed ++ [child]) ≤ fresh.offsets.length at childNodesFit
      rw [wordsNext] at childWordsFit
      rw [nodesNext] at childNodesFit
      have childDepth := forest_depth_member member
      have entered := held.bind_slot
      have current : frame state := current
      have slotFrame := current.bind 16 (by decide)
        (.signed .i32 (Int.ofNat (fresh.wordBase + 4 + processed.length * 3)))
      have evaluated := held.recursive_arguments program.core current.workspaceLocal current.workspaceLengthLocal
        current.tokensLocal current.statesLocal current.capacityLocal current.depthLocal positive depthBound
      have childArguments : ArgumentsEvaluateTo program.core (fresh.slotState processed state)
          [.local 0, .local 1, .local 2, .local 3, childPayload, .local 5, .local 6, .local 7, .local 8,
            .local 14, .local 13, .binary .subtract (.local 11) (.value (.signed .i32 1))]
          (nested.visitValues workspaceValues workspaceCell layout.tokenCount workspace.states.length childId (depth - 1))
          (fresh.slotState processed state) := by
        simpa only [TreeRuntime.visitValues, nested, held.record_length, held.offset_length] using evaluated
      obtain ⟨after, called, writtenRecords, writtenOffsets, _, effect⟩ :=
        checked.call_state linked inverseType inverse sound nested childId childFound childProductionBound enough computed
          entered.wellFormed slotFrame.artifact layoutTokens entered.recordsBacking entered.offsetsBacking
          current.recordsSeparate current.offsetsSeparate held.buffersDistinct
          (by simpa only [nested, held.record_length] using held.recordsBound)
          (by simpa only [nested, held.offset_length] using held.offsetsBound)
          (by omega) (by
            change forestDepth childTrees + 1 ≤ depth - 1
            change treeDepth child ≤ forestDepth trees at childDepth
            dsimp only [child, treeDepth] at childDepth
            omega)
          (by simpa only [nested, held.record_length, child] using childWordsFit)
          (by simpa only [nested, held.offset_length, child] using childNodesFit) childArguments
      refine ⟨⟨after, ?_, ?_, ?_, effect⟩⟩
      · change Evaluates program.core (fresh.slotState processed state) (recursiveCall checked.symbols) _ after at called
        simpa only [nested, wordsNext, nodesNext, child] using called
      · simpa only [nested, wordsNext, child] using writtenRecords
      · simpa only [nested, nodesNext, child] using writtenOffsets
  obtain ⟨completed, childExecution, writtenRecords, writtenOffsets, childEffect⟩ :=
    entry.children checked trees (grammar.productionAt ⟨runtime.parent.production, productionBound⟩).lhs stateId frame
      (fun held current effect => current.preserved held effect) recursive framed.initialize matched earlier
      (by unfold TreeRuntime.nextWord; omega) (by unfold TreeRuntime.nextNode; omega)
  obtain ⟨body, bodyEffect⟩ := input.body checked positive room reader readEffect childExecution childEffect
  have identity : checked.source.function.id = checked.source.source.id := by
    simpa [Program.function?] using List.find?_some checked.source.found
  have functionFound : program.core.function? checked.source.function.id = some checked.source.function := by
    rw [identity]
    exact checked.source.found
  have callEffect := CellEffect.closeCall afterArguments _ wellFormed bodyEffect
  refine ⟨restoreLocals afterArguments (restoreLocals afterRead completed), ?_, writtenRecords, writtenOffsets,
    ?_, callEffect⟩
  · rw [checked.identities.1]
    exact evaluatesCallReturned argumentsResult functionFound (checked.bind_parameters runtime) checked.bodyExact body
  · exact ⟨artifact.workspaceLength, artifact.workspaceEncoded,
      callEffect.preserves_entry wellFormed artifact.workspaceBacking
        (fun written => written.elim recordsSeparate offsetsSeparate)⟩
termination_by stateId

end Lanius.Extraction.ParserTreeSource
