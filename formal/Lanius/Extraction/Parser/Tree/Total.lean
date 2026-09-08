import Lanius.Extraction.Parser.Tree.Complete

namespace Lanius.Extraction.ParserTreeSource

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.Compiler.Parser Lanius.Extraction.ParserRecognize Lanius.Extraction.ParserDerivation
open Lanius.Extraction.ParserTreeLayout Lanius.Extraction.ParserTreeDerivation

/-- The checked materializer call terminates on a valid retained state even
    when its output space or recursive depth is insufficient. Success gives
    exact serialization; failure returns the actual bounded cursors and may
    leave partial output only in the two designated buffers. No child execution,
    successful or failed, is an assumption of this theorem. -/
theorem CheckedVisit.call_bounded {symbols : Core.Relocation.Symbols}
    (checked : CheckedVisit program) (linked : LinkedReader checked.reader allowed symbols)
    (inverseType : Lanius.TypeId → Lanius.TypeId) (inverse : Function.RightInverse inverseType symbols.typeId)
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
    (recordsSeparate : workspaceCell ≠ runtime.recordsCell) (offsetsSeparate : workspaceCell ≠ runtime.offsetsCell)
    (buffersDistinct : runtime.recordsCell ≠ runtime.offsetsCell)
    (recordsBound : runtime.records.length ≤ 2147483647) (offsetsBound : runtime.offsets.length ≤ 2147483647)
    (wordsStart : runtime.wordBase ≤ runtime.records.length) (nodesStart : runtime.nodeBase ≤ runtime.offsets.length)
    (depthBound : depth ≤ 2147483647)
    (argumentsResult : ArgumentsEvaluateTo program.core before arguments
      (runtime.visitValues workspaceValues workspaceCell layout.tokenCount workspace.states.length stateId depth)
      afterArguments) :
    let tree := Lanius.Compiler.Parser.ParseTree.nonterminal runtime.parent.production
      (grammar.productionAt ⟨runtime.parent.production, productionBound⟩).lhs runtime.parent.origin runtime.parent.position trees
    ∃ code nodes words after, Evaluates program.core before (.call checked.symbols.visit arguments)
        (resultValue checked.symbols.resultType code (Int.ofNat nodes) (Int.ofNat words)) after ∧
      runtime.Result tree code nodes words after.cells ∧ CellEffect runtime.outputs afterArguments after := by
  dsimp only
  let tree := Lanius.Compiler.Parser.ParseTree.nonterminal runtime.parent.production
    (grammar.productionAt ⟨runtime.parent.production, productionBound⟩).lhs runtime.parent.origin runtime.parent.position trees
  by_cases early : depth = 0 ∨ runtime.offsets.length ≤ runtime.nodeBase
  · obtain ⟨after, call, effect, afterWF⟩ := checked.failure_call wellFormed argumentsResult
      (by
        change Int.ofNat depth ≤ 0 ∨ Int.ofNat runtime.offsets.length ≤ Int.ofNat runtime.nodeBase
        rcases early with exhausted | full
        · exact Or.inl (by rw [exhausted]; decide)
        · exact Or.inr (Int.ofNat_le.mpr full))
    rw [← checked.identities.1] at call
    refine ⟨_, runtime.nodeBase, runtime.wordBase, after, call, ?_,
      (CellEffect.ofModifiesOnly effect afterWF).weaken CellSet.empty_subset⟩
    exact TreeRuntime.Result.failure runtime tree _ _ _ _ (by split <;> simp) (Nat.le_refl _) nodesStart
      (Nat.le_refl _) wordsStart
  have positive : 0 < depth := by omega
  have room : runtime.nodeBase < runtime.offsets.length := by omega
  by_cases headerFits : runtime.wordBase + 4 + runtime.parent.dot * 3 ≤ runtime.records.length
  · have input := runtime.enter (stateId := stateId) wellFormed artifact records offsets recordsSeparate offsetsSeparate
      buffersDistinct depthBound
    obtain ⟨children, afterRead, _, _, _, matched, earlier, reader, entry, framed, readEffect⟩ :=
      input.read checked linked inverseType inverse sound found treeEnough materialized layoutTokens
        recordsBound headerFits nodesStart offsetsBound
    let counted := afterRead.bindLocal 12 (.signed .i32 (Int.ofNat runtime.parent.dot))
    let fresh := runtime.freshCursors counted
    let frame := fresh.Frame layout workspace workspaceValues workspaceCell depth
    have recursive : fresh.EarlierSteps checked stateId trees frame grammar workspace := by
      intro processed pending childId child state held current smaller expansion member
      cases expansion with
      | @state _ childState childFuel childTrees childFound childProductionBound complete enough computed =>
        let child := Lanius.Compiler.Parser.ParseTree.nonterminal childState.production
          (grammar.productionAt ⟨childState.production, childProductionBound⟩).lhs childState.origin childState.position childTrees
        let nested : TreeRuntime := { fresh with
          parent := childState
          nodeBase := fresh.nextNode processed
          wordBase := fresh.nextWord processed
          records := fresh.recordValues processed (.state childId :: pending)
          offsets := fresh.offsetValues processed }
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
        obtain ⟨code, nodes, words, afterCall, called, result, callEffect⟩ :=
          checked.call_bounded linked inverseType inverse sound nested childId childFound childProductionBound enough computed
            entered.wellFormed slotFrame.artifact layoutTokens entered.recordsBacking entered.offsetsBacking
            current.recordsSeparate current.offsetsSeparate held.buffersDistinct
            (by simpa only [nested, held.record_length] using held.recordsBound)
            (by simpa only [nested, held.offset_length] using held.offsetsBound)
            (by simpa only [nested, held.record_length] using held.recordsFit)
            (by simpa only [nested, held.offset_length] using held.offsetsFit)
            (by omega) childArguments
        change Evaluates program.core (fresh.slotState processed state) (recursiveCall checked.symbols)
          (resultValue checked.symbols.resultType code (Int.ofNat nodes) (Int.ofNat words)) afterCall at called
        obtain ⟨allowed, nodeLower, nodeUpper, wordLower, wordUpper, success⟩ := result
        have nodesBound : nodes ≤ fresh.offsets.length := by
          simpa only [nested, held.offset_length] using nodeUpper
        have wordsBound : words ≤ fresh.records.length := by
          simpa only [nested, held.record_length] using wordUpper
        by_cases ok : code = 0
        · obtain ⟨nodesEqual, wordsEqual, writtenRecords, writtenOffsets⟩ := success ok
          have doneNext : fresh.done (processed ++ [child]) = appendTree (fresh.done processed)
              (treeFrom (fresh.nextNode processed) (fresh.nextWord processed) child) :=
            forest_snoc processed child _ _
          have wordsNext : fresh.nextWord (processed ++ [child]) = fresh.nextWord processed +
              (treeFrom (fresh.nextNode processed) (fresh.nextWord processed) child).words.length := by
            simp only [TreeRuntime.nextWord, doneNext, appendTree, List.length_append, Nat.add_assoc]
          have nodesNext : fresh.nextNode (processed ++ [child]) = fresh.nextNode processed +
              (treeFrom (fresh.nextNode processed) (fresh.nextWord processed) child).offsets.length := by
            simp only [TreeRuntime.nextNode, doneNext, appendTree, List.length_append, Nat.add_assoc]
          have nodesDone : nodes = fresh.nextNode (processed ++ [child]) := nodesEqual.trans nodesNext.symm
          have wordsDone : words = fresh.nextWord (processed ++ [child]) := wordsEqual.trans wordsNext.symm
          have nestedCall : fresh.ChildCall checked state processed (.state childId :: pending) child := by
            refine ⟨afterCall, ?_, ?_, ?_, callEffect⟩
            · simpa only [ok, nodesDone, wordsDone] using called
            · simpa only [nested, wordsDone, child, State.cellEntry?] using writtenRecords
            · simpa only [nested, nodesDone, child, State.cellEntry?] using writtenOffsets
          obtain ⟨after, executed, next, effect⟩ := held.state_step checked child ⟨_, _, _, _, _, rfl⟩ nestedCall
            (wordsDone ▸ wordsBound) (nodesDone ▸ nodesBound)
          exact ⟨.next, after, executed, Or.inl ⟨rfl, next⟩, effect⟩
        · obtain ⟨after, executed, _, effect⟩ := held.state_failure checked called callEffect ok
          refine ⟨_, after, executed, Or.inr ?_, effect.weaken ?_⟩
          · refine ⟨code, nodes, words, allowed.resolve_left ok, ?_, nodesBound, ?_, wordsBound, rfl⟩
            · change fresh.nextNode processed ≤ nodes at nodeLower
              unfold TreeRuntime.nextNode at nodeLower
              omega
            · change fresh.nextWord processed ≤ words at wordLower
              unfold TreeRuntime.nextWord at wordLower
              omega
          · intro cell written
            exact written.elim Or.inl (fun h => Or.inr (Or.inl h))
    obtain ⟨code, nodes, words, completed, childExecution, result, childEffect⟩ := entry.children_outcome checked trees
      (grammar.productionAt ⟨runtime.parent.production, productionBound⟩).lhs stateId frame
      (fun held current effect => current.preserved held effect) recursive framed.initialize matched earlier
    obtain ⟨body, bodyEffect⟩ := input.body checked positive room reader readEffect childExecution childEffect
    have identity : checked.source.function.id = checked.source.source.id := by
      simpa [Program.function?] using List.find?_some checked.source.found
    have functionFound : program.core.function? checked.source.function.id = some checked.source.function := by
      rw [identity]
      exact checked.source.found
    refine ⟨code, nodes, words, restoreLocals afterArguments (restoreLocals afterRead completed), ?_, result,
      CellEffect.closeCall afterArguments _ wellFormed bodyEffect⟩
    rw [checked.identities.1]
    exact evaluatesCallReturned argumentsResult functionFound (checked.bind_parameters runtime) checked.bodyExact body
  · obtain ⟨after, call, effect⟩ := checked.record_full_call linked inverseType inverse sound runtime stateId found
      wellFormed artifact records offsets recordsSeparate offsetsSeparate buffersDistinct depthBound positive room
      wordsStart recordsBound (by omega) argumentsResult
    exact ⟨2, runtime.nodeBase, runtime.wordBase, after, call,
      TreeRuntime.Result.failure runtime tree 2 _ _ _ (Or.inl rfl) (Nat.le_refl _) nodesStart (Nat.le_refl _) wordsStart,
      effect.weaken CellSet.empty_subset⟩
termination_by stateId

end Lanius.Extraction.ParserTreeSource
