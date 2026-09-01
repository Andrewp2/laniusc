import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructExactItems27
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructSpine

namespace Lanius.Extraction

set_option maxRecDepth 100000

theorem verifiedFrontendLexer_items_end_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6961 = some 2 := by
  unfold artifactProduction?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 0 (by omega)]
  rfl

theorem verifiedFrontendLexer_reconstruct_items_exact_end_kernel :
    (reconstructItems 6964 verifiedFrontendLexerArtifact 6961).run 1107 =
      some ([], 1107) := by
  exact reconstructItems_empty_step
    verifiedFrontendLexer_items_end_production_kernel

theorem verifiedFrontendLexer_exact_proposed_items_drop27_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 27 =
      verifiedFrontendLexerProposedItem27Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 28 := by rfl

theorem verifiedFrontendLexer_exact_items_node27_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6962 = some 1 := by
  unfold artifactProduction?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 1 (by omega)]
  rfl

theorem verifiedFrontendLexer_exact_items_node27_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6962 0 = some 6960 := by
  unfold artifactChildNode?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 1 (by omega)]
  rfl

theorem verifiedFrontendLexer_exact_items_node27_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6962 1 = some 6961 := by
  unfold artifactChildNode?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 1 (by omega)]
  rfl

theorem verifiedFrontendLexer_reconstruct_items_exact27_kernel :
    (reconstructItems 6965 verifiedFrontendLexerArtifact 6962).run 1017 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 27, 1107) := by
  rw [verifiedFrontendLexer_exact_proposed_items_drop27_kernel]
  exact reconstructItems_cons_step
    verifiedFrontendLexer_exact_items_node27_production_kernel
    verifiedFrontendLexer_exact_items_node27_item_kernel
    verifiedFrontendLexer_exact_items_node27_rest_kernel
    verifiedFrontendLexer_reconstruct_item27_exact_kernel
    verifiedFrontendLexer_reconstruct_items_exact_end_kernel

end Lanius.Extraction

