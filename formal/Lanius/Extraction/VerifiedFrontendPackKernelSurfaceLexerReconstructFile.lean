import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructRootChild

namespace Lanius.Extraction

theorem verifiedFrontendLexer_reconstruct_file_kernel :
    (reconstructFile 6992 verifiedFrontendLexerArtifact 6990).run 0 =
      some (verifiedFrontendLexerReconstructedKernel, 1108) := by
  unfold verifiedFrontendLexerReconstructedKernel
  exact reconstructFile_step
    verifiedFrontendLexer_root_production_kernel
    verifiedFrontendLexer_root_items_child_kernel
    verifiedFrontendLexer_reconstruct_items_exact0_kernel

end Lanius.Extraction
