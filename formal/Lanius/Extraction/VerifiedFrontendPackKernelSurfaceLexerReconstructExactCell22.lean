import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructExactCell23

namespace Lanius.Extraction

set_option maxRecDepth 100000

theorem verifiedFrontendLexer_exact_proposed_items_drop22_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 22 =
      verifiedFrontendLexerProposedItem22Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 23 := by rfl

theorem verifiedFrontendLexer_exact_items_node22_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6967 = some 1 := by
  unfold artifactProduction?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 6 (by omega)]
  rfl

theorem verifiedFrontendLexer_exact_items_node22_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6967 0 = some 4826 := by
  unfold artifactChildNode?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 6 (by omega)]
  rfl

theorem verifiedFrontendLexer_exact_items_node22_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6967 1 = some 6966 := by
  unfold artifactChildNode?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 6 (by omega)]
  rfl

theorem verifiedFrontendLexer_reconstruct_items_exact22_kernel :
    (reconstructItems 6970 verifiedFrontendLexerArtifact 6967).run 751 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 22, 1107) := by
  rw [verifiedFrontendLexer_exact_proposed_items_drop22_kernel]
  exact reconstructItems_cons_step
    verifiedFrontendLexer_exact_items_node22_production_kernel
    verifiedFrontendLexer_exact_items_node22_item_kernel
    verifiedFrontendLexer_exact_items_node22_rest_kernel
    verifiedFrontendLexer_reconstruct_item22_exact_kernel
    verifiedFrontendLexer_reconstruct_items_exact23_kernel

end Lanius.Extraction

