import Lanius.Extraction.VerifiedFrontendPackKernelStructural

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendPack_decoded_checked_kernel :
    (ArtifactPackContextChecker.decodePackUnitsFromCached 0
      verifiedFrontendPack.units
      verifiedFrontendPackStructuralKernel.surfaceData).isSome = true := by
  cbv

def verifiedFrontendPackDecodedKernel :=
  (ArtifactPackContextChecker.decodePackUnitsFromCached 0
    verifiedFrontendPack.units
    verifiedFrontendPackStructuralKernel.surfaceData).get
      verifiedFrontendPack_decoded_checked_kernel

theorem verifiedFrontendPackDecodedKernel_eq :
    ArtifactPackContextChecker.decodePackUnitsFromCached 0
        verifiedFrontendPack.units
        verifiedFrontendPackStructuralKernel.surfaceData =
      some verifiedFrontendPackDecodedKernel := by
  generalize found : ArtifactPackContextChecker.decodePackUnitsFromCached 0
    verifiedFrontendPack.units
    verifiedFrontendPackStructuralKernel.surfaceData = result
  cases result <;> simp_all [verifiedFrontendPackDecodedKernel]

end Lanius.Extraction
