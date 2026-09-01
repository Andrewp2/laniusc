import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructExactCell2

namespace Lanius.Extraction

set_option maxRecDepth 100000

theorem verifiedFrontendLexer_exact_proposed_items_drop1_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 1 =
      verifiedFrontendLexerProposedItem1Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 2 := by rfl

theorem verifiedFrontendLexer_exact_items_node1_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6988 = some 1 := by
  unfold artifactProduction?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 27 (by omega)]
  rfl

theorem verifiedFrontendLexer_exact_items_node1_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6988 0 = some 16 := by
  unfold artifactChildNode?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 27 (by omega)]
  rfl

theorem verifiedFrontendLexer_exact_items_node1_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6988 1 = some 6987 := by
  unfold artifactChildNode?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 27 (by omega)]
  rfl

theorem verifiedFrontendLexer_reconstruct_items_exact1_kernel :
    (reconstructItems 6991 verifiedFrontendLexerArtifact 6988).run 4 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 1, 1107) := by
  rw [verifiedFrontendLexer_exact_proposed_items_drop1_kernel]
  exact reconstructItems_cons_step
    verifiedFrontendLexer_exact_items_node1_production_kernel
    verifiedFrontendLexer_exact_items_node1_item_kernel
    verifiedFrontendLexer_exact_items_node1_rest_kernel
    verifiedFrontendLexer_reconstruct_item1_exact_kernel
    verifiedFrontendLexer_reconstruct_items_exact2_kernel

end Lanius.Extraction

