import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructCompactAssemblyCell8

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_cell_proposed_items_drop7_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 7 =
      verifiedFrontendLexerProposedItem7Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 8 := by
  rfl

theorem verifiedFrontendLexer_cell_items_node7_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6982 = some 1 := by
  cbv

theorem verifiedFrontendLexer_cell_items_node7_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6982 0 = some 226 := by
  cbv

theorem verifiedFrontendLexer_cell_items_node7_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6982 1 = some 6981 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_cell7_kernel :
    (reconstructItems 6984 verifiedFrontendLexerArtifact 6982).run 33 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 7, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_cell_items_node7_production_kernel,
    verifiedFrontendLexer_cell_items_node7_item_kernel,
    verifiedFrontendLexer_cell_items_node7_rest_kernel,
    verifiedFrontendLexer_reconstruct_item7_kernel,
    verifiedFrontendLexer_reconstruct_items_cell8_kernel,
    verifiedFrontendLexer_cell_proposed_items_drop7_kernel]

end Lanius.Extraction

