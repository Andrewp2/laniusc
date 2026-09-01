import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructExactCell24

namespace Lanius.Extraction

set_option maxRecDepth 100000

theorem verifiedFrontendLexer_exact_proposed_items_drop23_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 23 =
      verifiedFrontendLexerProposedItem23Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 24 := by rfl

theorem verifiedFrontendLexer_exact_items_node23_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6966 = some 1 := by
  unfold artifactProduction?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 5 (by omega)]
  rfl

theorem verifiedFrontendLexer_exact_items_node23_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6966 0 = some 5714 := by
  unfold artifactChildNode?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 5 (by omega)]
  rfl

theorem verifiedFrontendLexer_exact_items_node23_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6966 1 = some 6965 := by
  unfold artifactChildNode?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 5 (by omega)]
  rfl

theorem verifiedFrontendLexer_reconstruct_items_exact23_kernel :
    (reconstructItems 6969 verifiedFrontendLexerArtifact 6966).run 771 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 23, 1107) := by
  rw [verifiedFrontendLexer_exact_proposed_items_drop23_kernel]
  exact reconstructItems_cons_step
    verifiedFrontendLexer_exact_items_node23_production_kernel
    verifiedFrontendLexer_exact_items_node23_item_kernel
    verifiedFrontendLexer_exact_items_node23_rest_kernel
    verifiedFrontendLexer_reconstruct_item23_exact_kernel
    verifiedFrontendLexer_reconstruct_items_exact24_kernel

end Lanius.Extraction

