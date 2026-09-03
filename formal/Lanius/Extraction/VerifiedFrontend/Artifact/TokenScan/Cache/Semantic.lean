import Lanius.Extraction.VerifiedFrontend.Artifact.TokenScan.Artifact
import Lanius.Extraction.ArtifactCacheQuote
namespace Lanius.Extraction
set_option maxRecDepth 500000
def verifiedFrontendTokenScanSemanticKindTree : Lanius.Data.SeqTree Nat :=
  artifact_pack_unit_semantic_kind_tree%
    (include_str ".." / ".." / ".." / ".." / "Artifacts" / "frontend_pack.json"), "verified_compiler/src/verified/token_scan.lani", 64
end Lanius.Extraction
