import Lanius.Extraction.VerifiedFrontend.Surface.Lexer.Reconstruction.View
import Lanius.Extraction.SurfaceCheckerProvenance

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

def verifiedFrontendLexerReconstructedKernel : SurfaceFile :=
  verifiedFrontendLexerProposedKernel

theorem verifiedFrontendLexerReconstructedKernel_eq :
    reconstructArtifactSurfaceView verifiedFrontendLexerArtifact
      verifiedFrontendLexerView = some verifiedFrontendLexerReconstructedKernel :=
  verifiedFrontendLexer_reconstructed_view_kernel

theorem verifiedFrontendLexer_claims_present_kernel :
    (collectSurfaceClaimsFrom verifiedFrontendLexerArtifact
      verifiedFrontendLexerReconstructedKernel).isSome = true := by
  with_unfolding_all rfl

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
    collectSurfaceClaimsView verifiedFrontendLexerArtifact
        verifiedFrontendLexerView = some verifiedFrontendLexerClaimsKernel := by
  unfold collectSurfaceClaimsView
  rw [verifiedFrontendLexerReconstructedKernel_eq]
  exact verifiedFrontendLexerClaimsFromKernel_eq

theorem verifiedFrontendLexer_surface_present_kernel :
    (decodeSurfaceFile (verifiedFrontendLexerArtifact.parse_nodes.length + 1)
      verifiedFrontendLexerReconstructedKernel).isSome = true := by
  with_unfolding_all rfl

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
    decodeReconstructedSurfaceView verifiedFrontendLexerArtifact
      verifiedFrontendLexerView = some verifiedFrontendLexerSurfaceFileKernel := by
  unfold decodeReconstructedSurfaceView
  rw [verifiedFrontendLexerReconstructedKernel_eq]
  exact verifiedFrontendLexerSurfaceFileFromKernel_eq

end Lanius.Extraction
