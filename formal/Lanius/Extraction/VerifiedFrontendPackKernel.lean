import Lanius.Extraction.VerifiedFrontendPackKernelEvidence
import Lanius.Extraction.VerifiedFrontendPackKernelResolution

namespace Lanius.Extraction

/-! Proof-producing counterpart of the fast native checked-pack certificate.
Each expensive checker phase is reduced and cached in its own module. -/

theorem verifiedFrontendPack_completely_checked_kernel :
    (CompleteChecker.checkPack? verifiedFrontendPack).isSome = true := by
  unfold CompleteChecker.checkPack?
  rw [verifiedFrontendPackSemanticsKernel_eq]
  rw [verifiedFrontendPackEvidenceKernel_eq]
  rw [verifiedFrontendPackResolutionKernel_eq]
  rfl

end Lanius.Extraction
