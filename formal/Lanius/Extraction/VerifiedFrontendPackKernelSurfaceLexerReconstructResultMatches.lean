import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructResultAgreement

namespace Lanius.Extraction

theorem verifiedFrontendLexer_reconstruction_matches_kernel :
    surfaceReconstructionMatches verifiedFrontendLexerArtifact = true := by
  unfold surfaceReconstructionMatches
  rw [verifiedFrontendLexerProposedKernel_eq]
  rw [verifiedFrontendLexerReconstructedKernel_eq]
  exact verifiedFrontendLexer_reconstruction_agrees_kernel

end Lanius.Extraction
