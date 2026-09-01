import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructGroup3

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_proposed_item22_present_kernel :
    (verifiedFrontendLexerProposedItemsKernel[22]?).isSome = true := by
  cbv

def verifiedFrontendLexerProposedItem22Kernel :=
  (verifiedFrontendLexerProposedItemsKernel[22]?).get
    verifiedFrontendLexer_proposed_item22_present_kernel

theorem verifiedFrontendLexer_reconstruct_item22_kernel :
    (reconstructItem 6968 verifiedFrontendLexerArtifact 4826).run 751 =
      some (verifiedFrontendLexerProposedItem22Kernel, 771) := by
  cbv

theorem verifiedFrontendLexer_proposed_item23_present_kernel :
    (verifiedFrontendLexerProposedItemsKernel[23]?).isSome = true := by
  cbv

def verifiedFrontendLexerProposedItem23Kernel :=
  (verifiedFrontendLexerProposedItemsKernel[23]?).get
    verifiedFrontendLexer_proposed_item23_present_kernel

theorem verifiedFrontendLexer_reconstruct_item23_kernel :
    (reconstructItem 6967 verifiedFrontendLexerArtifact 5714).run 771 =
      some (verifiedFrontendLexerProposedItem23Kernel, 899) := by
  cbv

theorem verifiedFrontendLexer_proposed_item24_present_kernel :
    (verifiedFrontendLexerProposedItemsKernel[24]?).isSome = true := by
  cbv

def verifiedFrontendLexerProposedItem24Kernel :=
  (verifiedFrontendLexerProposedItemsKernel[24]?).get
    verifiedFrontendLexer_proposed_item24_present_kernel

theorem verifiedFrontendLexer_reconstruct_item24_kernel :
    (reconstructItem 6966 verifiedFrontendLexerArtifact 5916).run 899 =
      some (verifiedFrontendLexerProposedItem24Kernel, 931) := by
  cbv

end Lanius.Extraction

