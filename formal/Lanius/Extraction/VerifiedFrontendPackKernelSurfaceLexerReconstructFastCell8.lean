import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructFastCell9

namespace Lanius.Extraction

set_option maxRecDepth 100000

 theorem verifiedFrontendLexer_fast_proposed_items_drop8_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 8 =
      verifiedFrontendLexerProposedItem8Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 9 := by
  rfl

theorem verifiedFrontendLexer_fast_items_node8_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6981 = some 1 := by
  unfold artifactProduction?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 20 (by omega)]
  rfl

theorem verifiedFrontendLexer_fast_items_node8_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6981 0 = some 261 := by
  unfold artifactChildNode?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 20 (by omega)]
  rfl

theorem verifiedFrontendLexer_fast_items_node8_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6981 1 = some 6980 := by
  unfold artifactChildNode?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 20 (by omega)]
  rfl

theorem verifiedFrontendLexer_reconstruct_items_fast8_kernel :
    (reconstructItems 6983 verifiedFrontendLexerArtifact 6981).run 38 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 8, 1107) := by
  rw [verifiedFrontendLexer_fast_proposed_items_drop8_kernel]
  exact reconstructItems_cons_step
    verifiedFrontendLexer_fast_items_node8_production_kernel
    verifiedFrontendLexer_fast_items_node8_item_kernel
    verifiedFrontendLexer_fast_items_node8_rest_kernel
    verifiedFrontendLexer_reconstruct_item8_kernel
    verifiedFrontendLexer_reconstruct_items_fast9_kernel

end Lanius.Extraction
