import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructFastCell4

namespace Lanius.Extraction

set_option maxRecDepth 100000

 theorem verifiedFrontendLexer_fast_proposed_items_drop3_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 3 =
      verifiedFrontendLexerProposedItem3Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 4 := by
  rfl

theorem verifiedFrontendLexer_fast_items_node3_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6986 = some 1 := by
  unfold artifactProduction?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 25 (by omega)]
  rfl

theorem verifiedFrontendLexer_fast_items_node3_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6986 0 = some 86 := by
  unfold artifactChildNode?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 25 (by omega)]
  rfl

theorem verifiedFrontendLexer_fast_items_node3_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6986 1 = some 6985 := by
  unfold artifactChildNode?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 25 (by omega)]
  rfl

theorem verifiedFrontendLexer_reconstruct_items_fast3_kernel :
    (reconstructItems 6988 verifiedFrontendLexerArtifact 6986).run 13 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 3, 1107) := by
  rw [verifiedFrontendLexer_fast_proposed_items_drop3_kernel]
  exact reconstructItems_cons_step
    verifiedFrontendLexer_fast_items_node3_production_kernel
    verifiedFrontendLexer_fast_items_node3_item_kernel
    verifiedFrontendLexer_fast_items_node3_rest_kernel
    verifiedFrontendLexer_reconstruct_item3_kernel
    verifiedFrontendLexer_reconstruct_items_fast4_kernel

end Lanius.Extraction
