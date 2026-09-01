import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructCompactAssemblyCell11

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_cell_proposed_items_drop10_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 10 =
      verifiedFrontendLexerProposedItem10Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 11 := by
  rfl

theorem verifiedFrontendLexer_cell_items_node10_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6979 = some 1 := by
  cbv

theorem verifiedFrontendLexer_cell_items_node10_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6979 0 = some 627 := by
  cbv

theorem verifiedFrontendLexer_cell_items_node10_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6979 1 = some 6978 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_cell10_kernel :
    (reconstructItems 6981 verifiedFrontendLexerArtifact 6979).run 81 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 10, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_cell_items_node10_production_kernel,
    verifiedFrontendLexer_cell_items_node10_item_kernel,
    verifiedFrontendLexer_cell_items_node10_rest_kernel,
    verifiedFrontendLexer_reconstruct_item10_kernel,
    verifiedFrontendLexer_reconstruct_items_cell11_kernel,
    verifiedFrontendLexer_cell_proposed_items_drop10_kernel]

end Lanius.Extraction

