import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructExactCell21

namespace Lanius.Extraction

set_option maxRecDepth 100000

theorem verifiedFrontendLexer_exact_proposed_items_drop20_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 20 =
      verifiedFrontendLexerProposedItem20Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 21 := by rfl

theorem verifiedFrontendLexer_exact_items_node20_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6969 = some 1 := by
  unfold artifactProduction?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 8 (by omega)]
  rfl

theorem verifiedFrontendLexer_exact_items_node20_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6969 0 = some 4530 := by
  unfold artifactChildNode?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 8 (by omega)]
  rfl

theorem verifiedFrontendLexer_exact_items_node20_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6969 1 = some 6968 := by
  unfold artifactChildNode?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 8 (by omega)]
  rfl

theorem verifiedFrontendLexer_reconstruct_items_exact20_kernel :
    (reconstructItems 6972 verifiedFrontendLexerArtifact 6969).run 718 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 20, 1107) := by
  rw [verifiedFrontendLexer_exact_proposed_items_drop20_kernel]
  exact reconstructItems_cons_step
    verifiedFrontendLexer_exact_items_node20_production_kernel
    verifiedFrontendLexer_exact_items_node20_item_kernel
    verifiedFrontendLexer_exact_items_node20_rest_kernel
    verifiedFrontendLexer_reconstruct_item20_exact_kernel
    verifiedFrontendLexer_reconstruct_items_exact21_kernel

end Lanius.Extraction

