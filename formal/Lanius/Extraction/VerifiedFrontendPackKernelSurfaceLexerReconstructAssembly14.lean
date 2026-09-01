import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructAssembly3

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_items_node14_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6975 = some 1 := by
  cbv

theorem verifiedFrontendLexer_items_node14_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6975 0 = some 3692 := by
  cbv

theorem verifiedFrontendLexer_items_node14_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6975 1 = some 6974 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items14_kernel :
    (reconstructItems 6977 verifiedFrontendLexerArtifact 6975).run 309 =
      some ([verifiedFrontendLexerProposedItem14Kernel, verifiedFrontendLexerProposedItem15Kernel, verifiedFrontendLexerProposedItem16Kernel, verifiedFrontendLexerProposedItem17Kernel, verifiedFrontendLexerProposedItem18Kernel, verifiedFrontendLexerProposedItem19Kernel, verifiedFrontendLexerProposedItem20Kernel, verifiedFrontendLexerProposedItem21Kernel, verifiedFrontendLexerProposedItem22Kernel, verifiedFrontendLexerProposedItem23Kernel, verifiedFrontendLexerProposedItem24Kernel, verifiedFrontendLexerProposedItem25Kernel, verifiedFrontendLexerProposedItem26Kernel, verifiedFrontendLexerProposedItem27Kernel], 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_items_node14_production_kernel,
    verifiedFrontendLexer_items_node14_item_kernel,
    verifiedFrontendLexer_items_node14_rest_kernel,
    verifiedFrontendLexer_reconstruct_item14_kernel,
    verifiedFrontendLexer_reconstruct_items15_kernel]

end Lanius.Extraction

