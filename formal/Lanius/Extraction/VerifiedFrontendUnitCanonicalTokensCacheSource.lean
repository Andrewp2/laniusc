import Lanius.Extraction.VerifiedFrontendUnitCanonicalTokens
import Lanius.Extraction.VerifiedFrontendUnitCacheBase
namespace Lanius.Extraction
set_option maxRecDepth 500000
def verifiedFrontendCanonicalTokensSourceByteTree : Lanius.Data.SeqTree (Fin 256) :=
  artifact_pack_unit_source_byte_tree% (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/canonical_tokens.lani", 0, 64
end Lanius.Extraction
