import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerClaimsBase

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_claims_coverage_kernel :
    spellingCoverageValid verifiedFrontendLexerArtifact
      verifiedFrontendLexerClaimsKernel = true := by
  cbv

end Lanius.Extraction
