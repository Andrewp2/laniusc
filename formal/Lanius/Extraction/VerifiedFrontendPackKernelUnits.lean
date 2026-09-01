import Lanius.Extraction.VerifiedFrontendPackKernelContext

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendPack_units_checked_kernel :
    (ArtifactPackContextChecker.checkUnits verifiedFrontendPackContextKernel
      verifiedFrontendPackDecodedKernel.units).isSome = true := by
  cbv

def verifiedFrontendPackUnitsKernel :=
  (ArtifactPackContextChecker.checkUnits verifiedFrontendPackContextKernel
    verifiedFrontendPackDecodedKernel.units).get
      verifiedFrontendPack_units_checked_kernel

theorem verifiedFrontendPackUnitsKernel_eq :
    ArtifactPackContextChecker.checkUnits verifiedFrontendPackContextKernel
        verifiedFrontendPackDecodedKernel.units =
      some verifiedFrontendPackUnitsKernel := by
  generalize found : ArtifactPackContextChecker.checkUnits
    verifiedFrontendPackContextKernel
    verifiedFrontendPackDecodedKernel.units = result
  cases result <;> simp_all [verifiedFrontendPackUnitsKernel]

end Lanius.Extraction
