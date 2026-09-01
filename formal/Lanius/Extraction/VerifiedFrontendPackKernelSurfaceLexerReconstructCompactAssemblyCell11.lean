import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructCompactAssemblyCell12

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_cell_proposed_items_drop11_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 11 =
      verifiedFrontendLexerProposedItem11Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 12 := by
  rfl

theorem verifiedFrontendLexer_cell_items_node11_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6978 = some 1 := by
  cbv

theorem verifiedFrontendLexer_cell_items_node11_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6978 0 = some 729 := by
  cbv

theorem verifiedFrontendLexer_cell_items_node11_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6978 1 = some 6977 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_cell11_kernel :
    (reconstructItems 6980 verifiedFrontendLexerArtifact 6978).run 105 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 11, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_cell_items_node11_production_kernel,
    verifiedFrontendLexer_cell_items_node11_item_kernel,
    verifiedFrontendLexer_cell_items_node11_rest_kernel,
    verifiedFrontendLexer_reconstruct_item11_kernel,
    verifiedFrontendLexer_reconstruct_items_cell12_kernel,
    verifiedFrontendLexer_cell_proposed_items_drop11_kernel]

end Lanius.Extraction

