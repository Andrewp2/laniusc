import Lanius.Extraction.VerifiedFrontend.Assembly.Structural
import Lanius.Extraction.VerifiedFrontend.Decoded.Trace

namespace Lanius.Extraction

set_option maxRecDepth 100000

def verifiedFrontendPackDecodedKernel := verifiedFrontendPackDecodedExplicitKernel

theorem verifiedFrontendPackDecodedKernel_eq :
    ArtifactPackContextChecker.decodePackUnitsFromCached 0
        verifiedFrontendPack.units
        verifiedFrontendPackStructuralKernel.surfaceData =
      some verifiedFrontendPackDecodedKernel := by
  unfold verifiedFrontendPack verifiedFrontendPackStructuralKernel
    verifiedFrontendPackSurfaceDataKernel verifiedFrontendPackDecodedKernel
  rw [← verifiedFrontendPack_decoded_tail0_explicit_kernel]
  exact verifiedFrontendPack_decoded_tail0_found_kernel

theorem verifiedFrontendPack_decoded_checked_kernel :
    (ArtifactPackContextChecker.decodePackUnitsFromCached 0
      verifiedFrontendPack.units
      verifiedFrontendPackStructuralKernel.surfaceData).isSome = true := by
  rw [verifiedFrontendPackDecodedKernel_eq]
  rfl

end Lanius.Extraction
