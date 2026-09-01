import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructCompactAssemblyCell4

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_cell_proposed_items_drop3_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 3 =
      verifiedFrontendLexerProposedItem3Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 4 := by
  rfl

theorem verifiedFrontendLexer_cell_items_node3_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6986 = some 1 := by
  cbv

theorem verifiedFrontendLexer_cell_items_node3_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6986 0 = some 86 := by
  cbv

theorem verifiedFrontendLexer_cell_items_node3_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6986 1 = some 6985 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_cell3_kernel :
    (reconstructItems 6988 verifiedFrontendLexerArtifact 6986).run 13 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 3, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_cell_items_node3_production_kernel,
    verifiedFrontendLexer_cell_items_node3_item_kernel,
    verifiedFrontendLexer_cell_items_node3_rest_kernel,
    verifiedFrontendLexer_reconstruct_item3_kernel,
    verifiedFrontendLexer_reconstruct_items_cell4_kernel,
    verifiedFrontendLexer_cell_proposed_items_drop3_kernel]

end Lanius.Extraction

