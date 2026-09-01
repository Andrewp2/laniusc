import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructFastCell11

namespace Lanius.Extraction

set_option maxRecDepth 100000

 theorem verifiedFrontendLexer_fast_proposed_items_drop10_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 10 =
      verifiedFrontendLexerProposedItem10Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 11 := by
  rfl

theorem verifiedFrontendLexer_fast_items_node10_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6979 = some 1 := by
  unfold artifactProduction?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 18 (by omega)]
  rfl

theorem verifiedFrontendLexer_fast_items_node10_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6979 0 = some 627 := by
  unfold artifactChildNode?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 18 (by omega)]
  rfl

theorem verifiedFrontendLexer_fast_items_node10_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6979 1 = some 6978 := by
  unfold artifactChildNode?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 18 (by omega)]
  rfl

theorem verifiedFrontendLexer_reconstruct_items_fast10_kernel :
    (reconstructItems 6981 verifiedFrontendLexerArtifact 6979).run 81 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 10, 1107) := by
  rw [verifiedFrontendLexer_fast_proposed_items_drop10_kernel]
  exact reconstructItems_cons_step
    verifiedFrontendLexer_fast_items_node10_production_kernel
    verifiedFrontendLexer_fast_items_node10_item_kernel
    verifiedFrontendLexer_fast_items_node10_rest_kernel
    verifiedFrontendLexer_reconstruct_item10_kernel
    verifiedFrontendLexer_reconstruct_items_fast11_kernel

end Lanius.Extraction
