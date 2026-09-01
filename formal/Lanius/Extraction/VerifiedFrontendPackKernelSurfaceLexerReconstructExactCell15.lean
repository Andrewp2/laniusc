import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructExactCell16

namespace Lanius.Extraction

set_option maxRecDepth 100000

theorem verifiedFrontendLexer_exact_proposed_items_drop15_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 15 =
      verifiedFrontendLexerProposedItem15Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 16 := by rfl

theorem verifiedFrontendLexer_exact_items_node15_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6974 = some 1 := by
  unfold artifactProduction?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 13 (by omega)]
  rfl

theorem verifiedFrontendLexer_exact_items_node15_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6974 0 = some 4012 := by
  unfold artifactChildNode?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 13 (by omega)]
  rfl

theorem verifiedFrontendLexer_exact_items_node15_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6974 1 = some 6973 := by
  unfold artifactChildNode?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 13 (by omega)]
  rfl

theorem verifiedFrontendLexer_reconstruct_items_exact15_kernel :
    (reconstructItems 6977 verifiedFrontendLexerArtifact 6974).run 567 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 15, 1107) := by
  rw [verifiedFrontendLexer_exact_proposed_items_drop15_kernel]
  exact reconstructItems_cons_step
    verifiedFrontendLexer_exact_items_node15_production_kernel
    verifiedFrontendLexer_exact_items_node15_item_kernel
    verifiedFrontendLexer_exact_items_node15_rest_kernel
    verifiedFrontendLexer_reconstruct_item15_exact_kernel
    verifiedFrontendLexer_reconstruct_items_exact16_kernel

end Lanius.Extraction

