import Lanius.Extraction.CompactOutput.Assignments.Success
import Lanius.Extraction.CompactOutput.Assignments.Failure

namespace Lanius.Extraction.CompactOutput.Assignments

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Extraction.SemanticTokens

structure Memory where
  assignments : List Assignment
  inputCell : CellId
  outputCell : CellId
  cursorCell : CellId
  indexCell : CellId
  capacity : Nat
  capacityFit : capacity ≤ 2147483647
  sizeFit : 2 * assignments.length ≤ 2147483647
  fields : ∀ assignment ∈ assignments, assignment.first ≤ 2147483647 ∧
    -1 ≤ secondWord assignment ∧ secondWord assignment < 2147483647
  distinctLocals : cursorCell ≠ indexCell
  distinctBuffers : outputCell ≠ inputCell

def Memory.writes (memory : Memory) : CellSet :=
  CellSet.union (CellSet.union (CellSet.singleton memory.outputCell) (CellSet.singleton memory.cursorCell))
    (CellSet.singleton memory.indexCell)

structure Owned (memory : Memory) (index : Nat) (position : Int) (contents : List Int) (state : State) : Prop where
  wellFormed : StateWellFormed state
  bound : index ≤ memory.assignments.length
  room : memory.capacity ≤ contents.length
  input : I32PrefixLocal state 0 memory.inputCell (memory.assignments.flatMap Assignment.words)
  count : state.local? 2 = some (.signed .i32 memory.assignments.length)
  output : state.local? 3 = some (.slice i32 memory.outputCell [] 0 contents.length)
  capacity : state.local? 4 = some (.signed .i32 memory.capacity)
  backing : state.cellEntry? memory.outputCell = some {
    id := memory.outputCell, value := some (.array (signedI32Values contents)) }
  cursor : (Assertion.localPointsTo 6 memory.cursorCell (some (.signed .i32 position))).holds state
  indexOwned : (Assertion.localPointsTo 7 memory.indexCell (some (.signed .i32 index))).holds state
  stable : ∀ id ∈ [0, 2, 3, 4], ∀ cell, state.cellId? id = some cell →
    cell ≠ memory.cursorCell ∧ cell ≠ memory.indexCell

def Owned.entry (owned : Owned memory index position contents before)
    (bound : index < memory.assignments.length) : Entry before := {
  assignments := memory.assignments, index, inputCell := memory.inputCell
  outputCell := memory.outputCell, cursorCell := memory.cursorCell, position
  capacity := memory.capacity, contents, wellFormed := owned.wellFormed, input := owned.input
  indexRead := Assertion.localPointsTo_local _ _ _ _ owned.indexOwned
  bound, sizeFit := memory.sizeFit
  firstFit := (memory.fields _ (List.getElem_mem bound)).1
  lower := (memory.fields _ (List.getElem_mem bound)).2.1
  upper := (memory.fields _ (List.getElem_mem bound)).2.2
  room := owned.room, capacityFit := memory.capacityFit, cursor := owned.cursor
  outputRead := owned.output, capacityRead := owned.capacity
  stable := fun id member cell binding => (owned.stable id (by
    simp only [List.mem_cons, List.not_mem_nil, or_false] at member ⊢
    rcases member with rfl | rfl <;> simp) cell binding).1
  backing := owned.backing
}

theorem Owned.transition {nextIndex : Nat} {nextCursor : Int}
    (owned : Owned memory index position contents before)
    (effect : CellEffect memory.writes before after)
    (bound : nextIndex ≤ memory.assignments.length) (size : updated.length = contents.length)
    (backing : after.cellEntry? memory.outputCell = some {
      id := memory.outputCell, value := some (.array (signedI32Values updated)) })
    (cursor : (Assertion.localPointsTo 6 memory.cursorCell (some (.signed .i32 nextCursor))).holds after)
    (indexOwned : (Assertion.localPointsTo 7 memory.indexCell (some (.signed .i32 nextIndex))).holds after) :
    Owned memory nextIndex nextCursor updated after := by
  have keep {id : VarId} {value : Value} (member : id ∈ [0, 2, 3, 4])
      (found : before.local? id = some value) (different : value ≠ .array (signedI32Values contents)) :
      after.local? id = some value := by
    apply effect.preserves_local owned.wellFormed found
    intro cell binding changed
    rcases changed with (output | cursor) | index
    · exact local_cell_ne_of_distinct_value found owned.backing different binding output
    · exact (owned.stable id member cell binding).1 cursor
    · exact (owned.stable id member cell binding).2 index
  have input : I32PrefixLocal after 0 memory.inputCell (memory.assignments.flatMap Assignment.words) := by
    apply owned.input.transport
    · intro capacity found
      exact keep (by simp) found (by intro same; cases same)
    · intro stored found
      apply effect.preserves_entry owned.wellFormed found
      intro changed
      rcases changed with (output | cursor) | index
      · exact memory.distinctBuffers output.symm
      · obtain ⟨unused, _, old⟩ := owned.input.exists_unused
        rw [cursor, owned.cursor.2] at old
        cases old
      · obtain ⟨unused, _, old⟩ := owned.input.exists_unused
        rw [index, owned.indexOwned.2] at old
        cases old
  refine ⟨effect.wellFormed, bound, by rw [size]; exact owned.room, input,
    keep (by simp) owned.count (by intro same; cases same), ?_,
    keep (by simp) owned.capacity (by intro same; cases same), backing, cursor, indexOwned, ?_⟩
  · simpa only [size] using keep (by simp) owned.output (by intro same; cases same)
  · intro id member cell binding
    exact owned.stable id member cell (by simpa only [State.cellId?, effect.locals] using binding)

theorem Owned.condition (owned : Owned memory index position contents state) (program : Program) :
    Evaluates program state condition (.boolean (decide (index ≠ memory.assignments.length))) state := by
  apply evaluatesEagerBinary (by decide) (by decide)
    (local_evaluates program (Assertion.localPointsTo_local _ _ _ _ owned.indexOwned))
    (local_evaluates program owned.count)
  simp only [evalBinaryValue, scalarEqual, beq_self_eq_true, if_true,
    Except.ok.injEq, Value.boolean.injEq, decide_not]
  apply Bool.eq_iff_iff.mpr
  simp [Int.ofNat_inj]

end Lanius.Extraction.CompactOutput.Assignments
