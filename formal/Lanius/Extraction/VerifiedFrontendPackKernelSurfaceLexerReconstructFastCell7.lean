import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructFastCell8

namespace Lanius.Extraction

set_option maxRecDepth 100000

 theorem verifiedFrontendLexer_fast_proposed_items_drop7_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 7 =
      verifiedFrontendLexerProposedItem7Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 8 := by
  rfl

theorem verifiedFrontendLexer_fast_items_node7_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6982 = some 1 := by
  unfold artifactProduction?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 21 (by omega)]
  rfl

theorem verifiedFrontendLexer_fast_items_node7_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6982 0 = some 226 := by
  unfold artifactChildNode?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 21 (by omega)]
  rfl

theorem verifiedFrontendLexer_fast_items_node7_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6982 1 = some 6981 := by
  unfold artifactChildNode?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 21 (by omega)]
  rfl

theorem verifiedFrontendLexer_reconstruct_items_fast7_kernel :
    (reconstructItems 6984 verifiedFrontendLexerArtifact 6982).run 33 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 7, 1107) := by
  rw [verifiedFrontendLexer_fast_proposed_items_drop7_kernel]
  exact reconstructItems_cons_step
    verifiedFrontendLexer_fast_items_node7_production_kernel
    verifiedFrontendLexer_fast_items_node7_item_kernel
    verifiedFrontendLexer_fast_items_node7_rest_kernel
    verifiedFrontendLexer_reconstruct_item7_kernel
    verifiedFrontendLexer_reconstruct_items_fast8_kernel

end Lanius.Extraction
