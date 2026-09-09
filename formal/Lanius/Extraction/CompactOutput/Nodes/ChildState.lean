import Lanius.Extraction.CompactOutput.Nodes.Success
import Lanius.Extraction.CompactOutput.Nodes.Failure

namespace Lanius.Extraction.CompactOutput.Nodes

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Compiler.Parser ParserTreeLayout Lanius.Extraction.SemanticTokens

structure ChildMemory where
  record : RecordVisit
  words : List Int
  records : List RecordVisit
  node : Nat
  count : Nat
  inputCell : CellId
  outputCell : CellId
  cursorCell : CellId
  indexCell : CellId
  capacity : Nat
  stored : record.Stored 0 words
  sizeFit : words.length ≤ 2147483647
  countFit : count ≤ 2147483647
  nodeFit : node ≤ 2147483647
  capacityFit : capacity ≤ 2147483647
  linked : ∀ child ∈ record.children, child.Linked 0 records node
  tokenBound : ∀ child ∈ record.children, ∀ use, child = .token use → use.token < count
  distinctLocals : cursorCell ≠ indexCell
  distinctBuffers : outputCell ≠ inputCell

def ChildMemory.writes (memory : ChildMemory) : CellSet :=
  CellSet.union (CellSet.union (CellSet.singleton memory.outputCell) (CellSet.singleton memory.cursorCell))
    (CellSet.singleton memory.indexCell)

structure ChildOwned (memory : ChildMemory) (index : Nat) (position : Int)
    (contents : List Int) (state : State) : Prop where
  wellFormed : StateWellFormed state
  bound : index ≤ memory.record.children.length
  room : memory.capacity ≤ contents.length
  input : I32PrefixLocal state 0 memory.inputCell memory.words
  count : state.local? 4 = some (.signed .i32 memory.count)
  node : state.local? 9 = some (.signed .i32 memory.node)
  record : state.local? 10 = some (.signed .i32 memory.record.offset)
  children : state.local? 12 = some (.signed .i32 memory.record.children.length)
  output : state.local? 5 = some (.slice i32 memory.outputCell [] 0 contents.length)
  capacity : state.local? 6 = some (.signed .i32 memory.capacity)
  backing : state.cellEntry? memory.outputCell = some {
    id := memory.outputCell, value := some (.array (signedI32Values contents)) }
  cursor : (Assertion.localPointsTo 8 memory.cursorCell (some (.signed .i32 position))).holds state
  indexOwned : (Assertion.localPointsTo 13 memory.indexCell (some (.signed .i32 index))).holds state
  stable : ∀ id ∈ [0, 4, 5, 6, 9, 10, 12], ∀ cell, state.cellId? id = some cell →
    cell ≠ memory.cursorCell ∧ cell ≠ memory.indexCell

def ChildOwned.entry (owned : ChildOwned memory index position contents before)
    (bound : index < memory.record.children.length) : ChildEntry before := {
  record := memory.record, child := memory.record.children[index], index
  words := memory.words, records := memory.records, node := memory.node, count := memory.count
  inputCell := memory.inputCell, outputCell := memory.outputCell, cursorCell := memory.cursorCell
  position, capacity := memory.capacity, contents, wellFormed := owned.wellFormed
  input := owned.input, stored := memory.stored, found := by simp [bound]
  recordRead := owned.record, indexRead := Assertion.localPointsTo_local _ _ _ _ owned.indexOwned
  sizeFit := memory.sizeFit, countFit := memory.countFit, nodeFit := memory.nodeFit
  linked := memory.linked _ (List.getElem_mem bound)
  tokenBound := memory.tokenBound _ (List.getElem_mem bound)
  countRead := owned.count, nodeRead := owned.node, room := owned.room
  capacityFit := memory.capacityFit, cursor := owned.cursor, outputRead := owned.output
  capacityRead := owned.capacity, backing := owned.backing
  stable := fun id member cell binding => (owned.stable id (by
    simp only [List.mem_cons, List.not_mem_nil, or_false] at member ⊢
    rcases member with rfl | rfl <;> simp) cell binding).1
}

theorem ChildOwned.transition {nextIndex : Nat} {nextCursor : Int}
    (owned : ChildOwned memory index position contents before)
    (effect : CellEffect memory.writes before after)
    (bound : nextIndex ≤ memory.record.children.length) (size : updated.length = contents.length)
    (backing : after.cellEntry? memory.outputCell = some {
      id := memory.outputCell, value := some (.array (signedI32Values updated)) })
    (cursor : (Assertion.localPointsTo 8 memory.cursorCell (some (.signed .i32 nextCursor))).holds after)
    (indexOwned : (Assertion.localPointsTo 13 memory.indexCell (some (.signed .i32 nextIndex))).holds after) :
    ChildOwned memory nextIndex nextCursor updated after := by
  have keep {id : VarId} {value : Value} (member : id ∈ [0, 4, 5, 6, 9, 10, 12])
      (found : before.local? id = some value) (different : value ≠ .array (signedI32Values contents)) :
      after.local? id = some value := by
    apply effect.preserves_local owned.wellFormed found
    intro cell binding changed
    rcases changed with (output | cursor) | index
    · exact local_cell_ne_of_distinct_value found owned.backing different binding output
    · exact (owned.stable id member cell binding).1 cursor
    · exact (owned.stable id member cell binding).2 index
  have input : I32PrefixLocal after 0 memory.inputCell memory.words := by
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
    keep (by simp) owned.count (by intro same; cases same),
    keep (by simp) owned.node (by intro same; cases same),
    keep (by simp) owned.record (by intro same; cases same),
    keep (by simp) owned.children (by intro same; cases same), ?_,
    keep (by simp) owned.capacity (by intro same; cases same), backing, cursor, indexOwned, ?_⟩
  · simpa only [size] using keep (by simp) owned.output (by intro same; cases same)
  · intro id member cell binding
    exact owned.stable id member cell (by simpa only [State.cellId?, effect.locals] using binding)

theorem ChildOwned.condition (owned : ChildOwned memory index position contents state) (program : Program) :
    Evaluates program state childCondition (.boolean (decide (index ≠ memory.record.children.length))) state := by
  apply evaluatesEagerBinary (by decide) (by decide)
    (local_evaluates program (Assertion.localPointsTo_local _ _ _ _ owned.indexOwned))
    (local_evaluates program owned.children)
  simp only [evalBinaryValue, scalarEqual, beq_self_eq_true, if_true,
    Except.ok.injEq, Value.boolean.injEq, decide_not]
  apply Bool.eq_iff_iff.mpr
  simp [Int.ofNat_inj]

end Lanius.Extraction.CompactOutput.Nodes
