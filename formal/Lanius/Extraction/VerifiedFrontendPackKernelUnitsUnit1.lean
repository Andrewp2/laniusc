import Lanius.Extraction.VerifiedFrontendPackKernelContextMaterialized

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0

theorem verifiedFrontendTokenScan_unit_checked_kernel :
    (ArtifactPackContextChecker.checkUnit? verifiedFrontendPackContextMaterializedKernel
      verifiedFrontendTokenScanProgramUnitKernel).isSome = true := by
  with_unfolding_all rfl

def verifiedFrontendTokenScanUnitKernel :=
  (ArtifactPackContextChecker.checkUnit? verifiedFrontendPackContextMaterializedKernel
    verifiedFrontendTokenScanProgramUnitKernel).get verifiedFrontendTokenScan_unit_checked_kernel

theorem verifiedFrontendTokenScanUnitKernel_eq :
    ArtifactPackContextChecker.checkUnit? verifiedFrontendPackContextMaterializedKernel
        verifiedFrontendTokenScanProgramUnitKernel =
      some verifiedFrontendTokenScanUnitKernel :=
  parseOptionEqSomeGet verifiedFrontendTokenScan_unit_checked_kernel

end Lanius.Extraction
