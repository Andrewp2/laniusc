import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructExactCell3

namespace Lanius.Extraction

set_option maxRecDepth 100000

theorem verifiedFrontendLexer_exact_proposed_items_drop2_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 2 =
      verifiedFrontendLexerProposedItem2Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 3 := by rfl

theorem verifiedFrontendLexer_exact_items_node2_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6987 = some 1 := by
  unfold artifactProduction?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 26 (by omega)]
  rfl

theorem verifiedFrontendLexer_exact_items_node2_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6987 0 = some 51 := by
  unfold artifactChildNode?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 26 (by omega)]
  rfl

theorem verifiedFrontendLexer_exact_items_node2_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6987 1 = some 6986 := by
  unfold artifactChildNode?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 26 (by omega)]
  rfl

theorem verifiedFrontendLexer_reconstruct_items_exact2_kernel :
    (reconstructItems 6990 verifiedFrontendLexerArtifact 6987).run 8 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 2, 1107) := by
  rw [verifiedFrontendLexer_exact_proposed_items_drop2_kernel]
  exact reconstructItems_cons_step
    verifiedFrontendLexer_exact_items_node2_production_kernel
    verifiedFrontendLexer_exact_items_node2_item_kernel
    verifiedFrontendLexer_exact_items_node2_rest_kernel
    verifiedFrontendLexer_reconstruct_item2_exact_kernel
    verifiedFrontendLexer_reconstruct_items_exact3_kernel

end Lanius.Extraction

