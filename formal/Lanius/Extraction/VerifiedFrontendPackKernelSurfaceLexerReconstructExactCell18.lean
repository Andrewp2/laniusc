import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructExactCell19

namespace Lanius.Extraction

set_option maxRecDepth 100000

theorem verifiedFrontendLexer_exact_proposed_items_drop18_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 18 =
      verifiedFrontendLexerProposedItem18Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 19 := by rfl

theorem verifiedFrontendLexer_exact_items_node18_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6971 = some 1 := by
  unfold artifactProduction?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 10 (by omega)]
  rfl

theorem verifiedFrontendLexer_exact_items_node18_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6971 0 = some 4418 := by
  unfold artifactChildNode?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 10 (by omega)]
  rfl

theorem verifiedFrontendLexer_exact_items_node18_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6971 1 = some 6970 := by
  unfold artifactChildNode?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 10 (by omega)]
  rfl

theorem verifiedFrontendLexer_reconstruct_items_exact18_kernel :
    (reconstructItems 6974 verifiedFrontendLexerArtifact 6971).run 692 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 18, 1107) := by
  rw [verifiedFrontendLexer_exact_proposed_items_drop18_kernel]
  exact reconstructItems_cons_step
    verifiedFrontendLexer_exact_items_node18_production_kernel
    verifiedFrontendLexer_exact_items_node18_item_kernel
    verifiedFrontendLexer_exact_items_node18_rest_kernel
    verifiedFrontendLexer_reconstruct_item18_exact_kernel
    verifiedFrontendLexer_reconstruct_items_exact19_kernel

end Lanius.Extraction

