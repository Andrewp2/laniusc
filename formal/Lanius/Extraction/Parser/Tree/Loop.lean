import Lanius.Extraction.Parser.Tree.Entry
import Lanius.Extraction.Parser.Tree.Derivation

namespace Lanius.Extraction.ParserTreeSource

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Compiler.Parser Lanius.Extraction.ParserTreeLayout Lanius.Extraction.ParserTreeDerivation

private theorem local_read {id : Lanius.VarId} (found : before.local? id = some value) :
    Evaluates program before (.local id) value before :=
  ⟨1, evalLocal_of_local 0 program before id value found⟩

/-- The precise smaller-state obligation shared by the loop and caller proof.
    This is a proposition to construct by induction, not a new trust axiom. -/
def TreeRuntime.EarlierCalls (runtime : TreeRuntime) (checked : CheckedVisit program)
    (rootId : Nat) (allTrees : List Lanius.Compiler.Parser.ParseTree) (frame : State → Prop)
    (grammar : IndexedGrammar) (workspace : LogicalWorkspace) : Prop :=
  ∀ (processed : List Lanius.Compiler.Parser.ParseTree) (pending : List Child)
    (childId : Nat) (child : Lanius.Compiler.Parser.ParseTree) (state : State),
    runtime.At processed (.state childId :: pending) state → frame state → childId < rootId →
    ChildExpansion grammar workspace (.state childId) child → child ∈ allTrees →
    runtime.nextWord (processed ++ [child]) ≤ runtime.records.length →
    runtime.nextNode (processed ++ [child]) ≤ runtime.offsets.length →
    Nonempty (runtime.ChildCall checked state processed (.state childId :: pending) child)

/-- Execute the entire sibling loop using the exact selected workspace trees.
    The ambient frame carries immutable call inputs and workspace resources.
    The recursive callback is the smaller-state induction hypothesis: it is
    used only for an earlier resident child from this parent's selected tree.
    Whole-call correctness must construct that callback, not assume it. -/
theorem TreeRuntime.At.loop {runtime : TreeRuntime} (checked : CheckedVisit program)
    (allTrees : List Lanius.Compiler.Parser.ParseTree) (frame : State → Prop)
    (retain : ∀ {processed pending state after}, runtime.At processed pending state →
      frame state → CellEffect runtime.writes state after → frame after)
    (rootId : Nat)
    (recursive : runtime.EarlierCalls checked rootId allTrees frame grammar workspace)
    (held : runtime.At processed pending before) (framed : frame before)
    (matched : ChildrenExpansion grammar workspace pending remaining)
    (selected : processed ++ remaining = allTrees)
    (earlier : ∀ childId, .state childId ∈ pending → childId < rootId)
    (wordsFit : runtime.nextWord allTrees ≤ runtime.records.length)
    (nodesFit : runtime.nextNode allTrees ≤ runtime.offsets.length) :
    ∃ after, Executes program.core before
        (.whileLoop (.binary .notEqual (.local 15) (.local 12)) (childIteration checked.symbols)) .next after ∧
      runtime.At allTrees [] after ∧ frame after ∧ CellEffect runtime.writes before after := by
  cases matched with
  | nil =>
    have equal : processed.length = runtime.parent.dot := by simpa using held.count
    have finished : processed = allTrees := by simpa using selected
    refine ⟨before, ?_, finished ▸ held, framed, CellEffect.refl held.wellFormed⟩
    apply executesWhileFalse
    exact evaluatesEagerBinary (by decide) (by decide)
      (local_read (Assertion.localPointsTo_local _ _ _ _ held.cursorOwned)) (local_read held.countLocal)
      (by simp [evalBinaryValue, scalarEqual, equal])
  | @cons reference child references remaining head tail =>
    have different : processed.length ≠ runtime.parent.dot := by
      have count := held.count
      simp only [List.length_cons] at count
      omega
    have condition : Evaluates program.core before (.binary .notEqual (.local 15) (.local 12)) (.boolean true) before :=
      evaluatesEagerBinary (by decide) (by decide)
        (local_read (Assertion.localPointsTo_local _ _ _ _ held.cursorOwned)) (local_read held.countLocal)
        (by simp [evalBinaryValue, scalarEqual]; exact fun equal => different (Int.ofNat.inj equal))
    have selectedNext : (processed ++ [child]) ++ remaining = allTrees := by
      simpa only [List.append_assoc, List.singleton_append] using selected
    have sizes := forest_prefix_lengths (processed ++ [child]) remaining runtime.nodeBase
      (runtime.wordBase + 4 + runtime.parent.dot * 3)
    rw [selectedNext] at sizes
    have childWordsFit : runtime.nextWord (processed ++ [child]) ≤ runtime.records.length := by
      unfold TreeRuntime.nextWord TreeRuntime.done at wordsFit ⊢
      omega
    have childNodesFit : runtime.nextNode (processed ++ [child]) ≤ runtime.offsets.length := by
      unfold TreeRuntime.nextNode TreeRuntime.done at nodesFit ⊢
      omega
    have step : ∃ middle, Executes program.core before (childIteration checked.symbols) .next middle ∧
        runtime.At (processed ++ [child]) references middle ∧ CellEffect runtime.writes before middle := by
      cases head with
      | token =>
        obtain ⟨middle, executed, next, effect⟩ := held.token_step checked
        refine ⟨middle, executed, next, effect.weaken ?_⟩
        intro cell member
        simp_all [TreeRuntime.writes, CellSet.singleton]
      | state found productionBound complete enough computed =>
        have member : _ ∈ allTrees := selected ▸ (List.mem_append.mpr (Or.inr (List.mem_cons_self ..)))
        obtain ⟨nested⟩ := recursive processed references _ _ before held framed
          (earlier _ (List.mem_cons_self ..)) (.state found productionBound complete enough computed)
          member childWordsFit childNodesFit
        exact held.state_step checked _ ⟨_, _, _, _, _, rfl⟩ nested childWordsFit childNodesFit
    obtain ⟨middle, step, next, stepEffect⟩ := step
    have nextFrame := retain held framed stepEffect
    have restEarlier : ∀ childId, .state childId ∈ references → childId < rootId :=
      fun childId member => earlier childId (List.mem_cons_of_mem reference member)
    obtain ⟨after, loop, complete, afterFrame, loopEffect⟩ :=
      TreeRuntime.At.loop checked allTrees frame retain rootId recursive next nextFrame tail selectedNext
        restEarlier wordsFit nodesFit
    exact ⟨after, executesWhileTrue condition step loop, complete, afterFrame, stepEffect.trans loopEffect⟩
termination_by pending.length

/-- Complete the actual post-reader source component: initialize all cursors,
    expand every selected sibling, write the parent offset, return the exact
    tree layout, and hide private cursor writes. Only the smaller-state calls
    and an immutable ambient frame remain for the whole-call induction. -/
theorem TreeRuntime.Entry.children {runtime : TreeRuntime}
    (entry : runtime.Entry pending before) (checked : CheckedVisit program)
    (allTrees : List Lanius.Compiler.Parser.ParseTree) (nonterminal rootId : Nat)
    (frame : State → Prop)
    (retain : ∀ {processed pending state after}, (runtime.freshCursors before).At processed pending state →
      frame state → CellEffect (runtime.freshCursors before).writes state after → frame after)
    (recursive : (runtime.freshCursors before).EarlierCalls checked rootId allTrees frame grammar workspace)
    (framed : frame (runtime.initialState before))
    (matched : ChildrenExpansion grammar workspace pending allTrees)
    (earlier : ∀ childId, .state childId ∈ pending → childId < rootId)
    (wordsFit : runtime.nextWord allTrees ≤ runtime.records.length)
    (nodesRoom : runtime.nextNode allTrees < runtime.offsets.length) :
    let tree := Lanius.Compiler.Parser.ParseTree.nonterminal runtime.parent.production nonterminal
      runtime.parent.origin runtime.parent.position allTrees
    let layout := treeFrom runtime.nodeBase runtime.wordBase tree
    ∃ after, Executes program.core before (visitChildren checked.symbols)
        (.returned (some (resultValue checked.symbols.resultType 0
          (Int.ofNat (runtime.nodeBase + layout.offsets.length))
          (Int.ofNat (runtime.wordBase + layout.words.length))))) after ∧
      after.cellEntry? runtime.recordsCell = some {
        id := runtime.recordsCell, value := some (.array (signedI32Values
          (runtime.records.take runtime.wordBase ++ layout.words ++
            runtime.records.drop (runtime.wordBase + layout.words.length)))) } ∧
      after.cellEntry? runtime.offsetsCell = some {
        id := runtime.offsetsCell, value := some (.array (signedI32Values
          (runtime.offsets.take runtime.nodeBase ++ layout.offsets.map Int.ofNat ++
            runtime.offsets.drop (runtime.nodeBase + layout.offsets.length)))) } ∧
      CellEffect runtime.outputs before after := by
  dsimp only
  let layout := treeFrom runtime.nodeBase runtime.wordBase
    (.nonterminal runtime.parent.production nonterminal runtime.parent.origin runtime.parent.position allTrees)
  let post := fun cells : List Cell =>
    ({ before with cells := cells } : State).cellEntry? runtime.recordsCell = some {
      id := runtime.recordsCell, value := some (.array (signedI32Values
        (runtime.records.take runtime.wordBase ++ layout.words ++
          runtime.records.drop (runtime.wordBase + layout.words.length)))) } ∧
    ({ before with cells := cells } : State).cellEntry? runtime.offsetsCell = some {
      id := runtime.offsetsCell, value := some (.array (signedI32Values
        (runtime.offsets.take runtime.nodeBase ++ layout.offsets.map Int.ofNat ++
          runtime.offsets.drop (runtime.nodeBase + layout.offsets.length)))) }
  obtain ⟨after, executed, satisfied, effect⟩ := entry.with_cursors checked post (by
    intro initialized
    have freshWordsFit : (runtime.freshCursors before).nextWord allTrees ≤ (runtime.freshCursors before).records.length :=
      wordsFit
    have freshNodesRoom : (runtime.freshCursors before).nextNode allTrees < (runtime.freshCursors before).offsets.length :=
      nodesRoom
    obtain ⟨expanded, loop, complete, _, loopEffect⟩ := TreeRuntime.At.loop checked allTrees frame retain rootId recursive
      initialized framed matched (by rfl) earlier freshWordsFit (Nat.le_of_lt freshNodesRoom)
    obtain ⟨completed, exited, records, offsets, exitEffect⟩ := complete.finish checked freshNodesRoom nonterminal
    have exitSubset : CellSet.Subset (CellSet.singleton (runtime.freshCursors before).offsetsCell)
        (runtime.freshCursors before).writes := by
      intro cell member
      simp_all [TreeRuntime.writes, CellSet.singleton]
    refine ⟨completed, executesSequence loop exited, ?_, loopEffect.trans (exitEffect.weaken exitSubset)⟩
    exact ⟨records, offsets⟩)
  exact ⟨after, executed, satisfied.1, satisfied.2, effect⟩

end Lanius.Extraction.ParserTreeSource
