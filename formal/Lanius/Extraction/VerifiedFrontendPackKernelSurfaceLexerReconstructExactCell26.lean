import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructExactCell27

namespace Lanius.Extraction

set_option maxRecDepth 100000

theorem verifiedFrontendLexer_exact_proposed_items_drop26_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 26 =
      verifiedFrontendLexerProposedItem26Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 27 := by rfl

theorem verifiedFrontendLexer_exact_items_node26_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6963 = some 1 := by
  unfold artifactProduction?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 2 (by omega)]
  rfl

theorem verifiedFrontendLexer_exact_items_node26_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6963 0 = some 6417 := by
  unfold artifactChildNode?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 2 (by omega)]
  rfl

theorem verifiedFrontendLexer_exact_items_node26_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6963 1 = some 6962 := by
  unfold artifactChildNode?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 2 (by omega)]
  rfl

theorem verifiedFrontendLexer_reconstruct_items_exact26_kernel :
    (reconstructItems 6966 verifiedFrontendLexerArtifact 6963).run 963 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 26, 1107) := by
  rw [verifiedFrontendLexer_exact_proposed_items_drop26_kernel]
  exact reconstructItems_cons_step
    verifiedFrontendLexer_exact_items_node26_production_kernel
    verifiedFrontendLexer_exact_items_node26_item_kernel
    verifiedFrontendLexer_exact_items_node26_rest_kernel
    verifiedFrontendLexer_reconstruct_item26_exact_kernel
    verifiedFrontendLexer_reconstruct_items_exact27_kernel

end Lanius.Extraction

