import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructExactCell0

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_item14_beq_self_kernel :
    (verifiedFrontendLexerProposedItem14Kernel ==
      verifiedFrontendLexerProposedItem14Kernel) = true := by
  simp [verifiedFrontendLexerProposedItem14Kernel,
    verifiedFrontendLexerProposedItemsKernel,
    verifiedFrontendLexerProposedKernel,
    verifiedFrontendLexerArtifact]

end Lanius.Extraction
