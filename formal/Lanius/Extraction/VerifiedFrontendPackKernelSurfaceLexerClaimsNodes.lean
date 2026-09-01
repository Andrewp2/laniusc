import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerClaimsBase

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_claims_nodes_kernel :
    verifiedFrontendLexerClaimsKernel.nodes.all
      (nodeClaimValidCached verifiedFrontendLexerArtifact) = true := by
  cbv

end Lanius.Extraction
