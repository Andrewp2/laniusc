import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructCompactAssemblyCell1

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_cell_proposed_items_drop0_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 0 =
      verifiedFrontendLexerProposedItem0Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 1 := by
  rfl

theorem verifiedFrontendLexer_cell_items_node0_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6989 = some 1 := by
  cbv

theorem verifiedFrontendLexer_cell_items_node0_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6989 0 = some 6 := by
  cbv

theorem verifiedFrontendLexer_cell_items_node0_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6989 1 = some 6988 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_cell0_kernel :
    (reconstructItems 6991 verifiedFrontendLexerArtifact 6989).run 0 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 0, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_cell_items_node0_production_kernel,
    verifiedFrontendLexer_cell_items_node0_item_kernel,
    verifiedFrontendLexer_cell_items_node0_rest_kernel,
    verifiedFrontendLexer_reconstruct_item0_kernel,
    verifiedFrontendLexer_reconstruct_items_cell1_kernel,
    verifiedFrontendLexer_cell_proposed_items_drop0_kernel]

end Lanius.Extraction

