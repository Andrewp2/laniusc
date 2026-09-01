import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructGroup4

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_proposed_item25_present_kernel :
    (verifiedFrontendLexerProposedItemsKernel[25]?).isSome = true := by
  cbv

def verifiedFrontendLexerProposedItem25Kernel :=
  (verifiedFrontendLexerProposedItemsKernel[25]?).get
    verifiedFrontendLexer_proposed_item25_present_kernel

theorem verifiedFrontendLexer_reconstruct_item25_kernel :
    (reconstructItem 6965 verifiedFrontendLexerArtifact 6118).run 931 =
      some (verifiedFrontendLexerProposedItem25Kernel, 963) := by
  cbv

theorem verifiedFrontendLexer_proposed_item26_present_kernel :
    (verifiedFrontendLexerProposedItemsKernel[26]?).isSome = true := by
  cbv

def verifiedFrontendLexerProposedItem26Kernel :=
  (verifiedFrontendLexerProposedItemsKernel[26]?).get
    verifiedFrontendLexer_proposed_item26_present_kernel

theorem verifiedFrontendLexer_reconstruct_item26_kernel :
    (reconstructItem 6964 verifiedFrontendLexerArtifact 6417).run 963 =
      some (verifiedFrontendLexerProposedItem26Kernel, 1017) := by
  cbv

theorem verifiedFrontendLexer_proposed_item27_present_kernel :
    (verifiedFrontendLexerProposedItemsKernel[27]?).isSome = true := by
  cbv

def verifiedFrontendLexerProposedItem27Kernel :=
  (verifiedFrontendLexerProposedItemsKernel[27]?).get
    verifiedFrontendLexer_proposed_item27_present_kernel

theorem verifiedFrontendLexer_reconstruct_item27_kernel :
    (reconstructItem 6963 verifiedFrontendLexerArtifact 6960).run 1017 =
      some (verifiedFrontendLexerProposedItem27Kernel, 1107) := by
  cbv

end Lanius.Extraction

