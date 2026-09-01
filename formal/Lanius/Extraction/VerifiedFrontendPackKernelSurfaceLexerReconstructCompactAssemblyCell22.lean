import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructCompactAssemblyCell23

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_cell_proposed_items_drop22_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 22 =
      verifiedFrontendLexerProposedItem22Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 23 := by
  rfl

theorem verifiedFrontendLexer_cell_items_node22_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6967 = some 1 := by
  cbv

theorem verifiedFrontendLexer_cell_items_node22_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6967 0 = some 4826 := by
  cbv

theorem verifiedFrontendLexer_cell_items_node22_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6967 1 = some 6966 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_cell22_kernel :
    (reconstructItems 6969 verifiedFrontendLexerArtifact 6967).run 751 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 22, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_cell_items_node22_production_kernel,
    verifiedFrontendLexer_cell_items_node22_item_kernel,
    verifiedFrontendLexer_cell_items_node22_rest_kernel,
    verifiedFrontendLexer_reconstruct_item22_kernel,
    verifiedFrontendLexer_reconstruct_items_cell23_kernel,
    verifiedFrontendLexer_cell_proposed_items_drop22_kernel]

end Lanius.Extraction

