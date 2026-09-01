import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructLength

namespace Lanius.Extraction

set_option maxRecDepth 100000

theorem verifiedFrontendLexerReconstructedKernel_eq :
    reconstructArtifactSurface verifiedFrontendLexerArtifact =
      some verifiedFrontendLexerReconstructedKernel := by
  unfold reconstructArtifactSurface
  rw [verifiedFrontendLexer_parse_root_value_kernel]
  rw [verifiedFrontendLexer_parse_nodes_length_kernel]
  simp [verifiedFrontendLexer_reconstruct_file_kernel]

theorem verifiedFrontendLexer_reconstructed_present_kernel :
    (reconstructArtifactSurface verifiedFrontendLexerArtifact).isSome = true := by
  rw [verifiedFrontendLexerReconstructedKernel_eq]
  rfl

theorem verifiedFrontendLexer_reconstruction_agrees_kernel :
    verifiedFrontendLexerProposedKernel ==
      verifiedFrontendLexerReconstructedKernel = true := by
  rw [verifiedFrontendLexer_proposed_eq_reconstructed_kernel]
  exact beq_self_eq_true verifiedFrontendLexerReconstructedKernel

theorem verifiedFrontendLexer_reconstruction_matches_kernel :
    surfaceReconstructionMatches verifiedFrontendLexerArtifact = true := by
  unfold surfaceReconstructionMatches
  rw [verifiedFrontendLexerProposedKernel_eq]
  rw [verifiedFrontendLexerReconstructedKernel_eq]
  exact verifiedFrontendLexer_reconstruction_agrees_kernel

end Lanius.Extraction
