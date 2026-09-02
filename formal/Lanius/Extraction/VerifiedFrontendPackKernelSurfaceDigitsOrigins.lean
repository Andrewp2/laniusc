import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceDigitsClaims
import Lanius.Extraction.VerifiedFrontendPackOrigins

namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendDigits_origin_claims_equal_kernel :
    verifiedFrontendDigitsOrigins.claims = verifiedFrontendDigitsClaims := by cbv

theorem verifiedFrontendDigits_origin_ids_dense_kernel :
    verifiedFrontendDigitsOrigins.claims.nodes.map (·.id) ==
      List.range verifiedFrontendDigitsOrigins.claims.nodes.length := by cbv

theorem verifiedFrontendDigits_node_origins_checked_kernel :
    nodeOriginPathsValid verifiedFrontendDigitsArtifact verifiedFrontendDigitsView
      verifiedFrontendDigitsOrigins.claims.nodes
      verifiedFrontendDigitsOrigins.nodePaths = true := by cbv

theorem verifiedFrontendDigits_spelling_origins_checked_kernel :
    spellingOriginPathsValid verifiedFrontendDigitsArtifact
      verifiedFrontendDigitsView verifiedFrontendDigitsOrigins.claims.spellings
      verifiedFrontendDigitsOrigins.spellingPaths = true := by cbv

theorem verifiedFrontendDigits_origin_coverage_checked_kernel :
    spellingCoverageValid verifiedFrontendDigitsArtifact
      verifiedFrontendDigitsOrigins.claims = true := by cbv

theorem verifiedFrontendDigits_origins_checked_kernel :
    verifiedFrontendDigitsOrigins.valid verifiedFrontendDigitsArtifact
      verifiedFrontendDigitsView = true := by
  simp [SurfaceOrigins.valid, verifiedFrontendDigits_origin_ids_dense_kernel,
    verifiedFrontendDigits_node_origins_checked_kernel,
    verifiedFrontendDigits_spelling_origins_checked_kernel,
    verifiedFrontendDigits_origin_coverage_checked_kernel]

end Lanius.Extraction
