import Lanius.Extraction.VerifiedFrontend.Surface.Lexer.Claims.Trace
import Lanius.Extraction.VerifiedFrontend.Artifact.Lexer.Origins

namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
theorem verifiedFrontendLexer_spelling_origin_trace_checked_kernel :
    spellingOriginPathsValid verifiedFrontendLexerArtifact
      verifiedFrontendLexerView verifiedFrontendLexerOrigins.claims.spellings
      verifiedFrontendLexerOrigins.spellingPaths = true := by
  with_unfolding_all rfl
end Lanius.Extraction
