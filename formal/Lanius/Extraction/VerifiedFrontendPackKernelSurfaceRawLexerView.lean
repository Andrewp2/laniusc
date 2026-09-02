import Lanius.Extraction.VerifiedFrontendUnitRawLexerCache

namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendRawLexer_cache_checked_kernel :
    verifiedFrontendRawLexerCache.matches verifiedFrontendRawLexerArtifact = true := by
  with_unfolding_all rfl
def verifiedFrontendRawLexerView :
    ArtifactView verifiedFrontendRawLexerArtifact :=
  verifiedFrontendRawLexerCache.ofMatches
    verifiedFrontendRawLexer_cache_checked_kernel

end Lanius.Extraction
