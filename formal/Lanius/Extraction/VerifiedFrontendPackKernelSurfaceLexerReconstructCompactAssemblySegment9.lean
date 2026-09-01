import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructCompactAssemblySegment12

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_segment_proposed_items_drop9_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 9 =
      verifiedFrontendLexerProposedItem9Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 10 := by
  rfl

theorem verifiedFrontendLexer_segment_items_node9_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6980 = some 1 := by
  cbv

theorem verifiedFrontendLexer_segment_items_node9_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6980 0 = some 477 := by
  cbv

theorem verifiedFrontendLexer_segment_items_node9_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6980 1 = some 6979 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_segment9_kernel :
    (reconstructItems 6982 verifiedFrontendLexerArtifact 6980).run 43 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 9, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_segment_items_node9_production_kernel,
    verifiedFrontendLexer_segment_items_node9_item_kernel,
    verifiedFrontendLexer_segment_items_node9_rest_kernel,
    verifiedFrontendLexer_reconstruct_item9_kernel,
    verifiedFrontendLexer_reconstruct_items_segment10_kernel,
    verifiedFrontendLexer_segment_proposed_items_drop9_kernel]

theorem verifiedFrontendLexer_segment_proposed_items_drop8_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 8 =
      verifiedFrontendLexerProposedItem8Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 9 := by
  rfl

theorem verifiedFrontendLexer_segment_items_node8_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6981 = some 1 := by
  cbv

theorem verifiedFrontendLexer_segment_items_node8_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6981 0 = some 261 := by
  cbv

theorem verifiedFrontendLexer_segment_items_node8_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6981 1 = some 6980 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_segment8_kernel :
    (reconstructItems 6983 verifiedFrontendLexerArtifact 6981).run 38 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 8, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_segment_items_node8_production_kernel,
    verifiedFrontendLexer_segment_items_node8_item_kernel,
    verifiedFrontendLexer_segment_items_node8_rest_kernel,
    verifiedFrontendLexer_reconstruct_item8_kernel,
    verifiedFrontendLexer_reconstruct_items_segment9_kernel,
    verifiedFrontendLexer_segment_proposed_items_drop8_kernel]

theorem verifiedFrontendLexer_segment_proposed_items_drop7_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 7 =
      verifiedFrontendLexerProposedItem7Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 8 := by
  rfl

theorem verifiedFrontendLexer_segment_items_node7_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6982 = some 1 := by
  cbv

theorem verifiedFrontendLexer_segment_items_node7_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6982 0 = some 226 := by
  cbv

theorem verifiedFrontendLexer_segment_items_node7_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6982 1 = some 6981 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_segment7_kernel :
    (reconstructItems 6984 verifiedFrontendLexerArtifact 6982).run 33 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 7, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_segment_items_node7_production_kernel,
    verifiedFrontendLexer_segment_items_node7_item_kernel,
    verifiedFrontendLexer_segment_items_node7_rest_kernel,
    verifiedFrontendLexer_reconstruct_item7_kernel,
    verifiedFrontendLexer_reconstruct_items_segment8_kernel,
    verifiedFrontendLexer_segment_proposed_items_drop7_kernel]

end Lanius.Extraction

