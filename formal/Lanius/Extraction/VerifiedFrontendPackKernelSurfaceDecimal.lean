import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceCanonicalTokens

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendDecimal_surface_checked_kernel :
    (checkSurfaceArtifactCached? verifiedFrontendDecimalArtifact).isSome = true := by
  cbv

def verifiedFrontendDecimalSurfaceKernel :=
  (checkSurfaceArtifactCached? verifiedFrontendDecimalArtifact).get
    verifiedFrontendDecimal_surface_checked_kernel

theorem verifiedFrontendDecimalSurfaceKernel_eq :
    checkSurfaceArtifactCached? verifiedFrontendDecimalArtifact =
      some verifiedFrontendDecimalSurfaceKernel := by
  generalize found : checkSurfaceArtifactCached?
    verifiedFrontendDecimalArtifact = result
  cases result <;> simp_all [verifiedFrontendDecimalSurfaceKernel]

end Lanius.Extraction
