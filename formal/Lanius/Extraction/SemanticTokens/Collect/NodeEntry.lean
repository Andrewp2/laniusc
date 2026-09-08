import Lanius.Extraction.SemanticTokens.Collect.NodeLoop

namespace Lanius.Extraction.SemanticTokens.Collect

open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.Compiler.Parser ParserTreeLayout

/-- Ordinary inputs after assignment initialization, before `let node = 0`.
Fresh node/record/child cells and all loop invariants are derived below. -/
structure NodeEntry (data : TraversalData) (before : State) : Prop where
  wellFormed : StateWellFormed before
  grammar : data.grammar.Owns data.grammarCell before
  kinds : I32PrefixLocal before 2 data.kindsCell (data.tokens.map (Int.ofNat ∘ Token.kind))
  records : I32PrefixLocal before 4 data.recordsCell (treeFrom 0 0 data.tree).words
  offsets : I32PrefixLocal before 6 data.offsetsCell ((treeFrom 0 0 data.tree).offsets.map Int.ofNat)
  output : before.local? 8 = some (.slice i32 data.outputCell [] 0 data.original.length)
  backing : before.cellEntry? data.outputCell = some {
    id := data.outputCell, value := some (.array (signedI32Values (initialized data.original (data.tokens.length * 2)))) }
  count : before.local? 3 = some (.signed .i32 data.tokens.length)
  wordLength : before.local? 5 = some (.signed .i32 (treeFrom 0 0 data.tree).words.length)
  nodeCount : before.local? 7 = some (.signed .i32 data.collection.records.length)
  kindCount : before.local? 10 = some (.signed .i32 data.grammar.grammar.grammar.n_kinds)
  canonicalOffset : before.local? 11 = some (.signed .i32 data.grammar.layout.canonicalKindsOffset)
  nodesFit : data.collection.records.length ≤ 2147483647
  separate : ∀ cell ∈ [data.grammarCell, data.kindsCell, data.recordsCell, data.offsetsCell], cell ≠ data.outputCell

def NodeEntry.memory {data : TraversalData} (entry : NodeEntry data before) : NodeMemory := {
  data
  nodeCell := before.nextCell
  nodesFit := entry.nodesFit
  distinct := Nat.ne_of_lt (StateWellFormed.cell_lt_next_of_entry entry.wellFormed entry.backing)
  inputs := by
    intro cell member
    refine ⟨entry.separate cell member, ?_⟩
    apply Nat.ne_of_lt
    simp only [List.mem_cons, List.not_mem_nil, or_false] at member
    rcases member with rfl | rfl | rfl | rfl
    · exact StateWellFormed.cell_lt_next_of_entry entry.wellFormed entry.grammar.unused_backing
    · exact StateWellFormed.cell_lt_next_of_entry entry.wellFormed entry.kinds.unused_backing
    · exact StateWellFormed.cell_lt_next_of_entry entry.wellFormed entry.records.unused_backing
    · exact StateWellFormed.cell_lt_next_of_entry entry.wellFormed entry.offsets.unused_backing
}

theorem NodeEntry.invariant {data : TraversalData} (entry : NodeEntry data before) :
    NodeOwned entry.memory 0 (before.bindLocal 13 (.signed .i32 0)) := by
  have keep {id : VarId} {value : Value} (different : (13 : VarId) ≠ id)
      (found : before.local? id = some value) : (before.bindLocal 13 (.signed .i32 0)).local? id = some value :=
    (bindLocal_preserves_other_local entry.wellFormed different).trans found
  have effect := bindLocal_effect before 13 (.signed .i32 0)
  refine ⟨bindLocal_preserves_well_formed _ _ _ entry.wellFormed,
    entry.grammar.bindLocal entry.wellFormed 13 _ (by decide),
    entry.kinds.bindLocal entry.wellFormed 13 _ (by decide),
    entry.records.bindLocal entry.wellFormed 13 _ (by decide),
    entry.offsets.bindLocal entry.wellFormed 13 _ (by decide),
    keep (by decide) entry.output, ?_, bindLocal_owns_fresh _ _ _ entry.wellFormed,
    keep (by decide) entry.count, keep (by decide) entry.wordLength, keep (by decide) entry.nodeCount,
    keep (by decide) entry.kindCount, keep (by decide) entry.canonicalOffset, ?_⟩
  · have backing := (effect.oldCells data.outputCell
      (StateWellFormed.cell_lt_next_of_entry entry.wellFormed entry.backing) (by simp [CellSet.empty])).trans entry.backing
    simpa only [memory, priorUses, List.take_zero, List.flatMap_nil, written, writeUses, List.foldl_nil] using backing
  · intro id member cell binding changed
    have different : (13 : VarId) ≠ id := by
      simp only [nodeStableIds, List.mem_cons, List.not_mem_nil, or_false] at member
      dsimp only [VarId] at member ⊢
      omega
    have original : before.cellId? id = some cell := by
      simpa only [bindLocal_preserves_other_cellId before 13 id (.signed .i32 0) different] using binding
    rcases changed with output | node
    · have distinct : cell ≠ data.outputCell := by
        simp only [nodeStableIds, List.mem_cons, List.not_mem_nil, or_false] at member
        rcases member with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl
        · exact local_cell_ne_of_distinct_value entry.grammar.unused_local entry.backing (by intro same; cases same) original
        · exact local_cell_ne_of_distinct_value entry.kinds.unused_local entry.backing (by intro same; cases same) original
        · exact local_cell_ne_of_distinct_value entry.count entry.backing (by intro same; cases same) original
        · exact local_cell_ne_of_distinct_value entry.records.unused_local entry.backing (by intro same; cases same) original
        · exact local_cell_ne_of_distinct_value entry.wordLength entry.backing (by intro same; cases same) original
        · exact local_cell_ne_of_distinct_value entry.offsets.unused_local entry.backing (by intro same; cases same) original
        · exact local_cell_ne_of_distinct_value entry.nodeCount entry.backing (by intro same; cases same) original
        · exact local_cell_ne_of_distinct_value entry.output entry.backing (by intro same; cases same) original
        · exact local_cell_ne_of_distinct_value entry.kindCount entry.backing (by intro same; cases same) original
        · exact local_cell_ne_of_distinct_value entry.canonicalOffset entry.backing (by intro same; cases same) original
      exact distinct output
    · exact (Nat.ne_of_lt (StateWellFormed.cell_lt_next_of_local_binding id cell entry.wellFormed original)) node

/-- Execute all records from initialized caller storage, deriving every loop
invariant and temporary-cell separation internally. The source's node scope
stays live for the following final-validation phase. -/
theorem NodeEntry.execute {data : TraversalData} (entry : NodeEntry data before)
    (program : Program) (symbols : Symbols)
    (tokenTag : ParserTreeSource.constantValue program symbols.childToken 1)
    (stateTag : ParserTreeSource.constantValue program symbols.childState 2) :
    ∃ after, Executes program (before.bindLocal 13 (.signed .i32 0)) (nodeLoop symbols) .next after ∧
      NodeOwned entry.memory data.collection.records.length after ∧
      CellEffect entry.memory.writes (before.bindLocal 13 (.signed .i32 0)) after :=
  node_loop program symbols tokenTag stateTag entry.invariant (by omega)

end Lanius.Extraction.SemanticTokens.Collect
