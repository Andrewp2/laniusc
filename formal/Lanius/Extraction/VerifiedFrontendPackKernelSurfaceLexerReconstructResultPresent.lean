import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructResultEq

namespace Lanius.Extraction

theorem verifiedFrontendLexer_reconstructed_present_kernel :
    (reconstructArtifactSurface verifiedFrontendLexerArtifact).isSome = true := by
  rw [verifiedFrontendLexerReconstructedKernel_eq]
  rfl

end Lanius.Extraction
