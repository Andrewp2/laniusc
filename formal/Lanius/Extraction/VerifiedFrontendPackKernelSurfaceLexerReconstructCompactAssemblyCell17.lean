import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructCompactAssemblyCell18

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_cell_proposed_items_drop17_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 17 =
      verifiedFrontendLexerProposedItem17Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 18 := by
  rfl

theorem verifiedFrontendLexer_cell_items_node17_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6972 = some 1 := by
  cbv

theorem verifiedFrontendLexer_cell_items_node17_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6972 0 = some 4362 := by
  cbv

theorem verifiedFrontendLexer_cell_items_node17_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6972 1 = some 6971 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_cell17_kernel :
    (reconstructItems 6974 verifiedFrontendLexerArtifact 6972).run 679 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 17, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_cell_items_node17_production_kernel,
    verifiedFrontendLexer_cell_items_node17_item_kernel,
    verifiedFrontendLexer_cell_items_node17_rest_kernel,
    verifiedFrontendLexer_reconstruct_item17_kernel,
    verifiedFrontendLexer_reconstruct_items_cell18_kernel,
    verifiedFrontendLexer_cell_proposed_items_drop17_kernel]

end Lanius.Extraction

