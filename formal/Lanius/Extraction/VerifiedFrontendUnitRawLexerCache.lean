import Lanius.Extraction.VerifiedFrontendUnitRawLexer
import Lanius.Extraction.VerifiedFrontendUnitCacheBase
namespace Lanius.Extraction
set_option maxRecDepth 100000
def verifiedFrontendRawLexerCache : ArtifactCache := artifactCacheOfTrees
  (artifact_pack_unit_cache_trees% (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/raw_lexer.lani", 0, 64)
end Lanius.Extraction
