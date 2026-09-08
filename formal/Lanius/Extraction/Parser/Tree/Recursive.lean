import Lanius.Extraction.Parser.Tree.Runtime
import Lanius.Extraction.Parser.Tree.Resume

namespace Lanius.Extraction.ParserTreeSource

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.Compiler.Parser Lanius.Extraction.ParserTreeLayout

private theorem local_read {id : Lanius.VarId} (found : before.local? id = some value) :
    Evaluates program before (.local id) value before :=
  ⟨1, evalLocal_of_local 0 program before id value found⟩

def TreeRuntime.slotState (runtime : TreeRuntime) (trees : List Lanius.Compiler.Parser.ParseTree)
    (before : State) : State :=
  before.bindLocal 16 (.signed .i32 (Int.ofNat (runtime.wordBase + 4 + trees.length * 3)))

def TreeRuntime.outputs (runtime : TreeRuntime) : CellSet :=
  CellSet.union (CellSet.singleton runtime.recordsCell) (CellSet.singleton runtime.offsetsCell)

def TreeRuntime.writes (runtime : TreeRuntime) : CellSet := fun cell =>
  cell = runtime.recordsCell ∨ cell = runtime.offsetsCell ∨ cell = runtime.wordsCell ∨
    cell = runtime.nodesCell ∨ cell = runtime.cursorCell

/-- Fixed scalar/slice parameters survive the loop's complete write footprint.
    Separation from cursor cells comes from initialization; separation from
    output-array cells follows from the actual value constructors. -/
theorem TreeRuntime.At.preserves_fixed {runtime : TreeRuntime}
    (held : runtime.At trees pending before) (effect : CellEffect runtime.writes before after)
    {id : Lanius.VarId} (small : id < 13) (found : before.local? id = some value)
    (plain : ∀ values, value ≠ .array values) : after.local? id = some value := by
  apply effect.preserves_local held.wellFormed found
  intro cell binding written
  have fixed := held.fixedSeparate id small cell binding
  have records := local_cell_ne_of_distinct_value found held.recordsBacking (plain _) binding
  have offsets := local_cell_ne_of_distinct_value found held.offsetsBacking (plain _) binding
  exact written.elim records (fun h => h.elim offsets (fun h => h.elim fixed.1 (fun h => h.elim fixed.2.1 fixed.2.2)))

/-- The result required from the smaller-state induction hypothesis. It records
    an actual evaluation of the checked recursive call, exact appended bytes,
    and its output-only effect. Constructing this result is still an obligation
    of the whole-call proof; the branch lemma below does not prove recursion. -/
structure TreeRuntime.ChildCall (runtime : TreeRuntime) (checked : CheckedVisit program)
    (before : State) (trees : List Lanius.Compiler.Parser.ParseTree) (pending : List Child)
    (child : Lanius.Compiler.Parser.ParseTree) where
  after : State
  evaluation : Evaluates program.core (runtime.slotState trees before) (recursiveCall checked.symbols)
    (resultValue checked.symbols.resultType 0 (Int.ofNat (runtime.nextNode (trees ++ [child])))
      (Int.ofNat (runtime.nextWord (trees ++ [child])))) after
  records : after.cellEntry? runtime.recordsCell = some {
    id := runtime.recordsCell, value := some (.array (signedI32Values
      ((runtime.recordValues trees pending).take (runtime.nextWord trees) ++
        (treeFrom (runtime.nextNode trees) (runtime.nextWord trees) child).words ++
        (runtime.recordValues trees pending).drop (runtime.nextWord (trees ++ [child]))))) }
  offsets : after.cellEntry? runtime.offsetsCell = some {
    id := runtime.offsetsCell, value := some (.array (signedI32Values
      ((runtime.offsetValues trees).take (runtime.nextNode trees) ++
        (treeFrom (runtime.nextNode trees) (runtime.nextWord trees) child).offsets.map Int.ofNat ++
        (runtime.offsetValues trees).drop (runtime.nextNode (trees ++ [child]))))) }
  effect : CellEffect runtime.outputs (runtime.slotState trees before) after

theorem TreeRuntime.At.bind_slot {runtime : TreeRuntime} (held : runtime.At trees pending before) :
    runtime.At trees pending (runtime.slotState trees before) := by
  let value := Value.signed .i32 (Int.ofNat (runtime.wordBase + 4 + trees.length * 3))
  have preserve {id : Lanius.VarId} {v : Value} (small : id < 16) (found : before.local? id = some v) :
      (before.bindLocal 16 value).local? id = some v :=
    (bindLocal_preserves_other_local (boundId := 16) (queriedId := id) held.wellFormed
      (Ne.symm (Nat.ne_of_lt small))).trans found
  have backing {cell : CellId} {v : Value}
      (found : before.cellEntry? cell = some { id := cell, value := some v }) :
      (before.bindLocal 16 value).cellEntry? cell = some { id := cell, value := some v } :=
    ((bindLocal_effect before 16 value).oldCells cell
      (StateWellFormed.cell_lt_next_of_entry held.wellFormed found) (by simp [CellSet.empty])).trans found
  refine ⟨bindLocal_preserves_well_formed _ _ _ held.wellFormed, held.count, held.recordsFit,
    held.offsetsFit, held.recordsBound, held.offsetsBound,
    preserve (by decide) held.parentLocal, preserve (by decide) held.countLocal,
    preserve (by decide) held.recordsLocal, preserve (by decide) held.offsetsLocal,
    preserve (by decide) held.capacityLocal,
    bindLocal_preserves_localPointsTo_of_ne _ _ _ _ _ _ held.wellFormed (by decide) held.wordsOwned,
    bindLocal_preserves_localPointsTo_of_ne _ _ _ _ _ _ held.wellFormed (by decide) held.nodesOwned,
    bindLocal_preserves_localPointsTo_of_ne _ _ _ _ _ _ held.wellFormed (by decide) held.cursorOwned,
    backing held.recordsBacking, backing held.offsetsBacking, held.buffersDistinct, held.cursorsDistinct, ?_⟩
  intro id member cell found
  apply held.fixedSeparate id member cell
  have different : (16 : Lanius.VarId) ≠ id :=
    Ne.symm (Nat.ne_of_lt (Nat.lt_of_lt_of_le member (by decide : 13 ≤ 16)))
  simpa only [TreeRuntime.slotState, bindLocal_preserves_other_cellId _ _ _ _ different] using found

/-- Derive all twelve recursive argument evaluations from the parent loop
    state. The child's ID comes from the exact pending payload in the buffer,
    and depth subtraction is proved not to wrap. -/
theorem TreeRuntime.At.recursive_arguments {runtime : TreeRuntime}
    (held : runtime.At trees (.state childId :: pending) before) (program : Program)
    (workspaceLocal : before.local? 0 = some workspaceValue)
    (workspaceLengthLocal : before.local? 1 = some workspaceLengthValue)
    (tokensLocal : before.local? 2 = some tokenCountValue)
    (statesLocal : before.local? 3 = some stateCountValue)
    (capacityLocal : before.local? 6 = some (.signed .i32 (Int.ofNat runtime.records.length)))
    (depthLocal : before.local? 11 = some (.signed .i32 (Int.ofNat depth)))
    (positive : 0 < depth) (depthBound : depth ≤ 2147483647) :
    ArgumentsEvaluateTo program (runtime.slotState trees before)
      [.local 0, .local 1, .local 2, .local 3, childPayload,
        .local 5, .local 6, .local 7, .local 8, .local 14, .local 13,
        .binary .subtract (.local 11) (.value (.signed .i32 1))]
      [workspaceValue, workspaceLengthValue, tokenCountValue, stateCountValue,
        .signed .i32 (Int.ofNat childId),
        .slice (.scalar (.signed .i32)) runtime.recordsCell [] 0 runtime.records.length,
        .signed .i32 (Int.ofNat runtime.records.length),
        .slice (.scalar (.signed .i32)) runtime.offsetsCell [] 0 runtime.offsets.length,
        .signed .i32 (Int.ofNat runtime.offsets.length),
        .signed .i32 (Int.ofNat (runtime.nextNode trees)),
        .signed .i32 (Int.ofNat (runtime.nextWord trees)), .signed .i32 (Int.ofNat (depth - 1))]
      (runtime.slotState trees before) := by
  let entered := runtime.slotState trees before
  let slot := runtime.wordBase + 4 + trees.length * 3
  have entry := held.bind_slot
  have preserve {id : Lanius.VarId} {value : Value} (small : id < 16) (found : before.local? id = some value) :
      entered.local? id = some value :=
    (bindLocal_preserves_other_local (boundId := 16) (queriedId := id) held.wellFormed
      (Ne.symm (Nat.ne_of_lt small))).trans found
  have slotLocal : entered.local? 16 = some (.signed .i32 (Int.ofNat slot)) :=
    bindLocal_finds_local _ _ _ held.wellFormed
  have bound : slot + 1 < (runtime.recordValues trees (.state childId :: pending)).length :=
    (List.getElem?_eq_some_iff.mp held.pending_head.2.1).1
  have capacity := held.recordsBound
  rw [← held.record_length] at capacity
  have indexEvaluation : Evaluates program entered (.binary .add (.local 16) (.value (.signed .i32 1)))
      (.signed .i32 (Int.ofNat (slot + 1))) entered :=
    evaluatesNatI32Add (local_read slotLocal) ⟨1, rfl⟩ (by omega)
  have recordsLocal := entry.recordsLocal
  rw [← held.record_length] at recordsLocal
  have selected : (runtime.recordValues trees (.state childId :: pending)).get ⟨slot + 1, bound⟩ = Int.ofNat childId :=
    (List.getElem?_eq_some_iff.mp held.pending_head.2.1).2
  have payload : Evaluates program entered childPayload (.signed .i32 (Int.ofNat childId)) entered := by
    change Evaluates program entered (.index (.local 5) (.binary .add (.local 16) (.value (.signed .i32 1))))
      (.signed .i32 (Int.ofNat childId)) entered
    simpa only [selected] using evaluatesSignedI32SliceIndex program entered entered entered _
      (.local 5) (.binary .add (.local 16) (.value (.signed .i32 1))) runtime.recordsCell (slot + 1) bound
      (local_read recordsLocal) indexEvaluation entry.recordsBacking
  refine .cons (local_read (preserve (by decide) workspaceLocal)) ?_
  refine .cons (local_read (preserve (by decide) workspaceLengthLocal)) ?_
  refine .cons (local_read (preserve (by decide) tokensLocal)) ?_
  refine .cons (local_read (preserve (by decide) statesLocal)) ?_
  refine .cons payload (.cons (local_read entry.recordsLocal) ?_)
  refine .cons (local_read (preserve (by decide) capacityLocal)) ?_
  refine .cons (local_read entry.offsetsLocal) (.cons (local_read entry.capacityLocal) ?_)
  refine .cons (local_read (Assertion.localPointsTo_local _ _ _ _ entry.nodesOwned)) ?_
  refine .cons (local_read (Assertion.localPointsTo_local _ _ _ _ entry.wordsOwned)) ?_
  exact .cons (evaluatesNatI32Subtract (local_read (preserve (by decide) depthLocal))
    ⟨1, rfl⟩ (by omega) (by omega)) (.nil _ _)

/-- Enter the actual state-child branch. Both success and failure use the
    same bounded slot arithmetic and retained tag read. -/
theorem TreeRuntime.At.state_entry {runtime : TreeRuntime}
    (held : runtime.At trees (.state oldId :: pending) before) (checked : CheckedVisit program) :
    Evaluates program.core before childSlot
      (.signed .i32 (Int.ofNat (runtime.wordBase + 4 + trees.length * 3))) before ∧
    Evaluates program.core (runtime.slotState trees before)
      (.binary .equal (.index (.local 5) (.local 16)) (.constant checked.symbols.childState))
      (.boolean true) (runtime.slotState trees before) := by
  let slot := runtime.wordBase + 4 + trees.length * 3
  let entered := runtime.slotState trees before
  have entry := held.bind_slot
  have slotLocal : entered.local? 16 = some (.signed .i32 (Int.ofNat slot)) :=
    bindLocal_finds_local _ _ _ held.wellFormed
  have payloadBound := (List.getElem?_eq_some_iff.mp held.pending_head.2.1).1
  rw [held.record_length] at payloadBound
  have recordBound := held.recordsBound
  have slotBound : slot < (runtime.recordValues trees (.state oldId :: pending)).length := by
    rw [held.record_length]; dsimp [slot]; omega
  have tagRead : Evaluates program.core entered (.index (.local 5) (.local 16)) (.signed .i32 2) entered := by
    have recordsLocal := entry.recordsLocal
    rw [← held.record_length] at recordsLocal
    have selected : (runtime.recordValues trees (.state oldId :: pending)).get ⟨slot, slotBound⟩ = 2 :=
      (List.getElem?_eq_some_iff.mp held.pending_head.1).2
    simpa only [selected] using evaluatesSignedI32SliceIndex program.core entered entered entered _
      (.local 5) (.local 16) runtime.recordsCell slot slotBound
      (local_read recordsLocal) (local_read slotLocal) entry.recordsBacking
  refine ⟨?_, evaluatesEagerBinary (by decide) (by decide) tagRead (evaluatesConstant checked.childTag) rfl⟩
  apply evaluatesNatI32Add
  · exact evaluatesNatI32Add (local_read held.parentLocal) ⟨1, rfl⟩ (by omega)
  · exact evaluatesNatI32Multiply (local_read (Assertion.localPointsTo_local _ _ _ _ held.cursorOwned))
      ⟨1, rfl⟩ (by omega)
  · omega

/-- Execute a complete state-child iteration from a proved recursive call.
    This discharges the tag branch, result scope, parent rewrite, all cursor
    stores, and exact next loop invariant. The strong state-ID induction must
    supply `nested`; there is no standalone child-success axiom. -/
theorem TreeRuntime.At.state_step {runtime : TreeRuntime}
    (held : runtime.At trees (.state oldId :: pending) before) (checked : CheckedVisit program)
    (child : Lanius.Compiler.Parser.ParseTree)
    (nonterminal : ∃ production nt start finish children,
      child = .nonterminal production nt start finish children)
    (nested : runtime.ChildCall checked before trees (.state oldId :: pending) child)
    (recordsFit : runtime.nextWord (trees ++ [child]) ≤ runtime.records.length)
    (offsetsFit : runtime.nextNode (trees ++ [child]) ≤ runtime.offsets.length) :
    ∃ after, Executes program.core before (childIteration checked.symbols) .next after ∧
      runtime.At (trees ++ [child]) pending after ∧ CellEffect runtime.writes before after := by
  let slot := runtime.wordBase + 4 + trees.length * 3
  let entered := runtime.slotState trees before
  have entry := held.bind_slot
  have slotLocal : entered.local? 16 = some (.signed .i32 (Int.ofNat slot)) :=
    bindLocal_finds_local _ _ _ held.wellFormed
  have doneNext : runtime.done (trees ++ [child]) =
      appendTree (runtime.done trees) (treeFrom (runtime.nextNode trees) (runtime.nextWord trees) child) :=
    forest_snoc trees child _ _
  have wordsNext : runtime.nextWord (trees ++ [child]) = runtime.nextWord trees +
      (treeFrom (runtime.nextNode trees) (runtime.nextWord trees) child).words.length := by
    simp only [TreeRuntime.nextWord, doneNext, appendTree, List.length_append, Nat.add_assoc]
  have nodesNext : runtime.nextNode (trees ++ [child]) = runtime.nextNode trees +
      (treeFrom (runtime.nextNode trees) (runtime.nextWord trees) child).offsets.length := by
    simp only [TreeRuntime.nextNode, doneNext, appendTree, List.length_append, Nat.add_assoc]
  have nonempty : 0 < runtime.nextNode (trees ++ [child]) := by
    obtain ⟨production, nt, start, finish, children, rfl⟩ := nonterminal
    simp only [nodesNext, treeFrom, List.length_append, List.length_cons, List.length_nil]
    omega
  have payloadBound := (List.getElem?_eq_some_iff.mp held.pending_head.2.1).1
  rw [held.record_length] at payloadBound
  have recordBound := held.recordsBound
  obtain ⟨slotEvaluation, tagEqual⟩ := held.state_entry checked
  have unwritten {id : Lanius.VarId} {value : Value} (found : entered.local? id = some value)
      (plain : ∀ values, value ≠ .array values) (cell : CellId) (binding : entered.cellId? id = some cell) :
      ¬ runtime.outputs cell := by
    exact fun written => written.elim
      (local_cell_ne_of_distinct_value found entry.recordsBacking (plain _) binding)
      (local_cell_ne_of_distinct_value found entry.offsetsBacking (plain _) binding)
  have preserved {id : Lanius.VarId} {value : Value} (found : entered.local? id = some value)
      (plain : ∀ values, value ≠ .array values) : nested.after.local? id = some value :=
    nested.effect.preserves_local entry.wellFormed found (unwritten found plain)
  have privateOwned {id : Lanius.VarId} {cell : CellId} {n : Nat}
      (owned : (Assertion.localPointsTo id cell (some (.signed .i32 (Int.ofNat n)))).holds entered) :
      (Assertion.localPointsTo id cell (some (.signed .i32 (Int.ofNat n)))).holds nested.after :=
    nested.effect.preserves_localPointsTo entry.wellFormed owned
      (unwritten (Assertion.localPointsTo_local _ _ _ _ owned) (by intro values impossible; cases impossible) cell owned.1)
  let appended := (runtime.recordValues trees (.state oldId :: pending)).take (runtime.nextWord trees) ++
    (treeFrom (runtime.nextNode trees) (runtime.nextWord trees) child).words ++
    (runtime.recordValues trees (.state oldId :: pending)).drop (runtime.nextWord (trees ++ [child]))
  have appendedLength : appended.length = runtime.records.length := by
    simp only [appended, List.length_append, List.length_take, List.length_drop, held.record_length,
      Nat.min_eq_left held.recordsFit]
    rw [wordsNext] at recordsFit ⊢
    omega
  have recordsLocal := preserved entry.recordsLocal (by intro values impossible; cases impossible)
  rw [← appendedLength] at recordsLocal
  obtain ⟨resumed, expansion, records, nodes, words, resumeEffect⟩ := checked.child_success nested.evaluation
    nested.effect.wellFormed (preserved slotLocal (by intro values impossible; cases impossible))
    (privateOwned entry.nodesOwned) (privateOwned entry.wordsOwned) (Ne.symm held.cursorsDistinct.1)
    recordsLocal nested.records (by rw [appendedLength]; exact payloadBound)
    (appendedLength ▸ held.recordsBound) nonempty (Nat.le_trans offsetsFit held.offsetsBound)
  have cursorLocal := Assertion.localPointsTo_local _ _ _ _ entry.cursorOwned
  have cursorNotRecords : runtime.cursorCell ≠ runtime.recordsCell :=
    local_cell_ne_of_distinct_value cursorLocal entry.recordsBacking (by intro impossible; cases impossible) entry.cursorOwned.1
  have cursorNotOffsets : runtime.cursorCell ≠ runtime.offsetsCell :=
    local_cell_ne_of_distinct_value cursorLocal entry.offsetsBacking (by intro impossible; cases impossible) entry.cursorOwned.1
  have offsetsNotWords : runtime.offsetsCell ≠ runtime.wordsCell := Ne.symm
    (local_cell_ne_of_distinct_value (Assertion.localPointsTo_local _ _ _ _ entry.wordsOwned)
      entry.offsetsBacking (by intro impossible; cases impossible) entry.wordsOwned.1)
  have offsetsNotNodes : runtime.offsetsCell ≠ runtime.nodesCell := Ne.symm
    (local_cell_ne_of_distinct_value (Assertion.localPointsTo_local _ _ _ _ entry.nodesOwned)
      entry.offsetsBacking (by intro impossible; cases impossible) entry.nodesOwned.1)
  have resumedCursor := resumeEffect.preserves_localPointsTo nested.effect.wellFormed (privateOwned entry.cursorOwned)
    (show ¬ childResultWrites runtime.recordsCell runtime.nodesCell runtime.wordsCell runtime.cursorCell by
      simp [childResultWrites, CellSet.union, CellSet.singleton, cursorNotRecords,
        Ne.symm held.cursorsDistinct.2.1, Ne.symm held.cursorsDistinct.2.2])
  have resumedOffsets := resumeEffect.preserves_entry nested.effect.wellFormed nested.offsets
    (show ¬ childResultWrites runtime.recordsCell runtime.nodesCell runtime.wordsCell runtime.offsetsCell by
      simp [childResultWrites, CellSet.union, CellSet.singleton, Ne.symm held.buffersDistinct, offsetsNotNodes, offsetsNotWords])
  obtain ⟨completed, increment, cursor, incrementEffect⟩ := evaluatesOwnedLocalUpdate resumeEffect.wellFormed resumedCursor
    (show Evaluates program.core resumed (.value (.signed .i32 1)) (.signed .i32 1) resumed from ⟨1, rfl⟩)
    (show evalAssignValue program.core.target .add (some (.signed .i32 (Int.ofNat trees.length))) (.signed .i32 1) =
        .ok (.signed .i32 (Int.ofNat (trees.length + 1))) from by
      simp only [evalAssignValue, assignOpBinary?, evalBinaryValue, evalSignedBinary]
      rw [show Int.ofNat trees.length + 1 = Int.ofNat (trees.length + 1) by simp,
        wrapSigned_i32_ofNat program.core.target (trees.length + 1) (by omega)]
      rfl)
  have recordsAfter := incrementEffect.preserves_entry resumeEffect.wellFormed records (Ne.symm cursorNotRecords)
  have offsetsAfter := incrementEffect.preserves_entry resumeEffect.wellFormed resumedOffsets (Ne.symm cursorNotOffsets)
  have nodesAfter := incrementEffect.preserves_localPointsTo resumeEffect.wellFormed nodes held.cursorsDistinct.2.2
  have wordsAfter := incrementEffect.preserves_localPointsTo resumeEffect.wellFormed words held.cursorsDistinct.2.1
  have outputsSubset : CellSet.Subset runtime.outputs runtime.writes := by
    intro cell member
    rcases member with member | member <;> simp_all [TreeRuntime.writes, CellSet.singleton]
  have resumeSubset : CellSet.Subset (childResultWrites runtime.recordsCell runtime.nodesCell runtime.wordsCell) runtime.writes := by
    intro cell member
    rcases member with member | member | member <;> simp_all [TreeRuntime.writes, CellSet.singleton]
  have incrementSubset : CellSet.Subset (CellSet.singleton runtime.cursorCell) runtime.writes := by
    intro cell member; simp_all [TreeRuntime.writes, CellSet.singleton]
  have effect := CellEffect.closeLocal before 16 (.signed .i32 (Int.ofNat slot)) held.wellFormed
    ((nested.effect.weaken outputsSubset).trans
      ((resumeEffect.weaken resumeSubset).trans (incrementEffect.weaken incrementSubset)))
  have preserve {id : Lanius.VarId} {value : Value}
      (member : id < 13) (found : before.local? id = some value)
      (plain : ∀ values, value ≠ .array values) : (restoreLocals before completed).local? id = some value :=
    held.preserves_fixed effect member found plain
  refine ⟨restoreLocals before completed, ?_, ?_, effect⟩
  · exact executesLetLocal slotEvaluation
      (executesSequence (executesIfTrue tagEqual expansion)
        (executesSequence (executesExpression increment) (executesSkip _ _)))
  · refine ⟨effect.wellFormed, ?_, recordsFit, offsetsFit, held.recordsBound, held.offsetsBound,
      preserve (by decide) held.parentLocal (by intro values impossible; cases impossible),
      preserve (by decide) held.countLocal (by intro values impossible; cases impossible),
      preserve (by decide) held.recordsLocal (by intro values impossible; cases impossible),
      preserve (by decide) held.offsetsLocal (by intro values impossible; cases impossible),
      preserve (by decide) held.capacityLocal (by intro values impossible; cases impossible),
      ⟨held.wordsOwned.1, wordsAfter.2⟩, ⟨held.nodesOwned.1, nodesAfter.2⟩,
      ⟨held.cursorOwned.1, ?_⟩, ?_, ?_, held.buffersDistinct, held.cursorsDistinct, ?_⟩
    · have count := held.count
      simp only [List.length_append, List.length_cons, List.length_nil] at count ⊢
      omega
    · simpa only [List.length_append, List.length_cons, List.length_nil, Nat.zero_add,
        restoreLocals, State.cellEntry?] using cursor.2
    · have shape := held.child_records child nonterminal
      dsimp only at shape
      rw [← wordsNext] at shape
      simpa only [appended, slot, shape, restoreLocals, State.cellEntry?] using recordsAfter
    · have shape := held.child_offsets child
      dsimp only at shape
      rw [← nodesNext] at shape
      simpa only [shape, restoreLocals, State.cellEntry?] using offsetsAfter
    · intro id member cell found
      apply held.fixedSeparate id member cell
      simpa only [restoreLocals, State.cellId?] using found

end Lanius.Extraction.ParserTreeSource
