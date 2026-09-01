import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructCompactAssembly4

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_segment_proposed_items_drop21_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 21 =
      verifiedFrontendLexerProposedItem21Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 22 := by
  rfl

theorem verifiedFrontendLexer_segment_items_node21_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6968 = some 1 := by
  cbv

theorem verifiedFrontendLexer_segment_items_node21_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6968 0 = some 4678 := by
  cbv

theorem verifiedFrontendLexer_segment_items_node21_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6968 1 = some 6967 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_segment21_kernel :
    (reconstructItems 6970 verifiedFrontendLexerArtifact 6968).run 731 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 21, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_segment_items_node21_production_kernel,
    verifiedFrontendLexer_segment_items_node21_item_kernel,
    verifiedFrontendLexer_segment_items_node21_rest_kernel,
    verifiedFrontendLexer_reconstruct_item21_kernel,
    verifiedFrontendLexer_reconstruct_items_compact22_kernel,
    verifiedFrontendLexer_segment_proposed_items_drop21_kernel]

theorem verifiedFrontendLexer_segment_proposed_items_drop20_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 20 =
      verifiedFrontendLexerProposedItem20Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 21 := by
  rfl

theorem verifiedFrontendLexer_segment_items_node20_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6969 = some 1 := by
  cbv

theorem verifiedFrontendLexer_segment_items_node20_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6969 0 = some 4530 := by
  cbv

theorem verifiedFrontendLexer_segment_items_node20_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6969 1 = some 6968 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_segment20_kernel :
    (reconstructItems 6971 verifiedFrontendLexerArtifact 6969).run 718 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 20, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_segment_items_node20_production_kernel,
    verifiedFrontendLexer_segment_items_node20_item_kernel,
    verifiedFrontendLexer_segment_items_node20_rest_kernel,
    verifiedFrontendLexer_reconstruct_item20_kernel,
    verifiedFrontendLexer_reconstruct_items_segment21_kernel,
    verifiedFrontendLexer_segment_proposed_items_drop20_kernel]

theorem verifiedFrontendLexer_segment_proposed_items_drop19_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 19 =
      verifiedFrontendLexerProposedItem19Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 20 := by
  rfl

theorem verifiedFrontendLexer_segment_items_node19_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6970 = some 1 := by
  cbv

theorem verifiedFrontendLexer_segment_items_node19_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6970 0 = some 4474 := by
  cbv

theorem verifiedFrontendLexer_segment_items_node19_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6970 1 = some 6969 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_segment19_kernel :
    (reconstructItems 6972 verifiedFrontendLexerArtifact 6970).run 705 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 19, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_segment_items_node19_production_kernel,
    verifiedFrontendLexer_segment_items_node19_item_kernel,
    verifiedFrontendLexer_segment_items_node19_rest_kernel,
    verifiedFrontendLexer_reconstruct_item19_kernel,
    verifiedFrontendLexer_reconstruct_items_segment20_kernel,
    verifiedFrontendLexer_segment_proposed_items_drop19_kernel]

end Lanius.Extraction

