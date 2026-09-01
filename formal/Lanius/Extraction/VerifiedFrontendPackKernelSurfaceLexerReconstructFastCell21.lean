import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructFastCell22

namespace Lanius.Extraction

set_option maxRecDepth 100000

 theorem verifiedFrontendLexer_fast_proposed_items_drop21_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 21 =
      verifiedFrontendLexerProposedItem21Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 22 := by
  rfl

theorem verifiedFrontendLexer_fast_items_node21_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6968 = some 1 := by
  unfold artifactProduction?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 7 (by omega)]
  rfl

theorem verifiedFrontendLexer_fast_items_node21_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6968 0 = some 4678 := by
  unfold artifactChildNode?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 7 (by omega)]
  rfl

theorem verifiedFrontendLexer_fast_items_node21_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6968 1 = some 6967 := by
  unfold artifactChildNode?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 7 (by omega)]
  rfl

theorem verifiedFrontendLexer_reconstruct_items_fast21_kernel :
    (reconstructItems 6970 verifiedFrontendLexerArtifact 6968).run 731 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 21, 1107) := by
  rw [verifiedFrontendLexer_fast_proposed_items_drop21_kernel]
  exact reconstructItems_cons_step
    verifiedFrontendLexer_fast_items_node21_production_kernel
    verifiedFrontendLexer_fast_items_node21_item_kernel
    verifiedFrontendLexer_fast_items_node21_rest_kernel
    verifiedFrontendLexer_reconstruct_item21_kernel
    verifiedFrontendLexer_reconstruct_items_fast22_kernel

end Lanius.Extraction
