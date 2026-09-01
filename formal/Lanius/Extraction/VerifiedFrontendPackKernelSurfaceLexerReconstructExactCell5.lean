import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructExactCell6

namespace Lanius.Extraction

set_option maxRecDepth 100000

theorem verifiedFrontendLexer_exact_proposed_items_drop5_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 5 =
      verifiedFrontendLexerProposedItem5Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 6 := by rfl

theorem verifiedFrontendLexer_exact_items_node5_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6984 = some 1 := by
  unfold artifactProduction?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 23 (by omega)]
  rfl

theorem verifiedFrontendLexer_exact_items_node5_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6984 0 = some 156 := by
  unfold artifactChildNode?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 23 (by omega)]
  rfl

theorem verifiedFrontendLexer_exact_items_node5_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6984 1 = some 6983 := by
  unfold artifactChildNode?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 23 (by omega)]
  rfl

theorem verifiedFrontendLexer_reconstruct_items_exact5_kernel :
    (reconstructItems 6987 verifiedFrontendLexerArtifact 6984).run 23 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 5, 1107) := by
  rw [verifiedFrontendLexer_exact_proposed_items_drop5_kernel]
  exact reconstructItems_cons_step
    verifiedFrontendLexer_exact_items_node5_production_kernel
    verifiedFrontendLexer_exact_items_node5_item_kernel
    verifiedFrontendLexer_exact_items_node5_rest_kernel
    verifiedFrontendLexer_reconstruct_item5_exact_kernel
    verifiedFrontendLexer_reconstruct_items_exact6_kernel

end Lanius.Extraction

