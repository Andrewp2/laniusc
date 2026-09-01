import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceDecimal

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendNumber_surface_checked_kernel :
    (checkSurfaceArtifactCached? verifiedFrontendNumberArtifact).isSome = true := by
  cbv

def verifiedFrontendNumberSurfaceKernel :=
  (checkSurfaceArtifactCached? verifiedFrontendNumberArtifact).get
    verifiedFrontendNumber_surface_checked_kernel

theorem verifiedFrontendNumberSurfaceKernel_eq :
    checkSurfaceArtifactCached? verifiedFrontendNumberArtifact =
      some verifiedFrontendNumberSurfaceKernel := by
  generalize found : checkSurfaceArtifactCached?
    verifiedFrontendNumberArtifact = result
  cases result <;> simp_all [verifiedFrontendNumberSurfaceKernel]

end Lanius.Extraction
