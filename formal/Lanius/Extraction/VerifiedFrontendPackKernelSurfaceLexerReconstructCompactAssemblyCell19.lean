import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructCompactAssemblyCell20

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_cell_proposed_items_drop19_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 19 =
      verifiedFrontendLexerProposedItem19Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 20 := by
  rfl

theorem verifiedFrontendLexer_cell_items_node19_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6970 = some 1 := by
  cbv

theorem verifiedFrontendLexer_cell_items_node19_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6970 0 = some 4474 := by
  cbv

theorem verifiedFrontendLexer_cell_items_node19_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6970 1 = some 6969 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_cell19_kernel :
    (reconstructItems 6972 verifiedFrontendLexerArtifact 6970).run 705 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 19, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_cell_items_node19_production_kernel,
    verifiedFrontendLexer_cell_items_node19_item_kernel,
    verifiedFrontendLexer_cell_items_node19_rest_kernel,
    verifiedFrontendLexer_reconstruct_item19_kernel,
    verifiedFrontendLexer_reconstruct_items_cell20_kernel,
    verifiedFrontendLexer_cell_proposed_items_drop19_kernel]

end Lanius.Extraction

