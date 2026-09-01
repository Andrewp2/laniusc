import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructExactCell15

namespace Lanius.Extraction

set_option maxRecDepth 100000

theorem verifiedFrontendLexer_exact_proposed_items_drop14_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 14 =
      verifiedFrontendLexerProposedItem14Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 15 := by rfl

theorem verifiedFrontendLexer_exact_items_node14_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6975 = some 1 := by
  unfold artifactProduction?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 14 (by omega)]
  rfl

theorem verifiedFrontendLexer_exact_items_node14_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6975 0 = some 3692 := by
  unfold artifactChildNode?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 14 (by omega)]
  rfl

theorem verifiedFrontendLexer_exact_items_node14_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6975 1 = some 6974 := by
  unfold artifactChildNode?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 14 (by omega)]
  rfl

theorem verifiedFrontendLexer_reconstruct_items_exact14_kernel :
    (reconstructItems 6978 verifiedFrontendLexerArtifact 6975).run 309 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 14, 1107) := by
  rw [verifiedFrontendLexer_exact_proposed_items_drop14_kernel]
  exact reconstructItems_cons_step
    verifiedFrontendLexer_exact_items_node14_production_kernel
    verifiedFrontendLexer_exact_items_node14_item_kernel
    verifiedFrontendLexer_exact_items_node14_rest_kernel
    verifiedFrontendLexer_reconstruct_item14_exact_kernel
    verifiedFrontendLexer_reconstruct_items_exact15_kernel

end Lanius.Extraction

