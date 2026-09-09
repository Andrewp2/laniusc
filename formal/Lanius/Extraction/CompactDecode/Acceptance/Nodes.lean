import Lanius.Extraction.CompactDecode.Grammar

namespace Lanius.Extraction.CompactDecode

open Lanius.Compiler.Parser SemanticTokens

/-- The declarative child relation is sufficient for the executable checker;
proofs of emitted trees can use the relation instead of reducing the checker. -/
theorem children_match_accepted
    (matched : ChildrenMatch grammar kinds nodes current symbols children start finish) :
    checkChildren grammar kinds nodes current symbols children start = some finish := by
  induction matched with
  | empty => rfl
  | terminal terminal tokenPosition advanced tail ih =>
      simp [checkChildren, terminal, tokenPosition, advanced, ih]
  | nonterminal nonterminal inRange earlier lookup childKind childStart tail ih =>
      simp [checkChildren, Nat.not_lt.mpr nonterminal, inRange, earlier, lookup,
        childKind, childStart, ih]

theorem node_match_accepted {id : Nat} (matched : NodeMatches grammar kinds nodes id node) :
    checkNode grammar kinds nodes id node = true := by
  cases matched with
  | intro production lookup nonterminal ordered bounded children =>
      simp [checkNode, lookup, nonterminal, ordered, bounded, children_match_accepted children]

theorem nodes_match_accepted {id : Nat} (matched : NodesMatchFrom grammar kinds nodes id remaining) :
    checkNodesFrom grammar kinds nodes id remaining = true := by
  induction matched with
  | empty => rfl
  | cons head tail ih =>
      simp only [checkNodesFrom, node_match_accepted head, ih, Bool.true_and]

/-- Production identity and both span bounds survive decoding for every
collected node, not just the selected root. -/
theorem collection_node_headers
    (parse : MaterializedParse grammar (tokens.map Token.kind))
    (collection : CollectionRecords grammar tokens parse.tree 0 0)
    (sameGrammar : grammar.grammar = laniusGrammar)
    (member : record ∈ collection.records) :
    ∃ production, laniusGrammar.production? (decodedNode record).production = some production ∧
      (decodedNode record).nonterminal = production.lhs ∧
      (decodedNode record).position_start ≤ (decodedNode record).position_end ∧
      (decodedNode record).position_end ≤ (collection.assignments.map Assignment.code).length * 2 := by
  obtain ⟨production, found⟩ := collection_productions parse collection sameGrammar record member
  have lower := (collection.valid record member).monotone
  have upper := collection.bounded record member
  refine ⟨production, found, ?_, lower, ?_⟩
  · simp [decodedNode, found]
  · simpa only [decodedNode, List.length_map, collection.lengthEq, finalPosition] using upper

/-- The decoder preserves the existing backward link and exact child span.
The child's grammar symbol is established separately from tree recognition. -/
theorem collection_node_link
    (collection : CollectionRecords grammar tokens tree 0 0)
    (found : collection.records[index]? = some record)
    (member : ChildVisit.node childId start finish ∈ record.children) :
    childId < index ∧ ∃ node,
      (collection.records.map decodedNode)[childId]? = some node ∧
      node.position_start = start ∧ node.position_end = finish := by
  obtain ⟨_, bound, child, childFound, sameStart, sameFinish⟩ := collection.linked index record found _ member
  refine ⟨by simpa using bound, decodedNode child, ?_, sameStart, sameFinish⟩
  simpa only [List.getElem?_map, Nat.sub_zero, childFound, Option.map_some] using
    congrArg (Option.map decodedNode) childFound

end Lanius.Extraction.CompactDecode
