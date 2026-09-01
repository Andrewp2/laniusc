import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructCompactAssemblyCell5

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_cell_proposed_items_drop4_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 4 =
      verifiedFrontendLexerProposedItem4Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 5 := by
  rfl

theorem verifiedFrontendLexer_cell_items_node4_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6985 = some 1 := by
  cbv

theorem verifiedFrontendLexer_cell_items_node4_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6985 0 = some 121 := by
  cbv

theorem verifiedFrontendLexer_cell_items_node4_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6985 1 = some 6984 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_cell4_kernel :
    (reconstructItems 6987 verifiedFrontendLexerArtifact 6985).run 18 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 4, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_cell_items_node4_production_kernel,
    verifiedFrontendLexer_cell_items_node4_item_kernel,
    verifiedFrontendLexer_cell_items_node4_rest_kernel,
    verifiedFrontendLexer_reconstruct_item4_kernel,
    verifiedFrontendLexer_reconstruct_items_cell5_kernel,
    verifiedFrontendLexer_cell_proposed_items_drop4_kernel]

end Lanius.Extraction

