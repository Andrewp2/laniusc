import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceToken

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendCanonicalTokens_surface_checked_kernel :
    (checkSurfaceArtifactCached?
      verifiedFrontendCanonicalTokensArtifact).isSome = true := by
  cbv

def verifiedFrontendCanonicalTokensSurfaceKernel :=
  (checkSurfaceArtifactCached? verifiedFrontendCanonicalTokensArtifact).get
    verifiedFrontendCanonicalTokens_surface_checked_kernel

theorem verifiedFrontendCanonicalTokensSurfaceKernel_eq :
    checkSurfaceArtifactCached? verifiedFrontendCanonicalTokensArtifact =
      some verifiedFrontendCanonicalTokensSurfaceKernel := by
  generalize found : checkSurfaceArtifactCached?
    verifiedFrontendCanonicalTokensArtifact = result
  cases result <;> simp_all [verifiedFrontendCanonicalTokensSurfaceKernel]

end Lanius.Extraction
