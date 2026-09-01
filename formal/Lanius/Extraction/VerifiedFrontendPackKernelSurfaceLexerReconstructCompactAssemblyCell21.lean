import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructCompactAssemblyCell22

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_cell_proposed_items_drop21_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 21 =
      verifiedFrontendLexerProposedItem21Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 22 := by
  rfl

theorem verifiedFrontendLexer_cell_items_node21_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6968 = some 1 := by
  rfl

theorem verifiedFrontendLexer_cell_items_node21_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6968 0 = some 4678 := by
  rfl

theorem verifiedFrontendLexer_cell_items_node21_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6968 1 = some 6967 := by
  rfl

theorem verifiedFrontendLexer_reconstruct_items_cell21_kernel :
    (reconstructItems 6970 verifiedFrontendLexerArtifact 6968).run 731 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 21, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_cell_items_node21_production_kernel,
    verifiedFrontendLexer_cell_items_node21_item_kernel,
    verifiedFrontendLexer_cell_items_node21_rest_kernel,
    verifiedFrontendLexer_reconstruct_item21_kernel,
    verifiedFrontendLexer_reconstruct_items_cell22_kernel,
    verifiedFrontendLexer_cell_proposed_items_drop21_kernel]

end Lanius.Extraction
