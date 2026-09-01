import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexer

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendTokenScan_surface_checked_kernel :
    (checkSurfaceArtifactCached? verifiedFrontendTokenScanArtifact).isSome = true := by
  cbv

def verifiedFrontendTokenScanSurfaceKernel :=
  (checkSurfaceArtifactCached? verifiedFrontendTokenScanArtifact).get
    verifiedFrontendTokenScan_surface_checked_kernel

theorem verifiedFrontendTokenScanSurfaceKernel_eq :
    checkSurfaceArtifactCached? verifiedFrontendTokenScanArtifact =
      some verifiedFrontendTokenScanSurfaceKernel := by
  generalize found : checkSurfaceArtifactCached?
    verifiedFrontendTokenScanArtifact = result
  cases result <;> simp_all [verifiedFrontendTokenScanSurfaceKernel]

end Lanius.Extraction
