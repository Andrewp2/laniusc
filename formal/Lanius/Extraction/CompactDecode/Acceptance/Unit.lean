import Lanius.Extraction.CompactDecode.Acceptance.Children
import Lanius.Extraction.CompactDecode.Acceptance.Lexical
import Lanius.Extraction.CompactDecode.Acceptance.Semantic
import Lanius.Extraction.CompactDecode.Acceptance.Root

namespace Lanius.Extraction.CompactDecode

open CompactOutput SemanticTokens

/-- Successful frontend output and its selected collection produce an artifact
accepted by the complete syntax checker. No component-check acceptance is assumed. -/
theorem frontend_artifact_accepted
    (emission : Unit.Emission)
    (result : FrontendResult emission.data emission.count emission.nodes emission.words extracted)
    (collection : CollectionRecords emission.data.grammar (artifactTokens emission.data.tokens) result.parse.tree 0 0)
    (post : emission.data.Post stage detail emission.count emission.nodes emission.words position before extracted)
    (success : stage = 0)
    (sameGrammar : emission.data.grammar.grammar = laniusGrammar)
    (kindsBound : emission.data.grammar.grammar.n_kinds ≤ 32768)
    (path : String) :
    checkParseArtifact (emissionUnit emission path collection.assignments collection.records).artifact = true := by
  apply checkParseArtifact_of_checks _ (collection.records.length - 1)
  · exact frontend_tokens_accepted emission path collection.assignments collection.records post success
  · exact emission_semantic_accepted emission result collection sameGrammar path
  · exact collection_nodes_accepted result.parse collection sameGrammar kindsBound
  · rfl
  · exact emission_root_accepted emission result collection sameGrammar path

end Lanius.Extraction.CompactDecode
