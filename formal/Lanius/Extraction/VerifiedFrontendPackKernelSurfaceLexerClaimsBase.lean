import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstruct
import Lanius.Extraction.SurfaceChecker

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_claims_present_kernel :
    (collectSurfaceClaimsFrom verifiedFrontendLexerArtifact
      verifiedFrontendLexerReconstructedKernel).isSome = true := by
  cbv

def verifiedFrontendLexerClaimsKernel :=
  (collectSurfaceClaimsFrom verifiedFrontendLexerArtifact
    verifiedFrontendLexerReconstructedKernel).get
      verifiedFrontendLexer_claims_present_kernel

theorem verifiedFrontendLexerClaimsFromKernel_eq :
    collectSurfaceClaimsFrom verifiedFrontendLexerArtifact
        verifiedFrontendLexerReconstructedKernel =
      some verifiedFrontendLexerClaimsKernel := by
  generalize found : collectSurfaceClaimsFrom verifiedFrontendLexerArtifact
    verifiedFrontendLexerReconstructedKernel = result
  cases result <;> simp_all [verifiedFrontendLexerClaimsKernel]

theorem verifiedFrontendLexerClaimsKernel_eq :
    collectSurfaceClaims verifiedFrontendLexerArtifact =
      some verifiedFrontendLexerClaimsKernel := by
  unfold collectSurfaceClaims
  rw [verifiedFrontendLexerReconstructedKernel_eq]
  exact verifiedFrontendLexerClaimsFromKernel_eq

theorem verifiedFrontendLexer_surface_present_kernel :
    (decodeSurfaceFile (verifiedFrontendLexerArtifact.parse_nodes.length + 1)
      verifiedFrontendLexerReconstructedKernel).isSome = true := by
  cbv

def verifiedFrontendLexerSurfaceFileKernel :=
  (decodeSurfaceFile (verifiedFrontendLexerArtifact.parse_nodes.length + 1)
    verifiedFrontendLexerReconstructedKernel).get
      verifiedFrontendLexer_surface_present_kernel

theorem verifiedFrontendLexerSurfaceFileFromKernel_eq :
    decodeSurfaceFile (verifiedFrontendLexerArtifact.parse_nodes.length + 1)
        verifiedFrontendLexerReconstructedKernel =
      some verifiedFrontendLexerSurfaceFileKernel := by
  generalize found : decodeSurfaceFile
    (verifiedFrontendLexerArtifact.parse_nodes.length + 1)
    verifiedFrontendLexerReconstructedKernel = result
  cases result <;> simp_all [verifiedFrontendLexerSurfaceFileKernel]

theorem verifiedFrontendLexerSurfaceFileKernel_eq :
    decodeReconstructedSurface verifiedFrontendLexerArtifact =
      some verifiedFrontendLexerSurfaceFileKernel := by
  unfold decodeReconstructedSurface
  rw [verifiedFrontendLexerReconstructedKernel_eq]
  exact verifiedFrontendLexerSurfaceFileFromKernel_eq

end Lanius.Extraction
