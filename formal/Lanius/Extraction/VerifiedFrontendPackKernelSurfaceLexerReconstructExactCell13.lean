import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructExactCell14

namespace Lanius.Extraction

set_option maxRecDepth 100000

theorem verifiedFrontendLexer_exact_proposed_items_drop13_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 13 =
      verifiedFrontendLexerProposedItem13Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 14 := by rfl

theorem verifiedFrontendLexer_exact_items_node13_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6976 = some 1 := by
  unfold artifactProduction?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 15 (by omega)]
  rfl

theorem verifiedFrontendLexer_exact_items_node13_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6976 0 = some 1905 := by
  unfold artifactChildNode?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 15 (by omega)]
  rfl

theorem verifiedFrontendLexer_exact_items_node13_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6976 1 = some 6975 := by
  unfold artifactChildNode?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 15 (by omega)]
  rfl

theorem verifiedFrontendLexer_reconstruct_items_exact13_kernel :
    (reconstructItems 6979 verifiedFrontendLexerArtifact 6976).run 157 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 13, 1107) := by
  rw [verifiedFrontendLexer_exact_proposed_items_drop13_kernel]
  exact reconstructItems_cons_step
    verifiedFrontendLexer_exact_items_node13_production_kernel
    verifiedFrontendLexer_exact_items_node13_item_kernel
    verifiedFrontendLexer_exact_items_node13_rest_kernel
    verifiedFrontendLexer_reconstruct_item13_exact_kernel
    verifiedFrontendLexer_reconstruct_items_exact14_kernel

end Lanius.Extraction

