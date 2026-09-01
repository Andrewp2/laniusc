import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructCompactAssemblyCell7

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_cell_proposed_items_drop6_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 6 =
      verifiedFrontendLexerProposedItem6Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 7 := by
  rfl

theorem verifiedFrontendLexer_cell_items_node6_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6983 = some 1 := by
  cbv

theorem verifiedFrontendLexer_cell_items_node6_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6983 0 = some 191 := by
  cbv

theorem verifiedFrontendLexer_cell_items_node6_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6983 1 = some 6982 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_cell6_kernel :
    (reconstructItems 6985 verifiedFrontendLexerArtifact 6983).run 28 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 6, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_cell_items_node6_production_kernel,
    verifiedFrontendLexer_cell_items_node6_item_kernel,
    verifiedFrontendLexer_cell_items_node6_rest_kernel,
    verifiedFrontendLexer_reconstruct_item6_kernel,
    verifiedFrontendLexer_reconstruct_items_cell7_kernel,
    verifiedFrontendLexer_cell_proposed_items_drop6_kernel]

end Lanius.Extraction

