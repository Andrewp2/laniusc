import Lanius.Extraction.VerifiedFrontendUnitToken
import Lanius.Extraction.ArtifactCacheQuote
namespace Lanius.Extraction
set_option maxRecDepth 500000
def verifiedFrontendTokenSemanticKindTree : Lanius.Data.SeqTree Nat :=
  artifact_pack_unit_semantic_kind_tree%
    (include_str "Artifacts" / "frontend_pack.json"), "verified_compiler/src/verified/token.lani", 64
end Lanius.Extraction
