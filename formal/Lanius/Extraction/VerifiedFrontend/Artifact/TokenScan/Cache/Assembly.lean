import Lanius.Extraction.VerifiedFrontend.Artifact.Cache.Base
-- Closed-term hoisting is expensive for these large constructor quotations.
-- Keep executable code and kernel checking, but skip that compiler optimization.
set_option compiler.extract_closed false

namespace Lanius.Extraction
set_option maxRecDepth 100000
def verifiedFrontendTokenScanCache : ArtifactCache := artifactCacheOfTrees
  (artifact_pack_unit_cache_trees% (include_str ".." / ".." / ".." / ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/token_scan.lani", 0, 64)
end Lanius.Extraction
