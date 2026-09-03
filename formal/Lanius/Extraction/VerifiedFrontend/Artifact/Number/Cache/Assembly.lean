import Lanius.Extraction.VerifiedFrontend.Artifact.Number.Artifact
import Lanius.Extraction.VerifiedFrontend.Artifact.Cache.Base
namespace Lanius.Extraction
set_option maxRecDepth 100000
def verifiedFrontendNumberCache : ArtifactCache := artifactCacheOfTrees
  (artifact_pack_unit_cache_trees% (include_str ".." / ".." / ".." / ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/number.lani", 0, 64)
end Lanius.Extraction
