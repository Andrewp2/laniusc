import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructCompactAssemblyCell17

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_cell_proposed_items_drop16_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 16 =
      verifiedFrontendLexerProposedItem16Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 17 := by
  rfl

theorem verifiedFrontendLexer_cell_items_node16_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6973 = some 1 := by
  cbv

theorem verifiedFrontendLexer_cell_items_node16_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6973 0 = some 4332 := by
  cbv

theorem verifiedFrontendLexer_cell_items_node16_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6973 1 = some 6972 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_cell16_kernel :
    (reconstructItems 6975 verifiedFrontendLexerArtifact 6973).run 623 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 16, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_cell_items_node16_production_kernel,
    verifiedFrontendLexer_cell_items_node16_item_kernel,
    verifiedFrontendLexer_cell_items_node16_rest_kernel,
    verifiedFrontendLexer_reconstruct_item16_kernel,
    verifiedFrontendLexer_reconstruct_items_cell17_kernel,
    verifiedFrontendLexer_cell_proposed_items_drop16_kernel]

end Lanius.Extraction

