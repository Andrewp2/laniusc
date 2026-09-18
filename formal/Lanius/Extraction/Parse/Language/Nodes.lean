import Lanius.Extraction.Parse.Language.Terminals

namespace Lanius.Extraction
open Lanius.Compiler.Parser

theorem NodesMatchFrom.lookup {index : Nat}
    (valid : NodesMatchFrom grammar kinds nodes offset remaining)
    (found : remaining[index]? = some node) :
    NodeMatches grammar kinds nodes (offset + index) node := by
  induction valid generalizing index with
  | empty => simp at found
  | @cons offset head tail matched rest ih =>
      cases index with
      | zero =>
          have same : head = node := Option.some.inj found
          subst node
          simpa only [Nat.add_zero] using matched
      | succ index =>
          have foundTail : tail[index]? = some node := found
          simpa only [Nat.add_assoc, Nat.add_comm 1] using ih foundTail

theorem ChildrenMatch.recognizes
    (valid : ChildrenMatch grammar.grammar kinds nodes current symbols children start finish)
    (semantic : semanticKindsValid grammar.grammar tokens kinds = true)
    (different : grammar.grammar.split_token_kind ≠ grammar.grammar.split_component_kind)
    (earlier : ∀ (id : Nat), id < current → ∀ node, nodes[id]? = some node →
      node.nonterminal < grammar.grammar.n_nonterminals →
      RecognizesSymbol grammar (tokens.map Token.kind)
        (grammar.grammar.n_kinds + node.nonterminal) node.position_start node.position_end) :
    RecognizesSequence grammar (tokens.map Token.kind) symbols start finish := by
  induction valid with
  | empty => exact .empty
  | terminal terminal _ advanced _ tail =>
      exact .cons (.terminal terminal (advanceTerminal.scanTerminal semantic different advanced)) tail
  | @nonterminal symbol childId childNode position symbols children finish _ inRange before lookup childKind childStart _ tail =>
      have childBound : childNode.nonterminal < grammar.grammar.n_nonterminals := by
        simpa only [childKind] using inRange
      have child := earlier childId before childNode lookup childBound
      have symbolEq : grammar.grammar.n_kinds + childNode.nonterminal = symbol := by omega
      exact .cons (by simpa only [symbolEq, childStart] using child) tail

/-- Earlier-child IDs in the validated postorder tree supply structural
induction. No execution of the source parser or accepted-output premise is
needed to recover the ordinary grammar derivation. -/
theorem NodesMatchFrom.recognizes
    (valid : NodesMatchFrom grammar.grammar kinds nodes 0 nodes)
    (semantic : semanticKindsValid grammar.grammar tokens kinds = true)
    (different : grammar.grammar.split_token_kind ≠ grammar.grammar.split_component_kind)
    {id : Nat} (found : nodes[id]? = some node)
    (bounded : node.nonterminal < grammar.grammar.n_nonterminals) :
    RecognizesSymbol grammar (tokens.map Token.kind)
      (grammar.grammar.n_kinds + node.nonterminal) node.position_start node.position_end := by
  induction id using Nat.strongRecOn generalizing node with
  | ind id ih =>
      have matched : NodeMatches grammar.grammar kinds nodes id node := by
        simpa only [Nat.zero_add] using valid.lookup found
      cases matched with
      | intro production lookup lhs ordered endBound children =>
          have productionBound : node.production < grammar.productionCount :=
            (List.getElem?_eq_some_iff.mp lookup).1
          have productionEq : grammar.productionAt ⟨node.production, productionBound⟩ = production := by
            simpa only [Grammar.production?, IndexedGrammar.productionAt, List.get_eq_getElem] using
              (List.getElem?_eq_some_iff.mp lookup).2
          apply RecognizesSymbol.nonterminal bounded productionBound
            (by rw [productionEq, ← lhs])
          rw [productionEq]
          exact children.recognizes semantic different (fun child before _ lookup bound => ih child before lookup bound)

theorem RootMatches.recognizes
    (root : RootMatches grammar.grammar tokens.length nodes rootId)
    (valid : NodesMatchFrom grammar.grammar kinds nodes 0 nodes)
    (semantic : semanticKindsValid grammar.grammar tokens kinds = true)
    (different : grammar.grammar.split_token_kind ≠ grammar.grammar.split_component_kind)
    (startBound : grammar.grammar.start_nonterminal < grammar.grammar.n_nonterminals) :
    RecognizesInput grammar (tokens.map Token.kind) := by
  cases root with
  | intro node found last nonterminal start finish =>
      have recognized := valid.recognizes semantic different found (by simpa only [nonterminal] using startBound)
      simpa only [RecognizesInput, nonterminal, start, finish, finalPosition, List.length_map, Nat.mul_comm] using recognized

end Lanius.Extraction
