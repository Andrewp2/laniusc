import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerParse
import Lanius.Extraction.ParseChecker

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_semantic_kinds_checked_kernel :
    semanticKindsValid laniusGrammar verifiedFrontendLexerArtifact.tokens
      verifiedFrontendLexerArtifact.semantic_token_kinds = true := by
  cbv

end Lanius.Extraction
