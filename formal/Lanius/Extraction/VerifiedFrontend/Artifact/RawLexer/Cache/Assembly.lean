import Lanius.Extraction.VerifiedFrontend.Artifact.RawLexer.Artifact
import Lanius.Extraction.VerifiedFrontend.Artifact.CacheBase
namespace Lanius.Extraction
set_option maxRecDepth 100000
def verifiedFrontendRawLexerCache : ArtifactCache := artifactCacheOfTrees
  (artifact_pack_unit_cache_trees% (include_str ".." / ".." / ".." / ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/raw_lexer.lani", 0, 64)
end Lanius.Extraction
