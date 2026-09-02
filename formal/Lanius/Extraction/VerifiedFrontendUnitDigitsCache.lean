import Lanius.Extraction.VerifiedFrontendUnitDigits
import Lanius.Extraction.VerifiedFrontendUnitCacheBase
namespace Lanius.Extraction
set_option maxRecDepth 100000
def verifiedFrontendDigitsCache : ArtifactCache := artifactCacheOfTrees
  (artifact_pack_unit_cache_trees% (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/digits.lani", 0, 64)
end Lanius.Extraction
