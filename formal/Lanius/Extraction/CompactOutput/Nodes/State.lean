import Lanius.Extraction.CompactOutput.Nodes.Step

namespace Lanius.Extraction.CompactOutput.Nodes

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Extraction.SemanticTokens

structure Memory where
  records : List RecordVisit
  words : List Int
  inputLength : Nat
  count : Nat
  inputCell : CellId
  offsetCell : CellId
  outputCell : CellId
  cursorCell : CellId
  nodeCell : CellId
  capacity : Nat
  inputRoom : words.length ≤ inputLength
  inputFit : inputLength ≤ 2147483647
  countFit : count ≤ 2147483647
  nodesFit : records.length ≤ 2147483647
  capacityFit : capacity ≤ 2147483647
  stored : ∀ record ∈ records, record.Stored 0 words
  fields : ∀ record ∈ records, record.production ≤ 2147483647 ∧ record.start ≤ 2147483647 ∧ record.finish ≤ 2147483647
  linked : ∀ (index : Nat) (record : RecordVisit), records[index]? = some record → ∀ child ∈ record.children, child.Linked 0 records index
  tokenBound : ∀ record ∈ records, ∀ child ∈ record.children, ∀ use, child = .token use → use.token < count
  distinctLocals : cursorCell ≠ nodeCell
  distinctInput : outputCell ≠ inputCell
  distinctOffsets : outputCell ≠ offsetCell

def Memory.writes (memory : Memory) : CellSet :=
  CellSet.union (CellSet.union (CellSet.singleton memory.outputCell) (CellSet.singleton memory.cursorCell))
    (CellSet.singleton memory.nodeCell)

structure Owned (memory : Memory) (index : Nat) (position : Int) (contents : List Int) (state : State) : Prop where
  wellFormed : StateWellFormed state
  bound : index ≤ memory.records.length
  room : memory.capacity ≤ contents.length
  input : I32PrefixLocal state 0 memory.inputCell memory.words
  offsets : I32PrefixLocal state 2 memory.offsetCell (memory.records.map (fun record => (record.offset : Int)))
  lengthRead : state.local? 1 = some (.signed .i32 memory.inputLength)
  nodes : state.local? 3 = some (.signed .i32 memory.records.length)
  count : state.local? 4 = some (.signed .i32 memory.count)
  output : state.local? 5 = some (.slice i32 memory.outputCell [] 0 contents.length)
  capacity : state.local? 6 = some (.signed .i32 memory.capacity)
  backing : state.cellEntry? memory.outputCell = some {
    id := memory.outputCell, value := some (.array (signedI32Values contents)) }
  cursor : (Assertion.localPointsTo 8 memory.cursorCell (some (.signed .i32 position))).holds state
  node : (Assertion.localPointsTo 9 memory.nodeCell (some (.signed .i32 index))).holds state
  stable : ∀ id ∈ [0, 1, 2, 3, 4, 5, 6], ∀ cell, state.cellId? id = some cell →
    cell ≠ memory.cursorCell ∧ cell ≠ memory.nodeCell

def Owned.entry (owned : Owned memory index position contents before)
    (bound : index < memory.records.length) : RecordEntry before := {
  memory := {
    record := memory.records[index], words := memory.words, inputCell := memory.inputCell
    outputCell := memory.outputCell, cursorCell := memory.cursorCell, capacity := memory.capacity
    stored := memory.stored _ (List.getElem_mem bound), sizeFit := Nat.le_trans memory.inputRoom memory.inputFit
    capacityFit := memory.capacityFit, productionFit := (memory.fields _ (List.getElem_mem bound)).1
    startFit := (memory.fields _ (List.getElem_mem bound)).2.1
    finishFit := (memory.fields _ (List.getElem_mem bound)).2.2, distinctBuffers := memory.distinctInput }
  refs := {
    records := memory.records, node := index, count := memory.count
    nodeFit := Nat.le_trans owned.bound memory.nodesFit, countFit := memory.countFit
    linked := memory.linked index _ (by simp [bound])
    tokenBound := memory.tokenBound _ (List.getElem_mem bound) }
  nodeCell := memory.nodeCell, offsetCell := memory.offsetCell, position, contents
  inputLength := memory.inputLength, wellFormed := owned.wellFormed, input := owned.input, offsets := owned.offsets
  found := by simp [bound]
  inputRoom := memory.inputRoom, inputFit := memory.inputFit, lengthRead := owned.lengthRead
  refsOwned := {
    count := owned.count, node := Assertion.localPointsTo_local _ _ _ _ owned.node
    stable := fun id member cell binding => by
      rcases (by simpa using member : id = 4 ∨ id = 9) with rfl | rfl
      · exact (owned.stable 4 (by simp) cell binding).1
      · have same := Option.some.inj (binding.symm.trans owned.node.1)
        exact same ▸ Ne.symm memory.distinctLocals }
  room := owned.room, output := owned.output, capacity := owned.capacity, cursor := owned.cursor
  node := owned.node, backing := owned.backing
  stable := fun id member cell binding => (owned.stable id (by
    simp only [List.mem_cons, List.not_mem_nil, or_false] at member ⊢
    rcases member with rfl | rfl | rfl <;> simp) cell binding).1
  distinct := memory.distinctLocals, nextFit := by change index + 1 ≤ 2147483647; have := memory.nodesFit; omega
}

theorem Owned.transition {nextIndex : Nat} {nextCursor : Int}
    (owned : Owned memory index position contents before)
    (effect : CellEffect memory.writes before after)
    (bound : nextIndex ≤ memory.records.length) (size : updated.length = contents.length)
    (backing : after.cellEntry? memory.outputCell = some {
      id := memory.outputCell, value := some (.array (signedI32Values updated)) })
    (cursor : (Assertion.localPointsTo 8 memory.cursorCell (some (.signed .i32 nextCursor))).holds after)
    (node : (Assertion.localPointsTo 9 memory.nodeCell (some (.signed .i32 nextIndex))).holds after) :
    Owned memory nextIndex nextCursor updated after := by
  have keep {id : VarId} {value : Value} (member : id ∈ [0, 1, 2, 3, 4, 5, 6])
      (found : before.local? id = some value) (different : value ≠ .array (signedI32Values contents)) :
      after.local? id = some value := by
    apply effect.preserves_local owned.wellFormed found
    intro cell binding changed
    rcases changed with (output | cursor) | index
    · exact local_cell_ne_of_distinct_value found owned.backing different binding output
    · exact (owned.stable id member cell binding).1 cursor
    · exact (owned.stable id member cell binding).2 index
  have keepInput {id : VarId} {cell : CellId} {values : List Int}
      (member : id ∈ [0, 1, 2, 3, 4, 5, 6]) (input : I32PrefixLocal before id cell values)
      (separate : memory.outputCell ≠ cell) : I32PrefixLocal after id cell values := by
    apply input.transport
    · intro capacity found
      exact keep member found (by intro same; cases same)
    · intro stored found
      apply effect.preserves_entry owned.wellFormed found
      intro changed
      rcases changed with (output | cursor) | index
      · exact separate output.symm
      · obtain ⟨unused, _, old⟩ := input.exists_unused
        rw [cursor, owned.cursor.2] at old
        cases old
      · obtain ⟨unused, _, old⟩ := input.exists_unused
        rw [index, owned.node.2] at old
        cases old
  refine ⟨effect.wellFormed, bound, by rw [size]; exact owned.room,
    keepInput (by simp) owned.input memory.distinctInput,
    keepInput (by simp) owned.offsets memory.distinctOffsets,
    keep (by simp) owned.lengthRead (by intro same; cases same),
    keep (by simp) owned.nodes (by intro same; cases same),
    keep (by simp) owned.count (by intro same; cases same), ?_,
    keep (by simp) owned.capacity (by intro same; cases same), backing, cursor, node, ?_⟩
  · simpa only [size] using keep (by simp) owned.output (by intro same; cases same)
  · intro id member cell binding
    exact owned.stable id member cell (by simpa only [State.cellId?, effect.locals] using binding)

theorem Owned.condition (owned : Owned memory index position contents state) (program : Program) :
    Evaluates program state condition (.boolean (decide (index ≠ memory.records.length))) state := by
  apply evaluatesEagerBinary (by decide) (by decide)
    (local_evaluates program (Assertion.localPointsTo_local _ _ _ _ owned.node))
    (local_evaluates program owned.nodes)
  simp only [evalBinaryValue, scalarEqual, beq_self_eq_true, if_true,
    Except.ok.injEq, Value.boolean.injEq, decide_not]
  apply Bool.eq_iff_iff.mpr
  simp [Int.ofNat_inj]

end Lanius.Extraction.CompactOutput.Nodes
