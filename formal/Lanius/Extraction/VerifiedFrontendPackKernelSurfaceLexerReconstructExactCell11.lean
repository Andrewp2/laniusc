import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructExactCell12

namespace Lanius.Extraction

set_option maxRecDepth 100000

theorem verifiedFrontendLexer_exact_proposed_items_drop11_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 11 =
      verifiedFrontendLexerProposedItem11Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 12 := by rfl

theorem verifiedFrontendLexer_exact_items_node11_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6978 = some 1 := by
  unfold artifactProduction?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 17 (by omega)]
  rfl

theorem verifiedFrontendLexer_exact_items_node11_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6978 0 = some 729 := by
  unfold artifactChildNode?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 17 (by omega)]
  rfl

theorem verifiedFrontendLexer_exact_items_node11_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6978 1 = some 6977 := by
  unfold artifactChildNode?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 17 (by omega)]
  rfl

theorem verifiedFrontendLexer_reconstruct_items_exact11_kernel :
    (reconstructItems 6981 verifiedFrontendLexerArtifact 6978).run 105 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 11, 1107) := by
  rw [verifiedFrontendLexer_exact_proposed_items_drop11_kernel]
  exact reconstructItems_cons_step
    verifiedFrontendLexer_exact_items_node11_production_kernel
    verifiedFrontendLexer_exact_items_node11_item_kernel
    verifiedFrontendLexer_exact_items_node11_rest_kernel
    verifiedFrontendLexer_reconstruct_item11_exact_kernel
    verifiedFrontendLexer_reconstruct_items_exact12_kernel

end Lanius.Extraction

