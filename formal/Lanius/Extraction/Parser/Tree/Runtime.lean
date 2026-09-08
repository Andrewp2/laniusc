import Lanius.Extraction.Parser.Tree.Cursor
import Lanius.Extraction.Parser.Tree.Iteration

namespace Lanius.Extraction.ParserTreeSource

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Compiler.Parser Lanius.Extraction.ParserTreeLayout

/-- Fixed storage and private cursor cells for one invocation of `visit`.
    Initial arrays retain the caller's exact unused prefix and suffix. -/
structure TreeRuntime where
  parent : EarleyState
  nodeBase : Nat
  wordBase : Nat
  records : List Int
  offsets : List Int
  recordsCell : CellId
  offsetsCell : CellId
  wordsCell : CellId
  nodesCell : CellId
  cursorCell : CellId

def TreeRuntime.done (runtime : TreeRuntime) (trees : List Lanius.Compiler.Parser.ParseTree) : Layout (List Child) :=
  forestFrom runtime.nodeBase (runtime.wordBase + 4 + runtime.parent.dot * 3) trees

def TreeRuntime.nextNode (runtime : TreeRuntime) (trees : List Lanius.Compiler.Parser.ParseTree) : Nat :=
  runtime.nodeBase + (runtime.done trees).offsets.length

def TreeRuntime.nextWord (runtime : TreeRuntime) (trees : List Lanius.Compiler.Parser.ParseTree) : Nat :=
  runtime.wordBase + 4 + runtime.parent.dot * 3 + (runtime.done trees).words.length

def TreeRuntime.recordValues (runtime : TreeRuntime) (trees : List Lanius.Compiler.Parser.ParseTree)
    (pending : List Child) : List Int :=
  runtime.records.take runtime.wordBase ++ partialWords runtime.parent (runtime.done trees) pending ++
    runtime.records.drop (runtime.nextWord trees)

def TreeRuntime.offsetValues (runtime : TreeRuntime) (trees : List Lanius.Compiler.Parser.ParseTree) : List Int :=
  runtime.offsets.take runtime.nodeBase ++ (runtime.done trees).offsets.map Int.ofNat ++
    runtime.offsets.drop (runtime.nextNode trees)

/-- A successful loop state. Only the already-processed children have dense
    node references; the pending suffix still contains reader references.
    Semantic correspondence to the chosen workspace children is retained by
    the outer induction, not replaced by this physical storage invariant. -/
structure TreeRuntime.At (runtime : TreeRuntime) (trees : List Lanius.Compiler.Parser.ParseTree)
    (pending : List Child) (state : State) : Prop where
  wellFormed : StateWellFormed state
  count : trees.length + pending.length = runtime.parent.dot
  recordsFit : runtime.nextWord trees ≤ runtime.records.length
  offsetsFit : runtime.nextNode trees ≤ runtime.offsets.length
  recordsBound : runtime.records.length ≤ 2147483647
  offsetsBound : runtime.offsets.length ≤ 2147483647
  parentLocal : state.local? 10 = some (.signed .i32 (Int.ofNat runtime.wordBase))
  countLocal : state.local? 12 = some (.signed .i32 (Int.ofNat runtime.parent.dot))
  recordsLocal : state.local? 5 = some (.slice (.scalar (.signed .i32)) runtime.recordsCell [] 0 runtime.records.length)
  offsetsLocal : state.local? 7 = some (.slice (.scalar (.signed .i32)) runtime.offsetsCell [] 0 runtime.offsets.length)
  capacityLocal : state.local? 8 = some (.signed .i32 (Int.ofNat runtime.offsets.length))
  wordsOwned : (Assertion.localPointsTo 13 runtime.wordsCell
    (some (.signed .i32 (Int.ofNat (runtime.nextWord trees))))).holds state
  nodesOwned : (Assertion.localPointsTo 14 runtime.nodesCell
    (some (.signed .i32 (Int.ofNat (runtime.nextNode trees))))).holds state
  cursorOwned : (Assertion.localPointsTo 15 runtime.cursorCell
    (some (.signed .i32 (Int.ofNat trees.length)))).holds state
  recordsBacking : state.cellEntry? runtime.recordsCell = some {
    id := runtime.recordsCell, value := some (.array (signedI32Values (runtime.recordValues trees pending))) }
  offsetsBacking : state.cellEntry? runtime.offsetsCell = some {
    id := runtime.offsetsCell, value := some (.array (signedI32Values (runtime.offsetValues trees))) }
  buffersDistinct : runtime.recordsCell ≠ runtime.offsetsCell
  cursorsDistinct : runtime.wordsCell ≠ runtime.nodesCell ∧ runtime.wordsCell ≠ runtime.cursorCell ∧
    runtime.nodesCell ≠ runtime.cursorCell
  fixedSeparate : ∀ id : Lanius.VarId, id < 13 → ∀ cell,
    state.cellId? id = some cell → cell ≠ runtime.wordsCell ∧ cell ≠ runtime.nodesCell ∧ cell ≠ runtime.cursorCell

theorem TreeRuntime.At.record_length {runtime : TreeRuntime} (held : runtime.At trees pending state) :
    (runtime.recordValues trees pending).length = runtime.records.length := by
  have prefixBound : runtime.wordBase ≤ runtime.records.length := by
    have fit := held.recordsFit
    unfold TreeRuntime.nextWord at fit
    omega
  have length := partialWords_length runtime.parent (runtime.done trees) pending
    (by simpa only [TreeRuntime.done, forest_roots_length] using held.count)
  simp only [TreeRuntime.recordValues, List.length_append, List.length_take,
    Nat.min_eq_left prefixBound, List.length_drop, length]
  have fit := held.recordsFit
  unfold TreeRuntime.nextWord at fit ⊢
  omega

theorem TreeRuntime.At.offset_length {runtime : TreeRuntime} (held : runtime.At trees pending state) :
    (runtime.offsetValues trees).length = runtime.offsets.length := by
  have prefixBound : runtime.nodeBase ≤ runtime.offsets.length := by
    have fit := held.offsetsFit
    unfold TreeRuntime.nextNode at fit
    omega
  simp only [TreeRuntime.offsetValues, List.length_append, List.length_take,
    Nat.min_eq_left prefixBound, List.length_drop, List.length_map]
  have fit := held.offsetsFit
  unfold TreeRuntime.nextNode at fit ⊢
  omega

theorem TreeRuntime.At.pending_head {runtime : TreeRuntime}
    (held : runtime.At trees (child :: pending) state) :
    let values := runtime.recordValues trees (child :: pending)
    let slot := runtime.wordBase + 4 + trees.length * 3
    values[slot]? = some (childTag child) ∧
      values[slot + 1]? = some (Lanius.Compiler.Parser.childPayload child) ∧
      values[slot + 2]? = some (childKind child) := by
  have prefixBound : runtime.wordBase ≤ runtime.records.length := by
    have fit := held.recordsFit
    unfold TreeRuntime.nextWord at fit
    omega
  simpa only [TreeRuntime.recordValues, List.length_take, Nat.min_eq_left prefixBound,
    TreeRuntime.done, forest_roots_length] using
    partialWords_head (runtime.records.take runtime.wordBase) (runtime.records.drop (runtime.nextWord trees))
      runtime.parent (runtime.done trees) child pending

/-- Execute the actual terminal iteration and retain the complete loop
    invariant, including untouched offset storage and fixed caller locals. -/
theorem TreeRuntime.At.token_step {runtime : TreeRuntime}
    (held : runtime.At trees (.token token kind :: pending) before)
    (checked : CheckedVisit program) :
    ∃ after, Executes program.core before (childIteration checked.symbols) .next after ∧
      runtime.At (trees ++ [.terminal token kind]) pending after ∧
      CellEffect (CellSet.singleton runtime.cursorCell) before after := by
  have recordsLocal := held.recordsLocal
  rw [← held.record_length] at recordsLocal
  obtain ⟨after, executed, cursor, records, effect⟩ := checked.token_iteration held.wellFormed
    held.parentLocal held.cursorOwned recordsLocal held.recordsBacking held.pending_head.1
    (held.record_length ▸ held.recordsBound)
  have doneNext : runtime.done (trees ++ [.terminal token kind]) =
      appendTree (runtime.done trees) (treeFrom (runtime.nextNode trees) (runtime.nextWord trees) (.terminal token kind)) :=
    forest_snoc trees (.terminal token kind) _ _
  have nodesNext : runtime.nextNode (trees ++ [.terminal token kind]) = runtime.nextNode trees := by
    simp only [TreeRuntime.nextNode, doneNext, appendTree, treeFrom, List.append_nil]
  have wordsNext : runtime.nextWord (trees ++ [.terminal token kind]) = runtime.nextWord trees := by
    simp only [TreeRuntime.nextWord, doneNext, appendTree, treeFrom, List.append_nil]
  have recordsNext : runtime.recordValues (trees ++ [.terminal token kind]) pending =
      runtime.recordValues trees (.token token kind :: pending) := by
    simp only [TreeRuntime.recordValues, doneNext, wordsNext, partialWords_token]
  have offsetsNext : runtime.offsetValues (trees ++ [.terminal token kind]) = runtime.offsetValues trees := by
    simp only [TreeRuntime.offsetValues, doneNext, nodesNext, appendTree, treeFrom, List.append_nil]
  have preserve {id : Lanius.VarId} {value : Value}
      (member : id < 13) (foundLocal : before.local? id = some value) :
      after.local? id = some value :=
    effect.preserves_local held.wellFormed foundLocal (fun cell found => (held.fixedSeparate id member cell found).2.2)
  have cursorLocal := Assertion.localPointsTo_local _ _ _ _ held.cursorOwned
  have offsetsDifferent : runtime.offsetsCell ≠ runtime.cursorCell :=
    Ne.symm (local_cell_ne_of_distinct_value cursorLocal held.offsetsBacking
      (by intro impossible; cases impossible) held.cursorOwned.1)
  refine ⟨after, executed, ?_, effect⟩
  refine ⟨effect.wellFormed, ?_, wordsNext ▸ held.recordsFit, nodesNext ▸ held.offsetsFit,
    held.recordsBound, held.offsetsBound, preserve (by decide) held.parentLocal,
    preserve (by decide) held.countLocal, preserve (by decide) held.recordsLocal,
    preserve (by decide) held.offsetsLocal, preserve (by decide) held.capacityLocal,
    wordsNext ▸ effect.preserves_localPointsTo held.wellFormed held.wordsOwned held.cursorsDistinct.2.1,
    nodesNext ▸ effect.preserves_localPointsTo held.wellFormed held.nodesOwned held.cursorsDistinct.2.2,
    ?_, recordsNext ▸ records, offsetsNext ▸ effect.preserves_entry held.wellFormed held.offsetsBacking offsetsDifferent,
    held.buffersDistinct, held.cursorsDistinct, ?_⟩
  · have count := held.count
    simp only [List.length_append, List.length_cons, List.length_nil] at count ⊢
    omega
  · simpa only [List.length_append, List.length_cons, List.length_nil] using cursor
  · intro id member cell found
    apply held.fixedSeparate id member cell
    simpa only [State.cellId?, effect.locals] using found

private theorem extend_region (leading original added : List Int) (start : Nat)
    (length : leading.length = start) :
    (leading ++ original.drop start).take start ++ added ++
        (leading ++ original.drop start).drop (start + added.length) =
      leading ++ added ++ original.drop (start + added.length) := by
  rw [← length]
  simp [List.drop_append, List.drop_drop]

/-- The recursive child's exact append followed by the source payload store
    establishes the next parent's record invariant. The unused original suffix
    is retained, not replaced by an existential array with the right prefix. -/
theorem TreeRuntime.At.child_records {runtime : TreeRuntime}
    (held : runtime.At trees (.state oldId :: pending) before)
    (child : Lanius.Compiler.Parser.ParseTree)
    (nonterminal : ∃ production nt start finish children,
      child = .nonterminal production nt start finish children) :
    let nested := treeFrom (runtime.nextNode trees) (runtime.nextWord trees) child
    ((runtime.recordValues trees (.state oldId :: pending)).take (runtime.nextWord trees) ++ nested.words ++
      (runtime.recordValues trees (.state oldId :: pending)).drop (runtime.nextWord trees + nested.words.length)).set
        (runtime.wordBase + 4 + trees.length * 3 + 1)
        (Int.ofNat (runtime.nextNode (trees ++ [child]) - 1)) =
      runtime.recordValues (trees ++ [child]) pending := by
  dsimp only
  have doneNext : runtime.done (trees ++ [child]) =
      appendTree (runtime.done trees) (treeFrom (runtime.nextNode trees) (runtime.nextWord trees) child) :=
    forest_snoc trees child _ _
  have wordsNext : runtime.nextWord (trees ++ [child]) =
      runtime.nextWord trees + (treeFrom (runtime.nextNode trees) (runtime.nextWord trees) child).words.length := by
    simp only [TreeRuntime.nextWord, doneNext, appendTree, List.length_append, Nat.add_assoc]
  have prefixBound : runtime.wordBase ≤ runtime.records.length := by
    have fit := held.recordsFit
    unfold TreeRuntime.nextWord at fit
    omega
  have length : (runtime.records.take runtime.wordBase ++
      partialWords runtime.parent (runtime.done trees) (.state oldId :: pending)).length = runtime.nextWord trees := by
    rw [List.length_append, List.length_take, Nat.min_eq_left prefixBound,
      partialWords_length _ _ _ (by simpa only [TreeRuntime.done, forest_roots_length] using held.count)]
    simp only [TreeRuntime.nextWord, Nat.add_assoc]
  have extended := extend_region _ runtime.records
    (treeFrom (runtime.nextNode trees) (runtime.nextWord trees) child).words (runtime.nextWord trees) length
  change (runtime.recordValues trees (.state oldId :: pending)).take _ ++ _ ++
    (runtime.recordValues trees (.state oldId :: pending)).drop _ = _ at extended
  rw [extended]
  have root : (treeFrom (runtime.nextNode trees) (runtime.nextWord trees) child).roots =
      .state (runtime.nextNode (trees ++ [child]) - 1) := by
    simpa only [TreeRuntime.nextNode, doneNext] using appended_root (runtime.done trees) child nonterminal
  have rewritten := partialWords_state (runtime.records.take runtime.wordBase)
    (runtime.records.drop (runtime.nextWord (trees ++ [child]))) runtime.parent (runtime.done trees) pending
    (treeFrom (runtime.nextNode trees) (runtime.nextWord trees) child) root (oldId := oldId)
  have rootsLength : (runtime.done trees).roots.length = trees.length := forest_roots_length trees
  simpa only [TreeRuntime.recordValues, doneNext, wordsNext, List.length_take,
    Nat.min_eq_left prefixBound, rootsLength] using rewritten

theorem TreeRuntime.At.child_offsets {runtime : TreeRuntime}
    (held : runtime.At trees pending before) (child : Lanius.Compiler.Parser.ParseTree) :
    let nested := treeFrom (runtime.nextNode trees) (runtime.nextWord trees) child
    (runtime.offsetValues trees).take (runtime.nextNode trees) ++ nested.offsets.map Int.ofNat ++
        (runtime.offsetValues trees).drop (runtime.nextNode trees + nested.offsets.length) =
      runtime.offsetValues (trees ++ [child]) := by
  dsimp only
  have doneNext : runtime.done (trees ++ [child]) =
      appendTree (runtime.done trees) (treeFrom (runtime.nextNode trees) (runtime.nextWord trees) child) :=
    forest_snoc trees child _ _
  have prefixBound : runtime.nodeBase ≤ runtime.offsets.length := by
    have fit := held.offsetsFit
    unfold TreeRuntime.nextNode at fit
    omega
  have length : (runtime.offsets.take runtime.nodeBase ++
      (runtime.done trees).offsets.map Int.ofNat).length = runtime.nextNode trees := by
    simp only [List.length_append, List.length_take, Nat.min_eq_left prefixBound,
      List.length_map, TreeRuntime.nextNode]
  have extended := extend_region _ runtime.offsets
    ((treeFrom (runtime.nextNode trees) (runtime.nextWord trees) child).offsets.map Int.ofNat)
    (runtime.nextNode trees) length
  simpa only [TreeRuntime.offsetValues, TreeRuntime.nextNode, doneNext, appendTree,
    List.length_append, List.length_map, List.map_append, List.append_assoc, Nat.add_assoc] using extended

/-- Once the pending suffix is empty, executing the actual exit writes the
    parent offset and returns the exact canonical layout counts. No final
    buffer shape or successful constructor evaluation is assumed. -/
theorem TreeRuntime.At.finish {runtime : TreeRuntime}
    (held : runtime.At trees [] before) (checked : CheckedVisit program)
    (room : runtime.nextNode trees < runtime.offsets.length) (nonterminal : Nat) :
    let tree := Lanius.Compiler.Parser.ParseTree.nonterminal runtime.parent.production nonterminal
      runtime.parent.origin runtime.parent.position trees
    let layout := treeFrom runtime.nodeBase runtime.wordBase tree
    ∃ after, Executes program.core before (visitExit checked.symbols)
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
      CellEffect (CellSet.singleton runtime.offsetsCell) before after := by
  dsimp only
  have count : trees.length = runtime.parent.dot := by simpa using held.count
  let layout := treeFrom runtime.nodeBase runtime.wordBase
    (.nonterminal runtime.parent.production nonterminal runtime.parent.origin runtime.parent.position trees)
  have words : runtime.nextWord trees = runtime.wordBase + layout.words.length := by
    simp only [layout, treeFrom, List.length_append, child_words_length, forest_roots_length,
      recordHeader, List.length_cons, List.length_nil, count, TreeRuntime.nextWord,
      TreeRuntime.done, Nat.add_assoc]
    omega
  have nodes : runtime.nextNode trees + 1 = runtime.nodeBase + layout.offsets.length := by
    simp only [layout, treeFrom, List.length_append, List.length_cons, List.length_nil,
      count, TreeRuntime.nextNode, TreeRuntime.done, Nat.add_assoc]
  have offsetsLocal := held.offsetsLocal
  have capacityLocal := held.capacityLocal
  rw [← held.offset_length] at offsetsLocal capacityLocal
  obtain ⟨after, executed, backing, effect⟩ := checked.finish held.wellFormed offsetsLocal held.offsetsBacking
    capacityLocal held.parentLocal (Assertion.localPointsTo_local _ _ _ _ held.wordsOwned)
    (Assertion.localPointsTo_local _ _ _ _ held.nodesOwned)
    (held.offset_length ▸ room) (held.offset_length ▸ held.offsetsBound)
  have prefixBound : runtime.nodeBase ≤ runtime.offsets.length := by
    unfold TreeRuntime.nextNode at room
    omega
  have length : (runtime.offsets.take runtime.nodeBase ++ (runtime.done trees).offsets.map Int.ofNat).length =
      runtime.nextNode trees := by
    simp only [List.length_append, List.length_take, Nat.min_eq_left prefixBound,
      List.length_map, TreeRuntime.nextNode]
  have stored : (runtime.offsetValues trees).set (runtime.nextNode trees) (Int.ofNat runtime.wordBase) =
      runtime.offsets.take runtime.nodeBase ++ layout.offsets.map Int.ofNat ++
        runtime.offsets.drop (runtime.nodeBase + layout.offsets.length) := by
    unfold TreeRuntime.offsetValues
    rw [List.drop_eq_getElem_cons room,
      List.set_append_right _ _ (Nat.le_of_eq length), length, Nat.sub_self]
    simp only [List.set_cons_zero, layout, treeFrom, List.map_append, List.map_cons, List.map_nil,
      List.length_append, List.length_cons, List.length_nil, count, TreeRuntime.done,
      TreeRuntime.nextNode, List.append_assoc, List.cons_append, List.nil_append, Nat.add_assoc]
  have recordShape : runtime.recordValues trees [] =
      runtime.records.take runtime.wordBase ++ layout.words ++
        runtime.records.drop (runtime.wordBase + layout.words.length) := by
    rw [TreeRuntime.recordValues, words, TreeRuntime.done,
      partialWords_complete runtime.parent trees runtime.nodeBase runtime.wordBase nonterminal count]
  refine ⟨after, ?_, ?_, ?_, effect⟩
  · simpa only [words, nodes] using executed
  · simpa only [recordShape] using effect.preserves_entry held.wellFormed held.recordsBacking held.buffersDistinct
  · simpa only [stored] using backing

end Lanius.Extraction.ParserTreeSource
