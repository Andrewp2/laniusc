import Lanius.Extraction.VerifiedFrontendPack
import Lanius.Extraction.TokenChecker

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_token_checked_kernel :
    checkTokenArtifact verifiedFrontendLexerArtifact = true := by
  cbv

end Lanius.Extraction
