import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructExactCell11

namespace Lanius.Extraction

set_option maxRecDepth 100000

theorem verifiedFrontendLexer_exact_proposed_items_drop10_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 10 =
      verifiedFrontendLexerProposedItem10Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 11 := by rfl

theorem verifiedFrontendLexer_exact_items_node10_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6979 = some 1 := by
  unfold artifactProduction?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 18 (by omega)]
  rfl

theorem verifiedFrontendLexer_exact_items_node10_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6979 0 = some 627 := by
  unfold artifactChildNode?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 18 (by omega)]
  rfl

theorem verifiedFrontendLexer_exact_items_node10_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6979 1 = some 6978 := by
  unfold artifactChildNode?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 18 (by omega)]
  rfl

theorem verifiedFrontendLexer_reconstruct_items_exact10_kernel :
    (reconstructItems 6982 verifiedFrontendLexerArtifact 6979).run 81 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 10, 1107) := by
  rw [verifiedFrontendLexer_exact_proposed_items_drop10_kernel]
  exact reconstructItems_cons_step
    verifiedFrontendLexer_exact_items_node10_production_kernel
    verifiedFrontendLexer_exact_items_node10_item_kernel
    verifiedFrontendLexer_exact_items_node10_rest_kernel
    verifiedFrontendLexer_reconstruct_item10_exact_kernel
    verifiedFrontendLexer_reconstruct_items_exact11_kernel

end Lanius.Extraction

