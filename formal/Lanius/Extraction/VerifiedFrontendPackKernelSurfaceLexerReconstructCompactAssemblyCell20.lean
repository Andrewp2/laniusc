import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructCompactAssemblyCell21

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_cell_proposed_items_drop20_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 20 =
      verifiedFrontendLexerProposedItem20Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 21 := by
  rfl

theorem verifiedFrontendLexer_cell_items_node20_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6969 = some 1 := by
  cbv

theorem verifiedFrontendLexer_cell_items_node20_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6969 0 = some 4530 := by
  cbv

theorem verifiedFrontendLexer_cell_items_node20_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6969 1 = some 6968 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_cell20_kernel :
    (reconstructItems 6971 verifiedFrontendLexerArtifact 6969).run 718 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 20, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_cell_items_node20_production_kernel,
    verifiedFrontendLexer_cell_items_node20_item_kernel,
    verifiedFrontendLexer_cell_items_node20_rest_kernel,
    verifiedFrontendLexer_reconstruct_item20_kernel,
    verifiedFrontendLexer_reconstruct_items_cell21_kernel,
    verifiedFrontendLexer_cell_proposed_items_drop20_kernel]

end Lanius.Extraction

