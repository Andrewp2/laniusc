import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructResultPresent

namespace Lanius.Extraction

theorem verifiedFrontendLexer_reconstruction_agrees_kernel :
    (verifiedFrontendLexerProposedKernel ==
      verifiedFrontendLexerReconstructedKernel) = true := by
  rw [verifiedFrontendLexer_proposed_eq_reconstructed_kernel]
  exact beq_self_eq_true verifiedFrontendLexerReconstructedKernel

end Lanius.Extraction
