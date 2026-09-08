import Lanius.Extraction.Parser.Tree.Recursive

namespace Lanius.Extraction.ParserTreeSource

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Compiler.Parser Lanius.Extraction.ParserTreeLayout

private theorem local_read {id : Lanius.VarId} (found : before.local? id = some value) :
    Evaluates program before (.local id) value before :=
  ⟨1, evalLocal_of_local 0 program before id value found⟩

/-- Cursor identities come from actual allocation, never from a caller-owned
    private-local premise. All source and output coordinates stay unchanged. -/
def TreeRuntime.freshCursors (runtime : TreeRuntime) (before : State) : TreeRuntime :=
  { runtime with
    wordsCell := before.nextCell
    nodesCell := before.nextCell + 1
    cursorCell := before.nextCell + 2 }

def TreeRuntime.initialState (runtime : TreeRuntime) (before : State) : State :=
  let wordState := before.bindLocal 13 (.signed .i32 (Int.ofNat (runtime.wordBase + 4 + runtime.parent.dot * 3)))
  let nodeState := wordState.bindLocal 14 (.signed .i32 (Int.ofNat runtime.nodeBase))
  nodeState.bindLocal 15 (.signed .i32 0)

/-- Public values after the reader result is bound. The reader supplies the
    exact first record; cursor ownership and fixed-parameter separation are
    deliberately absent and will be derived from the three source `let`s. -/
structure TreeRuntime.Entry (runtime : TreeRuntime) (pending : List Child) (before : State) : Prop where
  wellFormed : StateWellFormed before
  count : pending.length = runtime.parent.dot
  recordsFit : runtime.wordBase + 4 + runtime.parent.dot * 3 ≤ runtime.records.length
  offsetsFit : runtime.nodeBase ≤ runtime.offsets.length
  recordsBound : runtime.records.length ≤ 2147483647
  offsetsBound : runtime.offsets.length ≤ 2147483647
  parentLocal : before.local? 10 = some (.signed .i32 (Int.ofNat runtime.wordBase))
  nodeLocal : before.local? 9 = some (.signed .i32 (Int.ofNat runtime.nodeBase))
  countLocal : before.local? 12 = some (.signed .i32 (Int.ofNat runtime.parent.dot))
  recordsLocal : before.local? 5 = some (.slice (.scalar (.signed .i32)) runtime.recordsCell [] 0 runtime.records.length)
  offsetsLocal : before.local? 7 = some (.slice (.scalar (.signed .i32)) runtime.offsetsCell [] 0 runtime.offsets.length)
  capacityLocal : before.local? 8 = some (.signed .i32 (Int.ofNat runtime.offsets.length))
  recordsBacking : before.cellEntry? runtime.recordsCell = some {
    id := runtime.recordsCell, value := some (.array (signedI32Values
      (runtime.records.take runtime.wordBase ++ derivationRecordWords runtime.parent pending ++
        runtime.records.drop (runtime.wordBase + 4 + runtime.parent.dot * 3)))) }
  offsetsBacking : before.cellEntry? runtime.offsetsCell = some {
    id := runtime.offsetsCell, value := some (.array (signedI32Values runtime.offsets)) }
  buffersDistinct : runtime.recordsCell ≠ runtime.offsetsCell

/-- The initial loop invariant is constructed from the actual initialized
    state, including freshness of all cursor cells relative to every fixed
    parameter and exact storage supplied by the reader. -/
theorem TreeRuntime.Entry.initialize {runtime : TreeRuntime}
    (entry : runtime.Entry pending before) :
    (runtime.freshCursors before).At [] pending (runtime.initialState before) := by
  let wordsValue := Value.signed .i32 (Int.ofNat (runtime.wordBase + 4 + runtime.parent.dot * 3))
  let nodesValue := Value.signed .i32 (Int.ofNat runtime.nodeBase)
  let wordState := before.bindLocal 13 wordsValue
  let nodeState := wordState.bindLocal 14 nodesValue
  let entered := nodeState.bindLocal 15 (.signed .i32 0)
  have wordWF : StateWellFormed wordState := bindLocal_preserves_well_formed _ _ _ entry.wellFormed
  have nodeWF : StateWellFormed nodeState := bindLocal_preserves_well_formed _ _ _ wordWF
  have enteredWF : StateWellFormed entered := bindLocal_preserves_well_formed _ _ _ nodeWF
  have preserve {id : Lanius.VarId} {value : Value} (small : id < 13) (found : before.local? id = some value) :
      entered.local? id = some value := by
    exact (bindLocal_preserves_other_local (boundId := 15) (queriedId := id) nodeWF
      (Ne.symm (Nat.ne_of_lt (Nat.lt_of_lt_of_le small (by decide : 13 ≤ 15))))).trans
      ((bindLocal_preserves_other_local (boundId := 14) (queriedId := id) wordWF
        (Ne.symm (Nat.ne_of_lt (Nat.lt_of_lt_of_le small (by decide : 13 ≤ 14))))).trans
        ((bindLocal_preserves_other_local (boundId := 13) (queriedId := id) entry.wellFormed
          (Ne.symm (Nat.ne_of_lt small))).trans found))
  have unchanged := ((bindLocal_effect before 13 wordsValue).trans_same
    (bindLocal_effect wordState 14 nodesValue)).trans_same (bindLocal_effect nodeState 15 (.signed .i32 0))
  have backing {cell : CellId} {value : Value}
      (found : before.cellEntry? cell = some { id := cell, value := some value }) :
      entered.cellEntry? cell = some { id := cell, value := some value } :=
    (unchanged.oldCells cell (StateWellFormed.cell_lt_next_of_entry entry.wellFormed found)
      (by simp [CellSet.empty])).trans found
  have words := bindLocal_preserves_localPointsTo_of_ne nodeState 15 13 (.signed .i32 0) before.nextCell _
    nodeWF (by decide) (bindLocal_preserves_localPointsTo_of_ne wordState 14 13 nodesValue before.nextCell _
      wordWF (by decide) (bindLocal_owns_fresh before 13 wordsValue entry.wellFormed))
  have nodes := bindLocal_preserves_localPointsTo_of_ne nodeState 15 14 (.signed .i32 0) wordState.nextCell _
    nodeWF (by decide) (bindLocal_owns_fresh wordState 14 nodesValue wordWF)
  have cursor := bindLocal_owns_fresh nodeState 15 (.signed .i32 0) nodeWF
  have wordFrontier : wordState.nextCell = before.nextCell + 1 := rfl
  have nodeFrontier : nodeState.nextCell = before.nextCell + 2 := rfl
  change (runtime.freshCursors before).At [] pending entered
  refine ⟨enteredWF, by simpa [TreeRuntime.freshCursors] using entry.count, ?_, ?_, entry.recordsBound, entry.offsetsBound,
    preserve (by decide) entry.parentLocal, preserve (by decide) entry.countLocal,
    preserve (by decide) entry.recordsLocal, preserve (by decide) entry.offsetsLocal,
    preserve (by decide) entry.capacityLocal, ?_, ?_, ?_, ?_, ?_, entry.buffersDistinct, ?_, ?_⟩
  · simpa only [TreeRuntime.nextWord, TreeRuntime.done, TreeRuntime.freshCursors, forestFrom,
      List.length_nil, Nat.add_zero] using entry.recordsFit
  · simpa only [TreeRuntime.nextNode, TreeRuntime.done, TreeRuntime.freshCursors, forestFrom, List.length_nil, Nat.add_zero] using entry.offsetsFit
  · simpa only [TreeRuntime.nextWord, TreeRuntime.done, TreeRuntime.freshCursors, forestFrom,
      List.length_nil, Nat.add_zero, wordsValue] using words
  · simpa only [TreeRuntime.nextNode, TreeRuntime.done, TreeRuntime.freshCursors, forestFrom,
      List.length_nil, Nat.add_zero, wordFrontier, nodesValue] using nodes
  · change (Assertion.localPointsTo 15 (before.nextCell + 2) (some (.signed .i32 0))).holds entered
    rw [← nodeFrontier]
    exact cursor
  · simpa only [TreeRuntime.recordValues, TreeRuntime.nextWord, TreeRuntime.done, TreeRuntime.freshCursors,
      forestFrom, List.length_nil, Nat.add_zero, partialWords_initial runtime.parent pending entry.count] using backing entry.recordsBacking
  · simpa only [TreeRuntime.offsetValues, TreeRuntime.nextNode, TreeRuntime.done, TreeRuntime.freshCursors,
      forestFrom, List.length_nil, List.map_nil, List.append_nil, Nat.add_zero, List.take_append_drop] using backing entry.offsetsBacking
  · change before.nextCell ≠ before.nextCell + 1 ∧ before.nextCell ≠ before.nextCell + 2 ∧
      before.nextCell + 1 ≠ before.nextCell + 2
    exact ⟨Nat.ne_of_lt (Nat.lt_succ_self _),
      Nat.ne_of_lt (Nat.lt_trans (Nat.lt_succ_self _) (Nat.lt_succ_self _)),
      Nat.ne_of_lt (Nat.lt_succ_self _)⟩
  · intro id small cell found
    have bound : before.cellId? id = some cell := by
      simpa only [entered, nodeState, wordState,
        bindLocal_preserves_other_cellId _ 15 id _ (Ne.symm (Nat.ne_of_lt (Nat.lt_of_lt_of_le small (by decide : 13 ≤ 15)))),
        bindLocal_preserves_other_cellId _ 14 id _ (Ne.symm (Nat.ne_of_lt (Nat.lt_of_lt_of_le small (by decide : 13 ≤ 14)))),
        bindLocal_preserves_other_cellId _ 13 id _ (Ne.symm (Nat.ne_of_lt small))] using found
    have old := StateWellFormed.cell_lt_next_of_local_binding id cell entry.wellFormed bound
    change cell ≠ before.nextCell ∧ cell ≠ before.nextCell + 1 ∧ cell ≠ before.nextCell + 2
    exact ⟨Nat.ne_of_lt old, Nat.ne_of_lt (Nat.lt_of_lt_of_le old (Nat.le_add_right _ 1)),
      Nat.ne_of_lt (Nat.lt_of_lt_of_le old (Nat.le_add_right _ 2))⟩

/-- Execute all three real cursor initializers and close their lexical scopes
    around the supplied loop-and-exit proof. Only the two output buffers remain
    in the caller-visible footprint; writes to freshly allocated cursors do not.
    The postcondition uses cells, as in the existing reader scope rules. -/
theorem TreeRuntime.Entry.with_cursors {runtime : TreeRuntime}
    (entry : runtime.Entry pending before) (checked : CheckedVisit program)
    (post : List Cell → Prop)
    (run : (runtime.freshCursors before).At [] pending (runtime.initialState before) →
      ∃ completed, Executes program.core (runtime.initialState before)
        (.sequence (.whileLoop (.binary .notEqual (.local 15) (.local 12)) (childIteration checked.symbols))
          (visitExit checked.symbols)) completion completed ∧ post completed.cells ∧
        CellEffect (runtime.freshCursors before).writes (runtime.initialState before) completed) :
    ∃ after, Executes program.core before (visitChildren checked.symbols) completion after ∧
      post after.cells ∧ CellEffect runtime.outputs before after := by
  let wordsValue := Value.signed .i32 (Int.ofNat (runtime.wordBase + 4 + runtime.parent.dot * 3))
  let nodesValue := Value.signed .i32 (Int.ofNat runtime.nodeBase)
  let wordState := before.bindLocal 13 wordsValue
  let nodeState := wordState.bindLocal 14 nodesValue
  have wordWF : StateWellFormed wordState := bindLocal_preserves_well_formed _ _ _ entry.wellFormed
  have nodeWF : StateWellFormed nodeState := bindLocal_preserves_well_formed _ _ _ wordWF
  have recordsBound := entry.recordsBound
  have fits := entry.recordsFit
  have wordEvaluation : Evaluates program.core before
      (.binary .add (.binary .add (.local 10) (.value (.signed .i32 4)))
        (.binary .multiply (.local 12) (.value (.signed .i32 3)))) wordsValue before := by
    apply evaluatesNatI32Add
    · exact evaluatesNatI32Add (local_read entry.parentLocal) ⟨1, rfl⟩ (by omega)
    · exact evaluatesNatI32Multiply (local_read entry.countLocal) ⟨1, rfl⟩ (by omega)
    · omega
  have nodeLocal : wordState.local? 9 = some nodesValue :=
    (bindLocal_preserves_other_local (boundId := 13) (queriedId := 9) entry.wellFormed (by decide)).trans entry.nodeLocal
  obtain ⟨completed, executed, satisfied, effect⟩ := run entry.initialize
  have closed := CellEffect.closeLocal before 13 wordsValue entry.wellFormed
    (CellEffect.closeLocal wordState 14 nodesValue wordWF
      (CellEffect.closeLocal nodeState 15 (.signed .i32 0) nodeWF effect))
  have visible : ∀ cell, cell < before.nextCell → (runtime.freshCursors before).writes cell → runtime.outputs cell := by
    intro cell old written
    rcases written with records | offsets | words | nodes | cursor
    · exact Or.inl records
    · exact Or.inr offsets
    · exact False.elim ((Nat.ne_of_lt old) words)
    · exact False.elim ((Nat.ne_of_lt (Nat.lt_of_lt_of_le old (Nat.le_add_right _ 1))) nodes)
    · exact False.elim ((Nat.ne_of_lt (Nat.lt_of_lt_of_le old (Nat.le_add_right _ 2))) cursor)
  refine ⟨restoreLocals before completed, ?_, satisfied, closed.narrow visible⟩
  have cursorScope := executesLetLocal (id := 15) (type := .scalar (.signed .i32))
    (afterInitializer := nodeState) (completed := completed) (show
      Evaluates program.core nodeState (.value (.signed .i32 0)) (.signed .i32 0) nodeState from ⟨1, rfl⟩) executed
  have nodeScope := executesLetLocal (id := 14) (type := .scalar (.signed .i32))
    (afterInitializer := wordState) (completed := restoreLocals nodeState completed) (local_read nodeLocal) cursorScope
  have wordScope := executesLetLocal (id := 13) (type := .scalar (.signed .i32))
    (afterInitializer := before) (completed := restoreLocals wordState (restoreLocals nodeState completed)) wordEvaluation nodeScope
  exact wordScope

end Lanius.Extraction.ParserTreeSource
