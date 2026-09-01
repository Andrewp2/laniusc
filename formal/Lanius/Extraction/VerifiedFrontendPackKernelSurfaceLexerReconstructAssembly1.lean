import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructAssembly14

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_items_node13_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6976 = some 1 := by
  cbv

theorem verifiedFrontendLexer_items_node13_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6976 0 = some 1905 := by
  cbv

theorem verifiedFrontendLexer_items_node13_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6976 1 = some 6975 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items13_kernel :
    (reconstructItems 6978 verifiedFrontendLexerArtifact 6976).run 157 =
      some ([verifiedFrontendLexerProposedItem13Kernel, verifiedFrontendLexerProposedItem14Kernel, verifiedFrontendLexerProposedItem15Kernel, verifiedFrontendLexerProposedItem16Kernel, verifiedFrontendLexerProposedItem17Kernel, verifiedFrontendLexerProposedItem18Kernel, verifiedFrontendLexerProposedItem19Kernel, verifiedFrontendLexerProposedItem20Kernel, verifiedFrontendLexerProposedItem21Kernel, verifiedFrontendLexerProposedItem22Kernel, verifiedFrontendLexerProposedItem23Kernel, verifiedFrontendLexerProposedItem24Kernel, verifiedFrontendLexerProposedItem25Kernel, verifiedFrontendLexerProposedItem26Kernel, verifiedFrontendLexerProposedItem27Kernel], 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_items_node13_production_kernel,
    verifiedFrontendLexer_items_node13_item_kernel,
    verifiedFrontendLexer_items_node13_rest_kernel,
    verifiedFrontendLexer_reconstruct_item13_kernel,
    verifiedFrontendLexer_reconstruct_items14_kernel]

end Lanius.Extraction

