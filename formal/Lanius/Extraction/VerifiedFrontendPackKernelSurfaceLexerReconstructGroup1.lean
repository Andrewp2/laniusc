import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructGroup0

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_proposed_item13_present_kernel :
    (verifiedFrontendLexerProposedItemsKernel[13]?).isSome = true := by
  cbv

def verifiedFrontendLexerProposedItem13Kernel :=
  (verifiedFrontendLexerProposedItemsKernel[13]?).get
    verifiedFrontendLexer_proposed_item13_present_kernel

theorem verifiedFrontendLexer_reconstruct_item13_kernel :
    (reconstructItem 6977 verifiedFrontendLexerArtifact 1905).run 157 =
      some (verifiedFrontendLexerProposedItem13Kernel, 309) := by
  cbv

end Lanius.Extraction

