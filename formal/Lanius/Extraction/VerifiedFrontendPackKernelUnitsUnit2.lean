import Lanius.Extraction.VerifiedFrontendPackKernelContextMaterialized

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0

theorem verifiedFrontendDigits_unit_checked_kernel :
    (ArtifactPackContextChecker.checkUnit? verifiedFrontendPackContextMaterializedKernel
      verifiedFrontendDigitsProgramUnitKernel).isSome = true := by
  with_unfolding_all rfl

def verifiedFrontendDigitsUnitKernel :=
  (ArtifactPackContextChecker.checkUnit? verifiedFrontendPackContextMaterializedKernel
    verifiedFrontendDigitsProgramUnitKernel).get verifiedFrontendDigits_unit_checked_kernel

theorem verifiedFrontendDigitsUnitKernel_eq :
    ArtifactPackContextChecker.checkUnit? verifiedFrontendPackContextMaterializedKernel
        verifiedFrontendDigitsProgramUnitKernel =
      some verifiedFrontendDigitsUnitKernel :=
  parseOptionEqSomeGet verifiedFrontendDigits_unit_checked_kernel

end Lanius.Extraction
