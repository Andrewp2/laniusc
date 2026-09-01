import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructCompactAssemblyCell16

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_cell_proposed_items_drop15_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 15 =
      verifiedFrontendLexerProposedItem15Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 16 := by
  rfl

theorem verifiedFrontendLexer_cell_items_node15_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6974 = some 1 := by
  cbv

theorem verifiedFrontendLexer_cell_items_node15_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6974 0 = some 4012 := by
  cbv

theorem verifiedFrontendLexer_cell_items_node15_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6974 1 = some 6973 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_cell15_kernel :
    (reconstructItems 6976 verifiedFrontendLexerArtifact 6974).run 567 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 15, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_cell_items_node15_production_kernel,
    verifiedFrontendLexer_cell_items_node15_item_kernel,
    verifiedFrontendLexer_cell_items_node15_rest_kernel,
    verifiedFrontendLexer_reconstruct_item15_kernel,
    verifiedFrontendLexer_reconstruct_items_cell16_kernel,
    verifiedFrontendLexer_cell_proposed_items_drop15_kernel]

end Lanius.Extraction

