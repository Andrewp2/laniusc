import Lanius.Extraction.VerifiedFrontendUnitCanonicalTokens
import Lanius.Extraction.ArtifactCacheQuote
namespace Lanius.Extraction
set_option maxRecDepth 100000
def verifiedFrontendCanonicalTokensSemanticKindTree : Lanius.Data.SeqTree Nat :=
  artifact_pack_unit_semantic_kind_tree%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/canonical_tokens.lani", 64
end Lanius.Extraction
