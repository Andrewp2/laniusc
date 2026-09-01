import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructCompactAssemblyCell9

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_cell_proposed_items_drop8_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 8 =
      verifiedFrontendLexerProposedItem8Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 9 := by
  rfl

theorem verifiedFrontendLexer_cell_items_node8_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6981 = some 1 := by
  cbv

theorem verifiedFrontendLexer_cell_items_node8_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6981 0 = some 261 := by
  cbv

theorem verifiedFrontendLexer_cell_items_node8_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6981 1 = some 6980 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_cell8_kernel :
    (reconstructItems 6983 verifiedFrontendLexerArtifact 6981).run 38 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 8, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_cell_items_node8_production_kernel,
    verifiedFrontendLexer_cell_items_node8_item_kernel,
    verifiedFrontendLexer_cell_items_node8_rest_kernel,
    verifiedFrontendLexer_reconstruct_item8_kernel,
    verifiedFrontendLexer_reconstruct_items_cell9_kernel,
    verifiedFrontendLexer_cell_proposed_items_drop8_kernel]

end Lanius.Extraction

