import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructFastCell17

namespace Lanius.Extraction

set_option maxRecDepth 100000

 theorem verifiedFrontendLexer_fast_proposed_items_drop16_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 16 =
      verifiedFrontendLexerProposedItem16Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 17 := by
  rfl

theorem verifiedFrontendLexer_fast_items_node16_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6973 = some 1 := by
  unfold artifactProduction?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 12 (by omega)]
  rfl

theorem verifiedFrontendLexer_fast_items_node16_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6973 0 = some 4332 := by
  unfold artifactChildNode?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 12 (by omega)]
  rfl

theorem verifiedFrontendLexer_fast_items_node16_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6973 1 = some 6972 := by
  unfold artifactChildNode?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 12 (by omega)]
  rfl

theorem verifiedFrontendLexer_reconstruct_items_fast16_kernel :
    (reconstructItems 6975 verifiedFrontendLexerArtifact 6973).run 623 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 16, 1107) := by
  rw [verifiedFrontendLexer_fast_proposed_items_drop16_kernel]
  exact reconstructItems_cons_step
    verifiedFrontendLexer_fast_items_node16_production_kernel
    verifiedFrontendLexer_fast_items_node16_item_kernel
    verifiedFrontendLexer_fast_items_node16_rest_kernel
    verifiedFrontendLexer_reconstruct_item16_kernel
    verifiedFrontendLexer_reconstruct_items_fast17_kernel

end Lanius.Extraction
