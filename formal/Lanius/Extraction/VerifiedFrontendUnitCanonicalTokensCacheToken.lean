import Lanius.Extraction.VerifiedFrontendUnitCanonicalTokens
import Lanius.Extraction.VerifiedFrontendUnitCacheBase
namespace Lanius.Extraction
set_option maxRecDepth 500000
def verifiedFrontendCanonicalTokensTokenTree : Lanius.Data.SeqTree Token :=
  artifact_pack_unit_token_tree% (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/canonical_tokens.lani", 64
end Lanius.Extraction
