import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructExactCell25

namespace Lanius.Extraction

set_option maxRecDepth 100000

theorem verifiedFrontendLexer_exact_proposed_items_drop24_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 24 =
      verifiedFrontendLexerProposedItem24Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 25 := by rfl

theorem verifiedFrontendLexer_exact_items_node24_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6965 = some 1 := by
  unfold artifactProduction?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 4 (by omega)]
  rfl

theorem verifiedFrontendLexer_exact_items_node24_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6965 0 = some 5916 := by
  unfold artifactChildNode?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 4 (by omega)]
  rfl

theorem verifiedFrontendLexer_exact_items_node24_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6965 1 = some 6964 := by
  unfold artifactChildNode?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 4 (by omega)]
  rfl

theorem verifiedFrontendLexer_reconstruct_items_exact24_kernel :
    (reconstructItems 6968 verifiedFrontendLexerArtifact 6965).run 899 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 24, 1107) := by
  rw [verifiedFrontendLexer_exact_proposed_items_drop24_kernel]
  exact reconstructItems_cons_step
    verifiedFrontendLexer_exact_items_node24_production_kernel
    verifiedFrontendLexer_exact_items_node24_item_kernel
    verifiedFrontendLexer_exact_items_node24_rest_kernel
    verifiedFrontendLexer_reconstruct_item24_exact_kernel
    verifiedFrontendLexer_reconstruct_items_exact25_kernel

end Lanius.Extraction

