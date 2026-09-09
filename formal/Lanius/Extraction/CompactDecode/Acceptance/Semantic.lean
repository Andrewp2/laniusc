import Lanius.Extraction.CompactDecode.Grammar

namespace Lanius.Extraction.CompactDecode

open CompactOutput SemanticTokens

theorem emission_semantic_accepted
    (emission : Unit.Emission)
    (result : FrontendResult emission.data emission.count emission.nodes emission.words extracted)
    (collection : CollectionRecords emission.data.grammar (artifactTokens emission.data.tokens) result.parse.tree 0 0)
    (sameGrammar : emission.data.grammar.grammar = laniusGrammar) (path : String) :
    let artifact := (emissionUnit emission path collection.assignments collection.records).artifact
    semanticKindsValid laniusGrammar artifact.tokens artifact.semantic_token_kinds = true := by
  change semanticKindsValid laniusGrammar (artifactTokens emission.data.tokens)
    (collection.assignments.map Assignment.code) = true
  rw [← sameGrammar]
  exact collection.acceptedKinds

end Lanius.Extraction.CompactDecode
