import Lanius.Extraction.SemanticTokens.Collect.Written
import Lanius.Extraction.SemanticTokens.Collect.NodeChild
import Lanius.Extraction.SemanticTokens.Collect.TokenChild

namespace Lanius.Extraction.SemanticTokens.Collect

open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.Compiler.Parser ParserTreeLayout

structure TraversalData where
  grammar : GrammarData
  tokens : List Token
  tree : Lanius.Compiler.Parser.ParseTree
  collection : CollectionRecords grammar.grammar tokens tree 0 0
  grammarCell : CellId
  kindsCell : CellId
  recordsCell : CellId
  offsetsCell : CellId
  outputCell : CellId
  original : List Int
  capacity : tokens.length * 2 ≤ original.length
  tokensFit : tokens.length * 2 ≤ 2147483647
  wordsFit : (treeFrom 0 0 tree).words.length ≤ 2147483647

def childWrites (output position child : CellId) : CellSet :=
  CellSet.union (CellSet.union (CellSet.singleton output) (CellSet.singleton position)) (CellSet.singleton child)

structure ChildMemory where
  data : TraversalData
  positionCell : CellId
  childCell : CellId
  distinct : data.outputCell ≠ positionCell ∧ data.outputCell ≠ childCell ∧ positionCell ≠ childCell
  inputs : ∀ cell ∈ [data.grammarCell, data.kindsCell, data.recordsCell, data.offsetsCell],
    ¬ childWrites data.outputCell positionCell childCell cell

abbrev ChildMemory.writes (memory : ChildMemory) := childWrites memory.data.outputCell memory.positionCell memory.childCell
def childStableIds : List VarId := [0, 2, 3, 4, 5, 6, 7, 8, 10, 11, 13, 14, 15]

/-- Runtime resources of one record's child loop. The semantic path and
visited-prefix uniqueness are separate logical facts, not runtime premises. -/
structure ChildOwned (memory : ChildMemory) (record : RecordVisit)
    (nodeIndex index position : Nat) (uses : List Use) (state : State) : Prop where
  wellFormed : StateWellFormed state
  grammar : memory.data.grammar.Owns memory.data.grammarCell state
  kinds : I32PrefixLocal state 2 memory.data.kindsCell (memory.data.tokens.map (Int.ofNat ∘ Token.kind))
  records : I32PrefixLocal state 4 memory.data.recordsCell (treeFrom 0 0 memory.data.tree).words
  offsets : I32PrefixLocal state 6 memory.data.offsetsCell ((treeFrom 0 0 memory.data.tree).offsets.map Int.ofNat)
  output : state.local? 8 = some (.slice i32 memory.data.outputCell [] 0 memory.data.original.length)
  backing : state.cellEntry? memory.data.outputCell = some {
    id := memory.data.outputCell,
    value := some (.array (signedI32Values (written memory.data.original memory.data.tokens.length uses))) }
  cursor : (Assertion.localPointsTo 16 memory.positionCell (some (.signed .i32 position))).holds state
  child : (Assertion.localPointsTo 17 memory.childCell (some (.signed .i32 index))).holds state
  count : state.local? 3 = some (.signed .i32 memory.data.tokens.length)
  wordLength : state.local? 5 = some (.signed .i32 (treeFrom 0 0 memory.data.tree).words.length)
  nodeCount : state.local? 7 = some (.signed .i32 memory.data.collection.records.length)
  kindCount : state.local? 10 = some (.signed .i32 memory.data.grammar.grammar.grammar.n_kinds)
  canonicalOffset : state.local? 11 = some (.signed .i32 memory.data.grammar.layout.canonicalKindsOffset)
  node : state.local? 13 = some (.signed .i32 nodeIndex)
  offset : state.local? 14 = some (.signed .i32 record.offset)
  childCount : state.local? 15 = some (.signed .i32 record.children.length)
  stable : ∀ id ∈ childStableIds, ∀ cell, state.cellId? id = some cell → ¬ memory.writes cell

theorem ChildOwned.bindLocal {memory : ChildMemory} {record : RecordVisit}
    (held : ChildOwned memory record nodeIndex index position uses before)
    (id : VarId) (value : Value) (high : 18 ≤ id) :
    ChildOwned memory record nodeIndex index position uses (before.bindLocal id value) := by
  have different (localId : VarId) (low : localId < 18) : id ≠ localId := by
    dsimp only [VarId] at high low ⊢
    omega
  have keep {localId : VarId} {current : Value} (low : localId < 18)
      (found : before.local? localId = some current) : (before.bindLocal id value).local? localId = some current :=
    (bindLocal_preserves_other_local held.wellFormed (different localId low)).trans found
  refine ⟨bindLocal_preserves_well_formed _ _ _ held.wellFormed,
    held.grammar.bindLocal held.wellFormed id value (different _ (by decide)),
    held.kinds.bindLocal held.wellFormed id value (different _ (by decide)),
    held.records.bindLocal held.wellFormed id value (different _ (by decide)),
    held.offsets.bindLocal held.wellFormed id value (different _ (by decide)),
    keep (by decide) held.output, ?_,
    bindLocal_preserves_localPointsTo_of_ne before id 16 value memory.positionCell _ held.wellFormed (different _ (by decide)) held.cursor,
    bindLocal_preserves_localPointsTo_of_ne before id 17 value memory.childCell _ held.wellFormed (different _ (by decide)) held.child,
    keep (by decide) held.count, keep (by decide) held.wordLength, keep (by decide) held.nodeCount,
    keep (by decide) held.kindCount, keep (by decide) held.canonicalOffset,
    keep (by decide) held.node, keep (by decide) held.offset, keep (by decide) held.childCount, ?_⟩
  · exact ((bindLocal_effect before id value).oldCells memory.data.outputCell
      (StateWellFormed.cell_lt_next_of_entry held.wellFormed held.backing) (by simp [CellSet.empty])).trans held.backing
  · intro localId member cell found
    have low : localId < 18 := by
      simp only [childStableIds, List.mem_cons, List.not_mem_nil, or_false] at member
      dsimp only [VarId] at member ⊢
      omega
    apply held.stable localId member cell
    simpa only [bindLocal_preserves_other_cellId before id localId value (different localId low)] using found

/-- Reassemble the next iteration from its actual write effect and changed
output/cursors. All read-only inputs and scalar locals are transported here. -/
theorem ChildOwned.advance {memory : ChildMemory} {record : RecordVisit} {nextIndex nextPosition : Nat}
    (held : ChildOwned memory record nodeIndex index position uses before)
    (effect : CellEffect memory.writes before after)
    (contents : after.cellEntry? memory.data.outputCell = some {
      id := memory.data.outputCell,
      value := some (.array (signedI32Values (written memory.data.original memory.data.tokens.length nextUses))) })
    (cursor : (Assertion.localPointsTo 16 memory.positionCell (some (.signed .i32 nextPosition))).holds after)
    (child : (Assertion.localPointsTo 17 memory.childCell (some (.signed .i32 nextIndex))).holds after) :
    ChildOwned memory record nodeIndex nextIndex nextPosition nextUses after := by
  have keep {id : VarId} {value : Value} (member : id ∈ childStableIds)
      (found : before.local? id = some value) : after.local? id = some value :=
    effect.preserves_local held.wellFormed found (held.stable id member)
  refine ⟨effect.wellFormed,
    held.grammar.preserved (fun _ found => keep (by decide) found) held.wellFormed effect (memory.inputs _ (by simp)),
    held.kinds.preserved (fun _ found => keep (by decide) found) held.wellFormed effect (memory.inputs _ (by simp)),
    held.records.preserved (fun _ found => keep (by decide) found) held.wellFormed effect (memory.inputs _ (by simp)),
    held.offsets.preserved (fun _ found => keep (by decide) found) held.wellFormed effect (memory.inputs _ (by simp)),
    keep (by decide) held.output, contents, cursor, child,
    keep (by decide) held.count, keep (by decide) held.wordLength, keep (by decide) held.nodeCount,
    keep (by decide) held.kindCount, keep (by decide) held.canonicalOffset,
    keep (by decide) held.node, keep (by decide) held.offset, keep (by decide) held.childCount, ?_⟩
  intro id member cell found
  apply held.stable id member cell
  simpa only [State.cellId?, effect.locals] using found

end Lanius.Extraction.SemanticTokens.Collect
