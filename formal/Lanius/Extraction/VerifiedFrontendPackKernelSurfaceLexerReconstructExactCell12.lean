import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructExactCell13

namespace Lanius.Extraction

set_option maxRecDepth 100000

theorem verifiedFrontendLexer_exact_proposed_items_drop12_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 12 =
      verifiedFrontendLexerProposedItem12Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 13 := by rfl

theorem verifiedFrontendLexer_exact_items_node12_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6977 = some 1 := by
  unfold artifactProduction?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 16 (by omega)]
  rfl

theorem verifiedFrontendLexer_exact_items_node12_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6977 0 = some 917 := by
  unfold artifactChildNode?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 16 (by omega)]
  rfl

theorem verifiedFrontendLexer_exact_items_node12_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6977 1 = some 6976 := by
  unfold artifactChildNode?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 16 (by omega)]
  rfl

theorem verifiedFrontendLexer_reconstruct_items_exact12_kernel :
    (reconstructItems 6980 verifiedFrontendLexerArtifact 6977).run 125 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 12, 1107) := by
  rw [verifiedFrontendLexer_exact_proposed_items_drop12_kernel]
  exact reconstructItems_cons_step
    verifiedFrontendLexer_exact_items_node12_production_kernel
    verifiedFrontendLexer_exact_items_node12_item_kernel
    verifiedFrontendLexer_exact_items_node12_rest_kernel
    verifiedFrontendLexer_reconstruct_item12_exact_kernel
    verifiedFrontendLexer_reconstruct_items_exact13_kernel

end Lanius.Extraction

