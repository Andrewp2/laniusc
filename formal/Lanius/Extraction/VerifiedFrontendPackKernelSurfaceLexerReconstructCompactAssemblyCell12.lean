import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructCompactAssemblyCell13

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_cell_proposed_items_drop12_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 12 =
      verifiedFrontendLexerProposedItem12Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 13 := by
  rfl

theorem verifiedFrontendLexer_cell_items_node12_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6977 = some 1 := by
  cbv

theorem verifiedFrontendLexer_cell_items_node12_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6977 0 = some 917 := by
  cbv

theorem verifiedFrontendLexer_cell_items_node12_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6977 1 = some 6976 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_cell12_kernel :
    (reconstructItems 6979 verifiedFrontendLexerArtifact 6977).run 125 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 12, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_cell_items_node12_production_kernel,
    verifiedFrontendLexer_cell_items_node12_item_kernel,
    verifiedFrontendLexer_cell_items_node12_rest_kernel,
    verifiedFrontendLexer_reconstruct_item12_kernel,
    verifiedFrontendLexer_reconstruct_items_cell13_kernel,
    verifiedFrontendLexer_cell_proposed_items_drop12_kernel]

end Lanius.Extraction

