import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructFastCell18

namespace Lanius.Extraction

set_option maxRecDepth 100000

 theorem verifiedFrontendLexer_fast_proposed_items_drop17_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 17 =
      verifiedFrontendLexerProposedItem17Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 18 := by
  rfl

theorem verifiedFrontendLexer_fast_items_node17_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6972 = some 1 := by
  unfold artifactProduction?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 11 (by omega)]
  rfl

theorem verifiedFrontendLexer_fast_items_node17_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6972 0 = some 4362 := by
  unfold artifactChildNode?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 11 (by omega)]
  rfl

theorem verifiedFrontendLexer_fast_items_node17_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6972 1 = some 6971 := by
  unfold artifactChildNode?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 11 (by omega)]
  rfl

theorem verifiedFrontendLexer_reconstruct_items_fast17_kernel :
    (reconstructItems 6974 verifiedFrontendLexerArtifact 6972).run 679 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 17, 1107) := by
  rw [verifiedFrontendLexer_fast_proposed_items_drop17_kernel]
  exact reconstructItems_cons_step
    verifiedFrontendLexer_fast_items_node17_production_kernel
    verifiedFrontendLexer_fast_items_node17_item_kernel
    verifiedFrontendLexer_fast_items_node17_rest_kernel
    verifiedFrontendLexer_reconstruct_item17_kernel
    verifiedFrontendLexer_reconstruct_items_fast18_kernel

end Lanius.Extraction
