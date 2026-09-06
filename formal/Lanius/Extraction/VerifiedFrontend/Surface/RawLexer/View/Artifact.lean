import Lanius.Extraction.KernelReduction
import Lanius.Extraction.VerifiedFrontend.Artifact.RawLexer.Cache.Assembly
import Lanius.Extraction.VerifiedFrontend.Artifact.RawLexer.Artifact

namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendRawLexer_cache_checked_kernel :
    verifiedFrontendRawLexerCache.matches verifiedFrontendRawLexerArtifact = true := by
  apply ArtifactCache.matches_of_sharedNodes
  · rfl
  · kernel_rfl
def verifiedFrontendRawLexerView :
    ArtifactView verifiedFrontendRawLexerArtifact :=
  verifiedFrontendRawLexerCache.ofMatches
    verifiedFrontendRawLexer_cache_checked_kernel

end Lanius.Extraction
