import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructExactCell7

namespace Lanius.Extraction

set_option maxRecDepth 100000

theorem verifiedFrontendLexer_exact_proposed_items_drop6_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 6 =
      verifiedFrontendLexerProposedItem6Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 7 := by rfl

theorem verifiedFrontendLexer_exact_items_node6_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6983 = some 1 := by
  unfold artifactProduction?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 22 (by omega)]
  rfl

theorem verifiedFrontendLexer_exact_items_node6_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6983 0 = some 191 := by
  unfold artifactChildNode?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 22 (by omega)]
  rfl

theorem verifiedFrontendLexer_exact_items_node6_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6983 1 = some 6982 := by
  unfold artifactChildNode?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 22 (by omega)]
  rfl

theorem verifiedFrontendLexer_reconstruct_items_exact6_kernel :
    (reconstructItems 6986 verifiedFrontendLexerArtifact 6983).run 28 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 6, 1107) := by
  rw [verifiedFrontendLexer_exact_proposed_items_drop6_kernel]
  exact reconstructItems_cons_step
    verifiedFrontendLexer_exact_items_node6_production_kernel
    verifiedFrontendLexer_exact_items_node6_item_kernel
    verifiedFrontendLexer_exact_items_node6_rest_kernel
    verifiedFrontendLexer_reconstruct_item6_exact_kernel
    verifiedFrontendLexer_reconstruct_items_exact7_kernel

end Lanius.Extraction

