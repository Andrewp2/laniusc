import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructExactCell1

namespace Lanius.Extraction

set_option maxRecDepth 100000

theorem verifiedFrontendLexer_exact_proposed_items_drop0_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 0 =
      verifiedFrontendLexerProposedItem0Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 1 := by rfl

theorem verifiedFrontendLexer_exact_items_node0_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6989 = some 1 := by
  unfold artifactProduction?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 28 (by omega)]
  rfl

theorem verifiedFrontendLexer_exact_items_node0_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6989 0 = some 6 := by
  unfold artifactChildNode?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 28 (by omega)]
  rfl

theorem verifiedFrontendLexer_exact_items_node0_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6989 1 = some 6988 := by
  unfold artifactChildNode?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 28 (by omega)]
  rfl

theorem verifiedFrontendLexer_reconstruct_items_exact0_kernel :
    (reconstructItems 6992 verifiedFrontendLexerArtifact 6989).run 0 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 0, 1107) := by
  rw [verifiedFrontendLexer_exact_proposed_items_drop0_kernel]
  exact reconstructItems_cons_step
    verifiedFrontendLexer_exact_items_node0_production_kernel
    verifiedFrontendLexer_exact_items_node0_item_kernel
    verifiedFrontendLexer_exact_items_node0_rest_kernel
    verifiedFrontendLexer_reconstruct_item0_exact_kernel
    verifiedFrontendLexer_reconstruct_items_exact1_kernel

end Lanius.Extraction

