import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructBase

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_proposed_item14_present_kernel :
    (verifiedFrontendLexerProposedItemsKernel[14]?).isSome = true := by
  cbv

def verifiedFrontendLexerProposedItem14Kernel :=
  (verifiedFrontendLexerProposedItemsKernel[14]?).get
    verifiedFrontendLexer_proposed_item14_present_kernel

theorem verifiedFrontendLexer_reconstruct_item14_kernel :
    (reconstructItem 6976 verifiedFrontendLexerArtifact 3692).run 309 =
      some (verifiedFrontendLexerProposedItem14Kernel, 567) := by
  cbv

end Lanius.Extraction
