import Lanius.Extraction.VerifiedFrontend.Artifact.Digits.Artifact
import Lanius.Extraction.ArtifactCacheQuote
namespace Lanius.Extraction
set_option maxRecDepth 500000
def verifiedFrontendDigitsSemanticKindTree : Lanius.Data.SeqTree Nat :=
  artifact_pack_unit_semantic_kind_tree%
    (include_str ".." / ".." / ".." / ".." / "Artifacts" / "frontend_pack.json"), "verified_compiler/src/verified/digits.lani", 64
end Lanius.Extraction
