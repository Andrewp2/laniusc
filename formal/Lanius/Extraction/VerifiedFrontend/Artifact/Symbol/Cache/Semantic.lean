import Lanius.Extraction.VerifiedFrontend.Artifact.Symbol.Artifact
import Lanius.Extraction.ArtifactCacheQuote
namespace Lanius.Extraction
set_option maxRecDepth 100000
def verifiedFrontendSymbolSemanticKindTree : Lanius.Data.SeqTree Nat :=
  artifact_pack_unit_semantic_kind_tree%
    (include_str ".." / ".." / ".." / ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/symbol.lani", 64
end Lanius.Extraction
