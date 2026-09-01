import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructCompactAssemblyCell6

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_cell_proposed_items_drop5_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 5 =
      verifiedFrontendLexerProposedItem5Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 6 := by
  rfl

theorem verifiedFrontendLexer_cell_items_node5_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6984 = some 1 := by
  cbv

theorem verifiedFrontendLexer_cell_items_node5_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6984 0 = some 156 := by
  cbv

theorem verifiedFrontendLexer_cell_items_node5_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6984 1 = some 6983 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_cell5_kernel :
    (reconstructItems 6986 verifiedFrontendLexerArtifact 6984).run 23 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 5, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_cell_items_node5_production_kernel,
    verifiedFrontendLexer_cell_items_node5_item_kernel,
    verifiedFrontendLexer_cell_items_node5_rest_kernel,
    verifiedFrontendLexer_reconstruct_item5_kernel,
    verifiedFrontendLexer_reconstruct_items_cell6_kernel,
    verifiedFrontendLexer_cell_proposed_items_drop5_kernel]

end Lanius.Extraction

