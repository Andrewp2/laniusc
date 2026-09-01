import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructCompactAssemblyCell3

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_cell_proposed_items_drop2_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 2 =
      verifiedFrontendLexerProposedItem2Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 3 := by
  rfl

theorem verifiedFrontendLexer_cell_items_node2_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6987 = some 1 := by
  cbv

theorem verifiedFrontendLexer_cell_items_node2_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6987 0 = some 51 := by
  cbv

theorem verifiedFrontendLexer_cell_items_node2_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6987 1 = some 6986 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_cell2_kernel :
    (reconstructItems 6989 verifiedFrontendLexerArtifact 6987).run 8 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 2, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_cell_items_node2_production_kernel,
    verifiedFrontendLexer_cell_items_node2_item_kernel,
    verifiedFrontendLexer_cell_items_node2_rest_kernel,
    verifiedFrontendLexer_reconstruct_item2_kernel,
    verifiedFrontendLexer_reconstruct_items_cell3_kernel,
    verifiedFrontendLexer_cell_proposed_items_drop2_kernel]

end Lanius.Extraction

