import Lanius.Extraction.VerifiedFrontendPackKernelDecoded

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendPack_context_checked_kernel :
    (ArtifactPackContextChecker.buildPackContext?
      verifiedFrontendPackDecodedKernel.units).isSome = true := by
  cbv

def verifiedFrontendPackContextKernel :=
  (ArtifactPackContextChecker.buildPackContext?
    verifiedFrontendPackDecodedKernel.units).get
      verifiedFrontendPack_context_checked_kernel

theorem verifiedFrontendPackContextKernel_eq :
    ArtifactPackContextChecker.buildPackContext?
        verifiedFrontendPackDecodedKernel.units =
      some verifiedFrontendPackContextKernel := by
  generalize found : ArtifactPackContextChecker.buildPackContext?
    verifiedFrontendPackDecodedKernel.units = result
  cases result <;> simp_all [verifiedFrontendPackContextKernel]

end Lanius.Extraction
