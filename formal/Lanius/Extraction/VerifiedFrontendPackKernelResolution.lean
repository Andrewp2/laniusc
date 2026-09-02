import Lanius.Extraction.VerifiedFrontendPackKernelSemantics
import Lanius.Extraction.GlobalResolutionEvidenceChecker

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.warning false
set_option cbv.maxSteps 100000000

theorem verifiedFrontendPack_resolution_checked_kernel :
    (GlobalResolutionEvidenceChecker.checkPackResolution?
      verifiedFrontendPack
      verifiedFrontendPackSemanticsKernel.context).isSome = true := by
  cbv

def verifiedFrontendPackResolutionKernel :=
  (GlobalResolutionEvidenceChecker.checkPackResolution?
    verifiedFrontendPack
    verifiedFrontendPackSemanticsKernel.context).get
      verifiedFrontendPack_resolution_checked_kernel

theorem verifiedFrontendPackResolutionKernel_eq :
    GlobalResolutionEvidenceChecker.checkPackResolution?
        verifiedFrontendPack verifiedFrontendPackSemanticsKernel.context =
      some verifiedFrontendPackResolutionKernel := by
  generalize found : GlobalResolutionEvidenceChecker.checkPackResolution?
    verifiedFrontendPack verifiedFrontendPackSemanticsKernel.context = result
  cases result <;> simp_all [verifiedFrontendPackResolutionKernel]

end Lanius.Extraction
