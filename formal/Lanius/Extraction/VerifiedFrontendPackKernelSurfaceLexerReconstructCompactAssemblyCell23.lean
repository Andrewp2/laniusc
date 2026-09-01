import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructCompactAssemblyCell24

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_cell_proposed_items_drop23_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 23 =
      verifiedFrontendLexerProposedItem23Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 24 := by
  rfl

theorem verifiedFrontendLexer_cell_items_node23_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6966 = some 1 := by
  cbv

theorem verifiedFrontendLexer_cell_items_node23_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6966 0 = some 5714 := by
  cbv

theorem verifiedFrontendLexer_cell_items_node23_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6966 1 = some 6965 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_cell23_kernel :
    (reconstructItems 6968 verifiedFrontendLexerArtifact 6966).run 771 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 23, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_cell_items_node23_production_kernel,
    verifiedFrontendLexer_cell_items_node23_item_kernel,
    verifiedFrontendLexer_cell_items_node23_rest_kernel,
    verifiedFrontendLexer_reconstruct_item23_kernel,
    verifiedFrontendLexer_reconstruct_items_cell24_kernel,
    verifiedFrontendLexer_cell_proposed_items_drop23_kernel]

end Lanius.Extraction

