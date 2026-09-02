import Lanius.Extraction.VerifiedFrontendUnitToken
import Lanius.Extraction.VerifiedFrontendUnitCacheBase
namespace Lanius.Extraction
set_option maxRecDepth 100000
def verifiedFrontendTokenCache : ArtifactCache := artifactCacheOfTrees
  (artifact_pack_unit_cache_trees% (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/token.lani", 0, 64)
end Lanius.Extraction
