import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructFastCell10

namespace Lanius.Extraction

set_option maxRecDepth 100000

 theorem verifiedFrontendLexer_fast_proposed_items_drop9_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 9 =
      verifiedFrontendLexerProposedItem9Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 10 := by
  rfl

theorem verifiedFrontendLexer_fast_items_node9_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6980 = some 1 := by
  unfold artifactProduction?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 19 (by omega)]
  rfl

theorem verifiedFrontendLexer_fast_items_node9_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6980 0 = some 477 := by
  unfold artifactChildNode?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 19 (by omega)]
  rfl

theorem verifiedFrontendLexer_fast_items_node9_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6980 1 = some 6979 := by
  unfold artifactChildNode?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 19 (by omega)]
  rfl

theorem verifiedFrontendLexer_reconstruct_items_fast9_kernel :
    (reconstructItems 6982 verifiedFrontendLexerArtifact 6980).run 43 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 9, 1107) := by
  rw [verifiedFrontendLexer_fast_proposed_items_drop9_kernel]
  exact reconstructItems_cons_step
    verifiedFrontendLexer_fast_items_node9_production_kernel
    verifiedFrontendLexer_fast_items_node9_item_kernel
    verifiedFrontendLexer_fast_items_node9_rest_kernel
    verifiedFrontendLexer_reconstruct_item9_kernel
    verifiedFrontendLexer_reconstruct_items_fast10_kernel

end Lanius.Extraction
