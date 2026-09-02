import Lanius.Extraction.VerifiedFrontendPackKernelEvidence
import Lanius.Extraction.VerifiedFrontendPackKernelResolution

namespace Lanius.Extraction

/-! Proof-producing counterpart of the fast native checked-pack certificate.
Each expensive checker phase is reduced and cached in its own module, then the
same public checked-package type is assembled without re-running those phases. -/

def verifiedFrontendPackCheckedKernel :
    CompleteChecker.CheckedPack verifiedFrontendPack := {
  semantics := verifiedFrontendPackSemanticsKernel
  evidence := verifiedFrontendPackEvidenceKernel.proof
  scopedResolution := verifiedFrontendPackResolutionKernel
}

theorem verifiedFrontendPack_completely_checked_kernel :
    Nonempty (CompleteChecker.CheckedPack verifiedFrontendPack) :=
  ⟨verifiedFrontendPackCheckedKernel⟩

end Lanius.Extraction
