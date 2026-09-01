import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructCompactAssemblyCell2

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_cell_proposed_items_drop1_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 1 =
      verifiedFrontendLexerProposedItem1Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 2 := by
  rfl

theorem verifiedFrontendLexer_cell_items_node1_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6988 = some 1 := by
  cbv

theorem verifiedFrontendLexer_cell_items_node1_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6988 0 = some 16 := by
  cbv

theorem verifiedFrontendLexer_cell_items_node1_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6988 1 = some 6987 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_cell1_kernel :
    (reconstructItems 6990 verifiedFrontendLexerArtifact 6988).run 4 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 1, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_cell_items_node1_production_kernel,
    verifiedFrontendLexer_cell_items_node1_item_kernel,
    verifiedFrontendLexer_cell_items_node1_rest_kernel,
    verifiedFrontendLexer_reconstruct_item1_kernel,
    verifiedFrontendLexer_reconstruct_items_cell2_kernel,
    verifiedFrontendLexer_cell_proposed_items_drop1_kernel]

end Lanius.Extraction

