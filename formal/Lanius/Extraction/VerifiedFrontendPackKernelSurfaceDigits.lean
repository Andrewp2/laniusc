import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceTokenScan

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendDigits_surface_checked_kernel :
    (checkSurfaceArtifactCached? verifiedFrontendDigitsArtifact).isSome = true := by
  cbv

def verifiedFrontendDigitsSurfaceKernel :=
  (checkSurfaceArtifactCached? verifiedFrontendDigitsArtifact).get
    verifiedFrontendDigits_surface_checked_kernel

theorem verifiedFrontendDigitsSurfaceKernel_eq :
    checkSurfaceArtifactCached? verifiedFrontendDigitsArtifact =
      some verifiedFrontendDigitsSurfaceKernel := by
  generalize found : checkSurfaceArtifactCached?
    verifiedFrontendDigitsArtifact = result
  cases result <;> simp_all [verifiedFrontendDigitsSurfaceKernel]

end Lanius.Extraction
