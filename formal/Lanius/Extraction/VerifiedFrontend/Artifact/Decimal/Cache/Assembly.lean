import Lanius.Extraction.VerifiedFrontend.Artifact.Cache.Base
-- Closed-term hoisting is expensive for these large constructor quotations.
-- Keep executable code and kernel checking, but skip that compiler optimization.
set_option compiler.extract_closed false

namespace Lanius.Extraction
set_option maxRecDepth 100000
def verifiedFrontendDecimalCache : ArtifactCache := artifactCacheOfTrees
  (artifact_pack_unit_cache_trees% (include_str ".." / ".." / ".." / ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/decimal.lani", 0, 64)
end Lanius.Extraction
