import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceNumber

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendSymbol_surface_checked_kernel :
    (checkSurfaceArtifactCached? verifiedFrontendSymbolArtifact).isSome = true := by
  cbv

def verifiedFrontendSymbolSurfaceKernel :=
  (checkSurfaceArtifactCached? verifiedFrontendSymbolArtifact).get
    verifiedFrontendSymbol_surface_checked_kernel

theorem verifiedFrontendSymbolSurfaceKernel_eq :
    checkSurfaceArtifactCached? verifiedFrontendSymbolArtifact =
      some verifiedFrontendSymbolSurfaceKernel := by
  generalize found : checkSurfaceArtifactCached?
    verifiedFrontendSymbolArtifact = result
  cases result <;> simp_all [verifiedFrontendSymbolSurfaceKernel]

end Lanius.Extraction
