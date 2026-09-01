import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceDigits

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendToken_surface_checked_kernel :
    (checkSurfaceArtifactCached? verifiedFrontendTokenArtifact).isSome = true := by
  cbv

def verifiedFrontendTokenSurfaceKernel :=
  (checkSurfaceArtifactCached? verifiedFrontendTokenArtifact).get
    verifiedFrontendToken_surface_checked_kernel

theorem verifiedFrontendTokenSurfaceKernel_eq :
    checkSurfaceArtifactCached? verifiedFrontendTokenArtifact =
      some verifiedFrontendTokenSurfaceKernel := by
  generalize found : checkSurfaceArtifactCached?
    verifiedFrontendTokenArtifact = result
  cases result <;> simp_all [verifiedFrontendTokenSurfaceKernel]

end Lanius.Extraction
