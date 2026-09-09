import Lanius.Extraction.CompactOutput.Nodes.HeaderWrite
import Lanius.Extraction.CompactOutput.Nodes.ChildLoop

namespace Lanius.Extraction.CompactOutput.Nodes

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Extraction.SemanticTokens

structure References (memory : HeaderMemory) where
  records : List RecordVisit
  node : Nat
  count : Nat
  nodeFit : node ≤ 2147483647
  countFit : count ≤ 2147483647
  linked : ∀ child ∈ memory.record.children, child.Linked 0 records node
  tokenBound : ∀ child ∈ memory.record.children, ∀ use, child = .token use → use.token < count

structure ReferencesOwned (refs : References memory) (state : State) : Prop where
  count : state.local? 4 = some (.signed .i32 refs.count)
  node : state.local? 9 = some (.signed .i32 refs.node)
  stable : ∀ id ∈ [4, 9], ∀ cell, state.cellId? id = some cell → cell ≠ memory.cursorCell

theorem ReferencesOwned.preserve {memory : HeaderMemory} {refs : References memory}
    (refsOwned : ReferencesOwned refs before)
    (owned : HeaderOwned memory position contents before)
    (effect : CellEffect memory.writes before after) : ReferencesOwned refs after := by
  have keep {id : VarId} {value : Value} (member : id ∈ [4, 9])
      (found : before.local? id = some value) (different : value ≠ .array (signedI32Values contents)) :
      after.local? id = some value := by
    apply effect.preserves_local owned.wellFormed found
    intro cell binding changed
    rcases changed with output | cursor
    · exact local_cell_ne_of_distinct_value found owned.backing different binding output
    · exact refsOwned.stable id member cell binding cursor
  refine ⟨keep (by simp) refsOwned.count (by intro same; cases same),
    keep (by simp) refsOwned.node (by intro same; cases same), ?_⟩
  intro id member cell binding
  exact refsOwned.stable id member cell (by simpa only [State.cellId?, effect.locals] using binding)

def HeaderOwned.childMemory (owned : HeaderOwned memory position contents before)
    (refs : References memory) : ChildMemory := {
  record := memory.record, words := memory.words, records := refs.records
  node := refs.node, count := refs.count, inputCell := memory.inputCell
  outputCell := memory.outputCell, cursorCell := memory.cursorCell, indexCell := before.nextCell
  capacity := memory.capacity, stored := memory.stored, sizeFit := memory.sizeFit
  countFit := refs.countFit, nodeFit := refs.nodeFit, capacityFit := memory.capacityFit
  linked := refs.linked, tokenBound := refs.tokenBound, distinctBuffers := memory.distinctBuffers
  distinctLocals := Nat.ne_of_lt (StateWellFormed.cell_lt_next_of_entry owned.wellFormed owned.cursor.2)
}

/-- The real `let child = 0` establishes the entire inner-loop invariant;
fresh-cell separation is derived from well-formedness. -/
theorem HeaderOwned.start_children (owned : HeaderOwned memory position contents before)
    (refsOwned : ReferencesOwned refs before) :
    ChildOwned (owned.childMemory refs) 0 position contents (before.bindLocal 13 (.signed .i32 0)) := by
  have keep {id : VarId} {value : Value} (different : (13 : VarId) ≠ id)
      (found : before.local? id = some value) :
      (before.bindLocal 13 (.signed .i32 0)).local? id = some value :=
    (bindLocal_preserves_other_local owned.wellFormed different).trans found
  have backing := ((bindLocal_effect before 13 (.signed .i32 0)).oldCells memory.outputCell
    (StateWellFormed.cell_lt_next_of_entry owned.wellFormed owned.backing) (by simp [CellSet.empty])).trans owned.backing
  refine ⟨bindLocal_preserves_well_formed _ _ _ owned.wellFormed, Nat.zero_le _, owned.room,
    owned.input.bindLocal owned.wellFormed 13 (.signed .i32 0) (by decide),
    keep (by decide) refsOwned.count, keep (by decide) refsOwned.node,
    keep (by decide) owned.record, keep (by decide) owned.children,
    keep (by decide) owned.output, keep (by decide) owned.capacity, backing,
    bindLocal_preserves_localPointsTo_of_ne before 13 8 (.signed .i32 0) memory.cursorCell _
      owned.wellFormed (by decide) owned.cursor,
    bindLocal_owns_fresh before 13 (.signed .i32 0) owned.wellFormed, ?_⟩
  intro id member cell binding
  have different : (13 : VarId) ≠ id := by
    simp only [List.mem_cons, List.not_mem_nil, or_false] at member
    rcases member with rfl | rfl | rfl | rfl | rfl | rfl | rfl <;> decide
  have original : before.cellId? id = some cell := by
    simpa only [bindLocal_preserves_other_cellId _ 13 id _ different] using binding
  constructor
  · by_cases special : id ∈ [4, 9]
    · exact refsOwned.stable id special cell original
    · apply owned.stable id _ cell original
      simp only [List.mem_cons, List.not_mem_nil, or_false] at member special ⊢
      rcases member with rfl | rfl | rfl | rfl | rfl | rfl | rfl <;> simp_all
  · exact Nat.ne_of_lt (StateWellFormed.cell_lt_next_of_local_binding id cell owned.wellFormed original)

end Lanius.Extraction.CompactOutput.Nodes
