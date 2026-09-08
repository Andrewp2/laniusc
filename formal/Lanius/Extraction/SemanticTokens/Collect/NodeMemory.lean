import Lanius.Extraction.SemanticTokens.Collect.RecordChildren

namespace Lanius.Extraction.SemanticTokens.Collect

open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.Compiler.Parser ParserTreeLayout

structure NodeMemory where
  data : TraversalData
  nodeCell : CellId
  nodesFit : data.collection.records.length ≤ 2147483647
  distinct : data.outputCell ≠ nodeCell
  inputs : ∀ cell ∈ [data.grammarCell, data.kindsCell, data.recordsCell, data.offsetsCell],
    cell ≠ data.outputCell ∧ cell ≠ nodeCell

def NodeMemory.writes (memory : NodeMemory) : CellSet :=
  CellSet.union (CellSet.singleton memory.data.outputCell) (CellSet.singleton memory.nodeCell)

def nodeStableIds : List VarId := [0, 2, 3, 4, 5, 6, 7, 8, 10, 11]

/-- Outer-loop resources. The buffer contains exactly the assignments made
by earlier records, with the caller's original spare capacity retained. -/
structure NodeOwned (memory : NodeMemory) (index : Nat) (state : State) : Prop where
  wellFormed : StateWellFormed state
  grammar : memory.data.grammar.Owns memory.data.grammarCell state
  kinds : I32PrefixLocal state 2 memory.data.kindsCell (memory.data.tokens.map (Int.ofNat ∘ Token.kind))
  records : I32PrefixLocal state 4 memory.data.recordsCell (treeFrom 0 0 memory.data.tree).words
  offsets : I32PrefixLocal state 6 memory.data.offsetsCell ((treeFrom 0 0 memory.data.tree).offsets.map Int.ofNat)
  output : state.local? 8 = some (.slice i32 memory.data.outputCell [] 0 memory.data.original.length)
  backing : state.cellEntry? memory.data.outputCell = some {
    id := memory.data.outputCell,
    value := some (.array (signedI32Values (written memory.data.original memory.data.tokens.length
      (priorUses memory.data.collection.records index)))) }
  node : (Assertion.localPointsTo 13 memory.nodeCell (some (.signed .i32 index))).holds state
  count : state.local? 3 = some (.signed .i32 memory.data.tokens.length)
  wordLength : state.local? 5 = some (.signed .i32 (treeFrom 0 0 memory.data.tree).words.length)
  nodeCount : state.local? 7 = some (.signed .i32 memory.data.collection.records.length)
  kindCount : state.local? 10 = some (.signed .i32 memory.data.grammar.grammar.grammar.n_kinds)
  canonicalOffset : state.local? 11 = some (.signed .i32 memory.data.grammar.layout.canonicalKindsOffset)
  stable : ∀ id ∈ nodeStableIds, ∀ cell, state.cellId? id = some cell → ¬ memory.writes cell

theorem NodeOwned.bindLocal {memory : NodeMemory}
    (held : NodeOwned memory index before) (id : VarId) (value : Value) (high : 14 ≤ id) :
    NodeOwned memory index (before.bindLocal id value) := by
  have different (localId : VarId) (low : localId < 14) : id ≠ localId := by
    dsimp only [VarId] at high low ⊢
    omega
  have keep {localId : VarId} {current : Value} (low : localId < 14)
      (found : before.local? localId = some current) : (before.bindLocal id value).local? localId = some current :=
    (bindLocal_preserves_other_local held.wellFormed (different localId low)).trans found
  refine ⟨bindLocal_preserves_well_formed _ _ _ held.wellFormed,
    held.grammar.bindLocal held.wellFormed id value (different _ (by decide)),
    held.kinds.bindLocal held.wellFormed id value (different _ (by decide)),
    held.records.bindLocal held.wellFormed id value (different _ (by decide)),
    held.offsets.bindLocal held.wellFormed id value (different _ (by decide)),
    keep (by decide) held.output, ?_,
    bindLocal_preserves_localPointsTo_of_ne before id 13 value memory.nodeCell _ held.wellFormed (different _ (by decide)) held.node,
    keep (by decide) held.count, keep (by decide) held.wordLength, keep (by decide) held.nodeCount,
    keep (by decide) held.kindCount, keep (by decide) held.canonicalOffset, ?_⟩
  · exact ((bindLocal_effect before id value).oldCells memory.data.outputCell
      (StateWellFormed.cell_lt_next_of_entry held.wellFormed held.backing) (by simp [CellSet.empty])).trans held.backing
  · intro localId member cell found
    have low : localId < 14 := by
      simp only [nodeStableIds, List.mem_cons, List.not_mem_nil, or_false] at member
      dsimp only [VarId] at member ⊢
      omega
    apply held.stable localId member cell
    simpa only [bindLocal_preserves_other_cellId before id localId value (different localId low)] using found

theorem NodeOwned.advance {memory : NodeMemory} {nextIndex : Nat}
    (held : NodeOwned memory index before) (effect : CellEffect memory.writes before after)
    (contents : after.cellEntry? memory.data.outputCell = some {
      id := memory.data.outputCell,
      value := some (.array (signedI32Values (written memory.data.original memory.data.tokens.length
        (priorUses memory.data.collection.records nextIndex)))) })
    (node : (Assertion.localPointsTo 13 memory.nodeCell (some (.signed .i32 nextIndex))).holds after) :
    NodeOwned memory nextIndex after := by
  have keep {id : VarId} {value : Value} (member : id ∈ nodeStableIds)
      (found : before.local? id = some value) : after.local? id = some value :=
    effect.preserves_local held.wellFormed found (held.stable id member)
  have inputs (cell : CellId) (member : cell ∈ [memory.data.grammarCell, memory.data.kindsCell, memory.data.recordsCell, memory.data.offsetsCell]) :
      ¬ memory.writes cell := by
    rcases memory.inputs cell member with ⟨output, node⟩
    exact fun changed => changed.elim output node
  refine ⟨effect.wellFormed,
    held.grammar.preserved (fun _ found => keep (by decide) found) held.wellFormed effect (inputs _ (by simp)),
    held.kinds.preserved (fun _ found => keep (by decide) found) held.wellFormed effect (inputs _ (by simp)),
    held.records.preserved (fun _ found => keep (by decide) found) held.wellFormed effect (inputs _ (by simp)),
    held.offsets.preserved (fun _ found => keep (by decide) found) held.wellFormed effect (inputs _ (by simp)),
    keep (by decide) held.output, contents, node,
    keep (by decide) held.count, keep (by decide) held.wordLength, keep (by decide) held.nodeCount,
    keep (by decide) held.kindCount, keep (by decide) held.canonicalOffset, ?_⟩
  intro id member cell found
  apply held.stable id member cell
  simpa only [State.cellId?, effect.locals] using found

theorem NodeOwned.input_old {memory : NodeMemory} (held : NodeOwned memory index before)
    (member : cell ∈ [memory.data.grammarCell, memory.data.kindsCell, memory.data.recordsCell, memory.data.offsetsCell]) :
    cell < before.nextCell := by
  simp only [List.mem_cons, List.not_mem_nil, or_false] at member
  rcases member with rfl | rfl | rfl | rfl
  · exact StateWellFormed.cell_lt_next_of_entry held.wellFormed held.grammar.unused_backing
  · exact StateWellFormed.cell_lt_next_of_entry held.wellFormed held.kinds.unused_backing
  · exact StateWellFormed.cell_lt_next_of_entry held.wellFormed held.records.unused_backing
  · exact StateWellFormed.cell_lt_next_of_entry held.wellFormed held.offsets.unused_backing

end Lanius.Extraction.SemanticTokens.Collect
