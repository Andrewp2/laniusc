import Lanius.Extraction.Parser.Tree.Outcome

namespace Lanius.Extraction.ParserTreeSource

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Compiler.Parser Lanius.Extraction.ParserTreeLayout Lanius.Extraction.ParserTreeDerivation

/-- Complete the post-reader component for either outcome. All cursor scopes
    close on early return as well as success. No capacity for the complete tree
    is assumed, including the final parent-offset slot. -/
theorem TreeRuntime.Entry.children_outcome {runtime : TreeRuntime}
    (entry : runtime.Entry pending before) (checked : CheckedVisit program)
    (allTrees : List Lanius.Compiler.Parser.ParseTree) (nonterminal rootId : Nat)
    (frame : State → Prop)
    (retain : ∀ {processed pending state after}, (runtime.freshCursors before).At processed pending state →
      frame state → CellEffect (runtime.freshCursors before).writes state after → frame after)
    (recursive : (runtime.freshCursors before).EarlierSteps checked rootId allTrees frame grammar workspace)
    (framed : frame (runtime.initialState before))
    (matched : ChildrenExpansion grammar workspace pending allTrees)
    (earlier : ∀ childId, .state childId ∈ pending → childId < rootId) :
    let tree := Lanius.Compiler.Parser.ParseTree.nonterminal runtime.parent.production nonterminal
      runtime.parent.origin runtime.parent.position allTrees
    ∃ code nodes words after, Executes program.core before (visitChildren checked.symbols)
        (.returned (some (resultValue checked.symbols.resultType code (Int.ofNat nodes) (Int.ofNat words)))) after ∧
      runtime.Result tree code nodes words after.cells ∧ CellEffect runtime.outputs before after := by
  dsimp only
  let tree := Lanius.Compiler.Parser.ParseTree.nonterminal runtime.parent.production nonterminal
    runtime.parent.origin runtime.parent.position allTrees
  let serialized := treeFrom runtime.nodeBase runtime.wordBase tree
  let fresh := runtime.freshCursors before
  have treeCount : allTrees.length = runtime.parent.dot := matched.length.symm.trans entry.count
  have wordsEqual : runtime.wordBase + serialized.words.length = fresh.nextWord allTrees := by
    simp only [serialized, tree, treeFrom, List.length_append, child_words_length, forest_roots_length,
      recordHeader, List.length_cons, List.length_nil, treeCount, TreeRuntime.nextWord,
      TreeRuntime.done, fresh, TreeRuntime.freshCursors, Nat.add_assoc]
    omega
  have nodesEqual : runtime.nodeBase + serialized.offsets.length = fresh.nextNode allTrees + 1 := by
    simp only [serialized, tree, treeFrom, List.length_append, List.length_cons, List.length_nil,
      treeCount, TreeRuntime.nextNode, TreeRuntime.done, fresh, TreeRuntime.freshCursors, Nat.add_assoc]
  obtain ⟨completion, expanded, loop, outcome, loopEffect⟩ := entry.initialize.loop_outcome checked allTrees frame retain
    rootId recursive framed matched rfl earlier
  have finished : ∃ code nodes words completed,
      Executes program.core (runtime.initialState before)
        (.sequence (.whileLoop (.binary .notEqual (.local 15) (.local 12)) (childIteration checked.symbols))
          (visitExit checked.symbols))
        (.returned (some (resultValue checked.symbols.resultType code (Int.ofNat nodes) (Int.ofNat words)))) completed ∧
      runtime.Result tree code nodes words completed.cells ∧
      CellEffect fresh.writes (runtime.initialState before) completed := by
    rcases outcome with ⟨rfl, complete, _⟩ | failed
    · by_cases room : fresh.nextNode allTrees < runtime.offsets.length
      · obtain ⟨completed, exited, records, offsets, effect⟩ := complete.finish checked room nonterminal
        have nodesBound : runtime.nodeBase + serialized.offsets.length ≤ runtime.offsets.length := by omega
        have wordsBound : runtime.wordBase + serialized.words.length ≤ runtime.records.length :=
          wordsEqual ▸ complete.recordsFit
        refine ⟨0, runtime.nodeBase + serialized.offsets.length, runtime.wordBase + serialized.words.length,
          completed, executesSequence loop exited, ?_, loopEffect.trans (effect.weaken ?_)⟩
        · exact ⟨Or.inl rfl, Nat.le_add_right _ _, nodesBound, Nat.le_add_right _ _, wordsBound,
            fun _ => ⟨rfl, rfl, records, offsets⟩⟩
        · intro cell member
          exact Or.inr (Or.inl member)
      · obtain ⟨completed, exited, effect, completedWF⟩ := checked.finish_full complete.wellFormed complete.capacityLocal
          (Assertion.localPointsTo_local _ _ _ _ complete.wordsOwned)
          (Assertion.localPointsTo_local _ _ _ _ complete.nodesOwned)
          (by change (runtime.offsets.length : Int) ≤ (fresh.nextNode allTrees : Int); omega)
        refine ⟨2, fresh.nextNode allTrees, fresh.nextWord allTrees, completed,
          executesSequence loop exited, ?_, loopEffect.trans
            ((CellEffect.ofModifiesOnly effect completedWF).weaken CellSet.empty_subset)⟩
        exact TreeRuntime.Result.failure runtime tree 2 _ _ _ (Or.inl rfl)
          (by simp [TreeRuntime.nextNode, fresh, TreeRuntime.freshCursors]) complete.offsetsFit
          (by simp [TreeRuntime.nextWord, fresh, TreeRuntime.freshCursors, Nat.add_assoc]) complete.recordsFit
    · obtain ⟨code, nodes, words, failedCode, nodesStart, nodesBound, wordsStart, wordsBound, rfl⟩ := failed
      exact ⟨code, nodes, words, expanded, executesSequenceReturned loop,
        TreeRuntime.Result.failure runtime tree code nodes words expanded.cells failedCode nodesStart nodesBound wordsStart wordsBound,
        loopEffect⟩
  obtain ⟨code, nodes, words, completed, executed, result, effect⟩ := finished
  obtain ⟨after, children, result, effect⟩ := entry.with_cursors checked (runtime.Result tree code nodes words)
    (fun _ => ⟨completed, executed, result, effect⟩)
  exact ⟨code, nodes, words, after, children, result, effect⟩

end Lanius.Extraction.ParserTreeSource
