import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerClaimsDense
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerClaimsNodes
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerClaimsSpellings
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerClaimsCoverage

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_claims_valid_kernel :
    surfaceClaimsValidCached verifiedFrontendLexerArtifact
      verifiedFrontendLexerClaimsKernel = true := by
  simp only [surfaceClaimsValidCached, verifiedFrontendLexer_claims_dense_kernel,
    verifiedFrontendLexer_claims_nodes_kernel,
    verifiedFrontendLexer_claims_spellings_kernel,
    verifiedFrontendLexer_claims_coverage_kernel, Bool.and_self]

end Lanius.Extraction
