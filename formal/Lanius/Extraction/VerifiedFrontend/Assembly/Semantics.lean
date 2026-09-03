import Lanius.Extraction.VerifiedFrontend.Assembly.Units.Assembly

namespace Lanius.Extraction

def verifiedFrontendPackSemanticsKernel :
    ArtifactPackContextChecker.CheckedArtifactPackSemantics
      verifiedFrontendPack := {
  structural := verifiedFrontendPackStructuralKernel
  decoded := verifiedFrontendPackDecodedKernel
  context := verifiedFrontendPackContextKernel
  unitsChecked := verifiedFrontendPackUnitsKernel.proof
}

theorem verifiedFrontendPack_semantics_checked_kernel :
    Nonempty
      (ArtifactPackContextChecker.CheckedArtifactPackSemantics
        verifiedFrontendPack) :=
  ⟨verifiedFrontendPackSemanticsKernel⟩

end Lanius.Extraction
