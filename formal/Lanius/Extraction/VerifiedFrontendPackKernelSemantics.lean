import Lanius.Extraction.VerifiedFrontendPackKernelUnits

namespace Lanius.Extraction

def verifiedFrontendPackSemanticsKernel :
    ArtifactPackContextChecker.CheckedArtifactPackSemantics
      verifiedFrontendPack := {
  structural := verifiedFrontendPackStructuralKernel
  decoded := verifiedFrontendPackDecodedKernel
  context := verifiedFrontendPackContextKernel
  unitsChecked := verifiedFrontendPackUnitsKernel.proof
}

theorem verifiedFrontendPackSemanticsKernel_eq :
    ArtifactPackContextChecker.checkArtifactPackSemantics?
        verifiedFrontendPack = some verifiedFrontendPackSemanticsKernel := by
  unfold ArtifactPackContextChecker.checkArtifactPackSemantics?
  rw [verifiedFrontendPackStructuralKernel_eq]
  rw [verifiedFrontendPackDecodedKernel_eq]
  rw [verifiedFrontendPackContextKernel_eq]
  rw [verifiedFrontendPackUnitsKernel_eq]
  rfl

theorem verifiedFrontendPack_semantics_checked_kernel :
    (ArtifactPackContextChecker.checkArtifactPackSemantics?
      verifiedFrontendPack).isSome = true := by
  rw [verifiedFrontendPackSemanticsKernel_eq]
  rfl

end Lanius.Extraction
