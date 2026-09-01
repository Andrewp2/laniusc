import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructCompactAssemblyCell19

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_cell_proposed_items_drop18_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 18 =
      verifiedFrontendLexerProposedItem18Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 19 := by
  rfl

theorem verifiedFrontendLexer_cell_items_node18_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6971 = some 1 := by
  cbv

theorem verifiedFrontendLexer_cell_items_node18_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6971 0 = some 4418 := by
  cbv

theorem verifiedFrontendLexer_cell_items_node18_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6971 1 = some 6970 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_cell18_kernel :
    (reconstructItems 6973 verifiedFrontendLexerArtifact 6971).run 692 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 18, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_cell_items_node18_production_kernel,
    verifiedFrontendLexer_cell_items_node18_item_kernel,
    verifiedFrontendLexer_cell_items_node18_rest_kernel,
    verifiedFrontendLexer_reconstruct_item18_kernel,
    verifiedFrontendLexer_reconstruct_items_cell19_kernel,
    verifiedFrontendLexer_cell_proposed_items_drop18_kernel]

end Lanius.Extraction

