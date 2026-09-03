import Lanius.Extraction.VerifiedFrontend.Surface.Data
import Lanius.Extraction.VerifiedFrontend.Assembly.Dense
import Lanius.Extraction.VerifiedFrontend.Assembly.Canonical
import Lanius.Extraction.VerifiedFrontend.Typing.Trace
import Lanius.Extraction.CoreChecker

namespace Lanius.Extraction

def verifiedFrontendPackStructuralKernel :
    ArtifactPackChecker.CheckedArtifactPack verifiedFrontendPack := {
  schema := rfl
  surfaceData := verifiedFrontendPackSurfaceDataKernel
  surfaces := verifiedFrontendPackSurfaceDataKernel.valid
  wire := verifiedFrontendPackWireKernel
  merged := verifiedFrontendPackWireKernel_eq
  nodeIdsDense := coreNodeIdsDense_sound
    verifiedFrontendPack_dense_checked_kernel
  valuesCanonical := verifiedFrontendPack_canonical_checked_kernel
  program := CoreDecode.program verifiedFrontendPackWireKernel
  decoded := rfl
  wellTyped := verifiedFrontendPackTypedKernel.proof
}

theorem verifiedFrontendPack_structural_checked_kernel :
    Nonempty (ArtifactPackChecker.CheckedArtifactPack verifiedFrontendPack) :=
  ⟨verifiedFrontendPackStructuralKernel⟩

end Lanius.Extraction
