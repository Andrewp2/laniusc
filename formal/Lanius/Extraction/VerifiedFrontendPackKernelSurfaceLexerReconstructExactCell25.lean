import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructExactCell26

namespace Lanius.Extraction

set_option maxRecDepth 100000

theorem verifiedFrontendLexer_exact_proposed_items_drop25_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 25 =
      verifiedFrontendLexerProposedItem25Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 26 := by rfl

theorem verifiedFrontendLexer_exact_items_node25_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6964 = some 1 := by
  unfold artifactProduction?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 3 (by omega)]
  rfl

theorem verifiedFrontendLexer_exact_items_node25_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6964 0 = some 6118 := by
  unfold artifactChildNode?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 3 (by omega)]
  rfl

theorem verifiedFrontendLexer_exact_items_node25_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6964 1 = some 6963 := by
  unfold artifactChildNode?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 3 (by omega)]
  rfl

theorem verifiedFrontendLexer_reconstruct_items_exact25_kernel :
    (reconstructItems 6967 verifiedFrontendLexerArtifact 6964).run 931 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 25, 1107) := by
  rw [verifiedFrontendLexer_exact_proposed_items_drop25_kernel]
  exact reconstructItems_cons_step
    verifiedFrontendLexer_exact_items_node25_production_kernel
    verifiedFrontendLexer_exact_items_node25_item_kernel
    verifiedFrontendLexer_exact_items_node25_rest_kernel
    verifiedFrontendLexer_reconstruct_item25_exact_kernel
    verifiedFrontendLexer_reconstruct_items_exact26_kernel

end Lanius.Extraction

