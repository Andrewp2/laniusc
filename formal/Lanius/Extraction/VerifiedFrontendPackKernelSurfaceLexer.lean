import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerClaims

namespace Lanius.Extraction

def verifiedFrontendLexerSurfaceKernel :
    CheckedSurfaceArtifact verifiedFrontendLexerArtifact := {
  reconstructed := verifiedFrontendLexerReconstructedKernel
  reconstructedFound := verifiedFrontendLexerReconstructedKernel_eq
  claims := verifiedFrontendLexerClaimsKernel
  claimsFound := verifiedFrontendLexerClaimsKernel_eq
  surface := verifiedFrontendLexerSurfaceFileKernel
  surfaceFound := verifiedFrontendLexerSurfaceFileKernel_eq
  valid := ⟨verifiedFrontendLexerParseValidKernel,
    verifiedFrontendLexer_parse_node_chunks_valid_kernel,
    verifiedFrontendLexerClaimsKernel,
    verifiedFrontendLexerSurfaceFileKernel,
    verifiedFrontendLexerClaimsKernel_eq,
    verifiedFrontendLexerSurfaceFileKernel_eq,
    surfaceClaimsValidCached_sound
      verifiedFrontendLexer_parse_node_chunks_valid_kernel
      verifiedFrontendLexer_claims_valid_kernel⟩
}

theorem verifiedFrontendLexerSurfaceKernel_eq :
    checkSurfaceArtifactCached? verifiedFrontendLexerArtifact =
      some verifiedFrontendLexerSurfaceKernel := by
  unfold checkSurfaceArtifactCached?
  rw [verifiedFrontendLexer_parse_checked_kernel]
  rw [verifiedFrontendLexer_parse_node_chunks_match_kernel]
  rw [verifiedFrontendLexerReconstructedKernel_eq]
  rw [verifiedFrontendLexerClaimsFromKernel_eq]
  rw [verifiedFrontendLexerSurfaceFileFromKernel_eq]
  rw [verifiedFrontendLexer_claims_valid_kernel]
  rfl

theorem verifiedFrontendLexer_surface_checked_kernel :
    (checkSurfaceArtifactCached? verifiedFrontendLexerArtifact).isSome = true := by
  rw [verifiedFrontendLexerSurfaceKernel_eq]
  rfl

end Lanius.Extraction
