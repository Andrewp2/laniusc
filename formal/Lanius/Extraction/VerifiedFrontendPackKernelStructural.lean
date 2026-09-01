import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceData
import Lanius.Extraction.VerifiedFrontendPackKernelDense
import Lanius.Extraction.VerifiedFrontendPackKernelCanonical
import Lanius.Extraction.VerifiedFrontendPackKernelTyped

namespace Lanius.Extraction

def verifiedFrontendPackStructuralKernel :
    ArtifactPackChecker.CheckedArtifactPack verifiedFrontendPack := {
  schema := rfl
  surfaceData := verifiedFrontendPackSurfaceDataKernel
  surfaces := verifiedFrontendPackSurfaceDataKernel.valid
  wire := verifiedFrontendPackWireKernel
  merged := verifiedFrontendPackWireKernel_eq
  nodeIdsDense := ArtifactPackChecker.coreNodeIdsDense_sound
    verifiedFrontendPack_dense_checked_kernel
  valuesCanonical := verifiedFrontendPack_canonical_checked_kernel
  program := CoreDecode.program verifiedFrontendPackWireKernel
  decoded := rfl
  wellTyped := verifiedFrontendPackTypedKernel.proof
}

theorem verifiedFrontendPackStructuralKernel_eq :
    ArtifactPackChecker.checkArtifactPack? verifiedFrontendPack =
      some verifiedFrontendPackStructuralKernel := by
  unfold ArtifactPackChecker.checkArtifactPack?
  rw [verifiedFrontendPackSurfaceDataKernel_eq]
  rw [verifiedFrontendPackWireKernel_eq]
  simp only [verifiedFrontendPack_dense_checked_kernel, if_true,
    verifiedFrontendPack_canonical_checked_kernel]
  rw [verifiedFrontendPackTypedKernel_eq]
  rfl

theorem verifiedFrontendPack_structural_checked_kernel :
    (ArtifactPackChecker.checkArtifactPack? verifiedFrontendPack).isSome = true := by
  rw [verifiedFrontendPackStructuralKernel_eq]
  rfl

end Lanius.Extraction
