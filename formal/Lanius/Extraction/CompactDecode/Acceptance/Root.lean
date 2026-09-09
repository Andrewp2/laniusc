import Lanius.Extraction.CompactDecode.Grammar

namespace Lanius.Extraction.CompactDecode

open Lanius.Compiler.Parser SemanticTokens

theorem collection_root_accepted
    (parse : MaterializedParse grammar (tokens.map Token.kind))
    (collection : CollectionRecords grammar tokens parse.tree 0 0)
    (sameGrammar : grammar.grammar = laniusGrammar) :
    rootShapeValid laniusGrammar tokens.length (collection.records.map decodedNode)
      (collection.records.length - 1) = true := by
  rw [collection.recordsEq]
  have recognized := parse.recognizes
  cases treeEq : parse.tree with
  | terminal token kind =>
    rw [treeEq] at recognized
    cases recognized with
    | terminal tokenEq bound scanned => omega
  | nonterminal production nonterminal start finish children =>
    rw [treeEq] at recognized
    generalize symbolEq : grammar.grammar.n_kinds + grammar.grammar.start_nonterminal = symbol at recognized
    cases recognized with
    | nonterminal ntBound productionBound lhs childrenRecognize =>
      have ntEq : nonterminal = grammar.grammar.start_nonterminal := by omega
      have found : laniusGrammar.production? production =
          some (grammar.productionAt ⟨production, productionBound⟩) := by
        rw [← sameGrammar]
        exact List.getElem?_eq_getElem productionBound
      rw [← sameGrammar] at found
      simp [treeVisits, rootShapeValid, List.map_append, decodedNode, found, lhs, ntEq,
        ← sameGrammar, finalPosition]

theorem emission_root_accepted
    (emission : CompactOutput.Unit.Emission)
    (result : FrontendResult emission.data emission.count emission.nodes emission.words extracted)
    (collection : CollectionRecords emission.data.grammar (artifactTokens emission.data.tokens) result.parse.tree 0 0)
    (sameGrammar : emission.data.grammar.grammar = laniusGrammar) (path : String) :
    let artifact := (emissionUnit emission path collection.assignments collection.records).artifact
    rootShapeValid laniusGrammar artifact.tokens.length artifact.parse_nodes
      (collection.records.length - 1) = true := by
  change rootShapeValid laniusGrammar (artifactTokens emission.data.tokens).length
    (collection.records.map decodedNode) (collection.records.length - 1) = true
  exact collection_root_accepted result.parse collection sameGrammar

end Lanius.Extraction.CompactDecode
