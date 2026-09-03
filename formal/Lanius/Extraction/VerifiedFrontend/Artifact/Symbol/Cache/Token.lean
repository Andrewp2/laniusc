import Lanius.Extraction.VerifiedFrontend.Artifact.Symbol.Artifact
import Lanius.Extraction.VerifiedFrontend.Artifact.CacheBase
namespace Lanius.Extraction
set_option maxRecDepth 100000
def verifiedFrontendSymbolTokenTree : Lanius.Data.SeqTree Token :=
  artifact_pack_unit_token_tree% (include_str ".." / ".." / ".." / ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/symbol.lani", 64
end Lanius.Extraction
