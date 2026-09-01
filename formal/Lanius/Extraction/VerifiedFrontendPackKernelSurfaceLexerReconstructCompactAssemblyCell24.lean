import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructCompactAssembly5

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_cell_proposed_items_drop24_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 24 =
      verifiedFrontendLexerProposedItem24Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 25 := by
  rfl

theorem verifiedFrontendLexer_cell_items_node24_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6965 = some 1 := by
  cbv

theorem verifiedFrontendLexer_cell_items_node24_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6965 0 = some 5916 := by
  cbv

theorem verifiedFrontendLexer_cell_items_node24_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6965 1 = some 6964 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_cell24_kernel :
    (reconstructItems 6967 verifiedFrontendLexerArtifact 6965).run 899 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 24, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_cell_items_node24_production_kernel,
    verifiedFrontendLexer_cell_items_node24_item_kernel,
    verifiedFrontendLexer_cell_items_node24_rest_kernel,
    verifiedFrontendLexer_reconstruct_item24_kernel,
    verifiedFrontendLexer_reconstruct_items_compact25_kernel,
    verifiedFrontendLexer_cell_proposed_items_drop24_kernel]

end Lanius.Extraction

