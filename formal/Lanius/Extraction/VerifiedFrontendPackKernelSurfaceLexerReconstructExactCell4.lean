import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructExactCell5

namespace Lanius.Extraction

set_option maxRecDepth 100000

theorem verifiedFrontendLexer_exact_proposed_items_drop4_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 4 =
      verifiedFrontendLexerProposedItem4Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 5 := by rfl

theorem verifiedFrontendLexer_exact_items_node4_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6985 = some 1 := by
  unfold artifactProduction?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 24 (by omega)]
  rfl

theorem verifiedFrontendLexer_exact_items_node4_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6985 0 = some 121 := by
  unfold artifactChildNode?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 24 (by omega)]
  rfl

theorem verifiedFrontendLexer_exact_items_node4_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6985 1 = some 6984 := by
  unfold artifactChildNode?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 24 (by omega)]
  rfl

theorem verifiedFrontendLexer_reconstruct_items_exact4_kernel :
    (reconstructItems 6988 verifiedFrontendLexerArtifact 6985).run 18 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 4, 1107) := by
  rw [verifiedFrontendLexer_exact_proposed_items_drop4_kernel]
  exact reconstructItems_cons_step
    verifiedFrontendLexer_exact_items_node4_production_kernel
    verifiedFrontendLexer_exact_items_node4_item_kernel
    verifiedFrontendLexer_exact_items_node4_rest_kernel
    verifiedFrontendLexer_reconstruct_item4_exact_kernel
    verifiedFrontendLexer_reconstruct_items_exact5_kernel

end Lanius.Extraction

