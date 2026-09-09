import Lanius.Extraction.CompactOutput.Nodes.Scope
import Lanius.Extraction.CompactOutput.Nodes.Fields

namespace Lanius.Extraction.CompactOutput.Nodes

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Compiler.Parser ParserTreeLayout Lanius.Extraction.SemanticTokens

structure ChildEntry (before : State) where
  record : RecordVisit
  child : ChildVisit
  index : Nat
  words : List Int
  records : List RecordVisit
  node : Nat
  count : Nat
  inputCell : CellId
  outputCell : CellId
  cursorCell : CellId
  position : Int
  capacity : Nat
  contents : List Int
  wellFormed : StateWellFormed before
  input : I32PrefixLocal before 0 inputCell words
  stored : record.Stored 0 words
  found : record.children[index]? = some child
  recordRead : before.local? 10 = some (.signed .i32 record.offset)
  indexRead : before.local? 13 = some (.signed .i32 index)
  sizeFit : words.length ≤ 2147483647
  countFit : count ≤ 2147483647
  nodeFit : node ≤ 2147483647
  linked : child.Linked 0 records node
  tokenBound : ∀ use, child = .token use → use.token < count
  countRead : before.local? 4 = some (.signed .i32 count)
  nodeRead : before.local? 9 = some (.signed .i32 node)
  room : capacity ≤ contents.length
  capacityFit : capacity ≤ 2147483647
  cursor : (Assertion.localPointsTo 8 cursorCell (some (.signed .i32 position))).holds before
  outputRead : before.local? 5 = some (.slice i32 outputCell [] 0 contents.length)
  capacityRead : before.local? 6 = some (.signed .i32 capacity)
  stable : ∀ id ∈ [5, 6], ∀ cell, before.cellId? id = some cell → cell ≠ cursorCell
  backing : before.cellEntry? outputCell = some {
    id := outputCell, value := some (.array (signedI32Values contents)) }

def ChildEntry.scope (entry : ChildEntry before) : State := childState before entry.record entry.index entry.child
def ChildEntry.outcome (entry : ChildEntry before) : AppendOutcome :=
  appendAll entry.capacity (encodeChild entry.child) entry.position entry.contents

theorem ChildEntry.write (entry : ChildEntry before) (word : Word.Checked program byte digit) :
    ∃ middle written,
      Evaluates program.core entry.scope (tagWrite word.source.function.id) .unit middle ∧
      Evaluates program.core middle (payloadWrite word.source.function.id) .unit written ∧
      (Assertion.localPointsTo 8 entry.cursorCell (some (.signed .i32 entry.outcome.position))).holds written ∧
      written.cellEntry? entry.outputCell = some {
        id := entry.outputCell, value := some (.array (signedI32Values entry.outcome.contents)) } ∧
      CellEffect (CellSet.union (CellSet.singleton entry.outputCell) (CellSet.singleton entry.cursorCell)) entry.scope written := by
  obtain ⟨_, _, _, scopeWF, tag, payload, _⟩ := initialize_child program.core entry.record entry.child entry.index
    entry.wellFormed entry.input entry.stored entry.found entry.recordRead entry.indexRead entry.sizeFit
  have rowWF : StateWellFormed (slotState before entry.record entry.index) := bindLocal_preserves_well_formed _ _ _ entry.wellFormed
  have startWF : StateWellFormed (tagState before entry.record entry.index entry.child) := bindLocal_preserves_well_formed _ _ _ rowWF
  have keep {id : VarId} {value : Value} (n9 : (14 : VarId) ≠ id) (n10 : (15 : VarId) ≠ id)
      (n11 : (16 : VarId) ≠ id) (found : before.local? id = some value) : entry.scope.local? id = some value :=
    (bindLocal_preserves_other_local startWF n11).trans
      ((bindLocal_preserves_other_local rowWF n10).trans
        ((bindLocal_preserves_other_local entry.wellFormed n9).trans found))
  have cursorRow := bindLocal_preserves_localPointsTo_of_ne before 14 8
    (.signed .i32 (entry.record.offset + 4 + entry.index * 3 : Nat)) entry.cursorCell _ entry.wellFormed (by decide) entry.cursor
  have cursorStart := bindLocal_preserves_localPointsTo_of_ne (slotState before entry.record entry.index) 15 8
    (.signed .i32 (childTag entry.child.reference)) entry.cursorCell _ rowWF (by decide) cursorRow
  have cursorScope := bindLocal_preserves_localPointsTo_of_ne (tagState before entry.record entry.index entry.child) 16 8
    (.signed .i32 (childPayload entry.child.reference)) entry.cursorCell _ startWF (by decide) cursorStart
  have backingRow := ((bindLocal_effect before 14 (.signed .i32 (entry.record.offset + 4 + entry.index * 3 : Nat))).oldCells entry.outputCell
    (StateWellFormed.cell_lt_next_of_entry entry.wellFormed entry.backing) (by simp [CellSet.empty])).trans entry.backing
  have backingStart := ((bindLocal_effect (slotState before entry.record entry.index) 15 (.signed .i32 (childTag entry.child.reference))).oldCells entry.outputCell
    (StateWellFormed.cell_lt_next_of_entry rowWF backingRow) (by simp [CellSet.empty])).trans backingRow
  have backingScope := ((bindLocal_effect (tagState before entry.record entry.index entry.child) 16 (.signed .i32 (childPayload entry.child.reference))).oldCells entry.outputCell
    (StateWellFormed.cell_lt_next_of_entry startWF backingStart) (by simp [CellSet.empty])).trans backingStart
  have stable : ∀ id ∈ [5, 6, 16], ∀ cell, entry.scope.cellId? id = some cell → cell ≠ entry.cursorCell := by
    intro id member cell binding
    simp only [List.mem_cons, List.not_mem_nil, or_false] at member
    rcases member with rfl | rfl | rfl
    · apply entry.stable 5 (by simp) cell
      simpa only [scope, childState, tagState, slotState,
        bindLocal_preserves_other_cellId _ 16 5 _ (by decide),
        bindLocal_preserves_other_cellId _ 15 5 _ (by decide),
        bindLocal_preserves_other_cellId _ 14 5 _ (by decide)] using binding
    · apply entry.stable 6 (by simp) cell
      simpa only [scope, childState, tagState, slotState,
        bindLocal_preserves_other_cellId _ 16 6 _ (by decide),
        bindLocal_preserves_other_cellId _ 15 6 _ (by decide),
        bindLocal_preserves_other_cellId _ 14 6 _ (by decide)] using binding
    · have fresh := (bindLocal_owns_fresh (tagState before entry.record entry.index entry.child) 16 (.signed .i32 (childPayload entry.child.reference)) startWF).1
      have selected : cell = (tagState before entry.record entry.index entry.child).nextCell := Option.some.inj (binding.symm.trans fresh)
      have old := StateWellFormed.cell_lt_next_of_local_binding 8 entry.cursorCell entry.wellFormed entry.cursor.1
      rw [selected]
      exact Ne.symm (Nat.ne_of_lt (Nat.lt_trans (Nat.lt_trans old (Nat.lt_succ_self _)) (Nat.lt_succ_self _)))
  have fields := child_fields entry.child entry.count entry.node entry.countFit entry.nodeFit entry.linked entry.tokenBound
  simp only [Int.ofNat_eq_natCast] at fields
  obtain ⟨middle, written, firstRun, secondRun, cursor, backing, effect⟩ := write_child word
    (childTag entry.child.reference).toNat (childPayload entry.child.reference).toNat entry.capacity entry.position
    scopeWF fields.2.2.1 fields.2.2.2 entry.room entry.capacityFit cursorScope
    (keep (by decide) (by decide) (by decide) entry.outputRead)
    (keep (by decide) (by decide) (by decide) entry.capacityRead)
    (by simpa only [fields.1] using tag) (by simpa only [fields.2.1] using payload) stable backingScope
  exact ⟨middle, written, firstRun, secondRun, cursor, backing, effect⟩

theorem ChildEntry.validate (entry : ChildEntry before) (program : Program)
    (tokenConstant : ParserTreeSource.constantValue program tokenTag 1)
    (stateConstant : ParserTreeSource.constantValue program stateTag 2)
    (tailRun : Executes program entry.scope continuation completion after) :
    Executes program entry.scope (validateThen tokenTag stateTag continuation) completion after := by
  obtain ⟨_, _, _, _, tag, payload, _⟩ := initialize_child program entry.record entry.child entry.index
    entry.wellFormed entry.input entry.stored entry.found entry.recordRead entry.indexRead entry.sizeFit
  have slotWF : StateWellFormed (slotState before entry.record entry.index) := bindLocal_preserves_well_formed _ _ _ entry.wellFormed
  have tagWF : StateWellFormed (tagState before entry.record entry.index entry.child) := bindLocal_preserves_well_formed _ _ _ slotWF
  have keep {id : VarId} {value : Value} (n14 : (14 : VarId) ≠ id) (n15 : (15 : VarId) ≠ id)
      (n16 : (16 : VarId) ≠ id) (found : before.local? id = some value) : entry.scope.local? id = some value :=
    (bindLocal_preserves_other_local tagWF n16).trans
      ((bindLocal_preserves_other_local slotWF n15).trans
        ((bindLocal_preserves_other_local entry.wellFormed n14).trans found))
  exact validate_child program entry.child entry.count entry.node tokenConstant stateConstant tag payload
    (keep (by decide) (by decide) (by decide) entry.countRead)
    (keep (by decide) (by decide) (by decide) entry.nodeRead) entry.linked entry.tokenBound tailRun

end Lanius.Extraction.CompactOutput.Nodes
