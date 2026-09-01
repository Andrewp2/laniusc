import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructCompactAssemblyCell10

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_cell_proposed_items_drop9_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 9 =
      verifiedFrontendLexerProposedItem9Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 10 := by
  rfl

theorem verifiedFrontendLexer_cell_items_node9_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6980 = some 1 := by
  cbv

theorem verifiedFrontendLexer_cell_items_node9_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6980 0 = some 477 := by
  cbv

theorem verifiedFrontendLexer_cell_items_node9_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6980 1 = some 6979 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_cell9_kernel :
    (reconstructItems 6982 verifiedFrontendLexerArtifact 6980).run 43 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 9, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_cell_items_node9_production_kernel,
    verifiedFrontendLexer_cell_items_node9_item_kernel,
    verifiedFrontendLexer_cell_items_node9_rest_kernel,
    verifiedFrontendLexer_reconstruct_item9_kernel,
    verifiedFrontendLexer_reconstruct_items_cell10_kernel,
    verifiedFrontendLexer_cell_proposed_items_drop9_kernel]

end Lanius.Extraction

