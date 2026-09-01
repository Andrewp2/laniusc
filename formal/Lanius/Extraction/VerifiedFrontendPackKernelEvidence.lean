import Lanius.Extraction.VerifiedFrontendPackKernelSemantics

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.warning false
set_option cbv.maxSteps 100000000

theorem verifiedFrontendPack_evidence_checked_kernel :
    (CompleteChecker.checkPackEvidenceCached? verifiedFrontendPack
      verifiedFrontendPackSemanticsKernel.structural.surfaceData).isSome = true := by
  cbv

def verifiedFrontendPackEvidenceKernel :=
  (CompleteChecker.checkPackEvidenceCached? verifiedFrontendPack
    verifiedFrontendPackSemanticsKernel.structural.surfaceData).get
      verifiedFrontendPack_evidence_checked_kernel

theorem verifiedFrontendPackEvidenceKernel_eq :
    CompleteChecker.checkPackEvidenceCached? verifiedFrontendPack
        verifiedFrontendPackSemanticsKernel.structural.surfaceData =
      some verifiedFrontendPackEvidenceKernel := by
  generalize found : CompleteChecker.checkPackEvidenceCached?
    verifiedFrontendPack
    verifiedFrontendPackSemanticsKernel.structural.surfaceData = result
  cases result <;> simp_all [verifiedFrontendPackEvidenceKernel]

end Lanius.Extraction
