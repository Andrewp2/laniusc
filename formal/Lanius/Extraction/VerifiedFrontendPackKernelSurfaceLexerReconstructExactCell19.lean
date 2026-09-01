import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructExactCell20

namespace Lanius.Extraction

set_option maxRecDepth 100000

theorem verifiedFrontendLexer_exact_proposed_items_drop19_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 19 =
      verifiedFrontendLexerProposedItem19Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 20 := by rfl

theorem verifiedFrontendLexer_exact_items_node19_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6970 = some 1 := by
  unfold artifactProduction?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 9 (by omega)]
  rfl

theorem verifiedFrontendLexer_exact_items_node19_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6970 0 = some 4474 := by
  unfold artifactChildNode?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 9 (by omega)]
  rfl

theorem verifiedFrontendLexer_exact_items_node19_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6970 1 = some 6969 := by
  unfold artifactChildNode?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 9 (by omega)]
  rfl

theorem verifiedFrontendLexer_reconstruct_items_exact19_kernel :
    (reconstructItems 6973 verifiedFrontendLexerArtifact 6970).run 705 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 19, 1107) := by
  rw [verifiedFrontendLexer_exact_proposed_items_drop19_kernel]
  exact reconstructItems_cons_step
    verifiedFrontendLexer_exact_items_node19_production_kernel
    verifiedFrontendLexer_exact_items_node19_item_kernel
    verifiedFrontendLexer_exact_items_node19_rest_kernel
    verifiedFrontendLexer_reconstruct_item19_exact_kernel
    verifiedFrontendLexer_reconstruct_items_exact20_kernel

end Lanius.Extraction

