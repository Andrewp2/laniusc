import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructCompactAssemblySegment6

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_segment_proposed_items_drop3_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 3 =
      verifiedFrontendLexerProposedItem3Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 4 := by
  rfl

theorem verifiedFrontendLexer_segment_items_node3_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6986 = some 1 := by
  cbv

theorem verifiedFrontendLexer_segment_items_node3_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6986 0 = some 86 := by
  cbv

theorem verifiedFrontendLexer_segment_items_node3_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6986 1 = some 6985 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_segment3_kernel :
    (reconstructItems 6988 verifiedFrontendLexerArtifact 6986).run 13 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 3, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_segment_items_node3_production_kernel,
    verifiedFrontendLexer_segment_items_node3_item_kernel,
    verifiedFrontendLexer_segment_items_node3_rest_kernel,
    verifiedFrontendLexer_reconstruct_item3_kernel,
    verifiedFrontendLexer_reconstruct_items_segment4_kernel,
    verifiedFrontendLexer_segment_proposed_items_drop3_kernel]

theorem verifiedFrontendLexer_segment_proposed_items_drop2_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 2 =
      verifiedFrontendLexerProposedItem2Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 3 := by
  rfl

theorem verifiedFrontendLexer_segment_items_node2_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6987 = some 1 := by
  cbv

theorem verifiedFrontendLexer_segment_items_node2_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6987 0 = some 51 := by
  cbv

theorem verifiedFrontendLexer_segment_items_node2_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6987 1 = some 6986 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_segment2_kernel :
    (reconstructItems 6989 verifiedFrontendLexerArtifact 6987).run 8 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 2, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_segment_items_node2_production_kernel,
    verifiedFrontendLexer_segment_items_node2_item_kernel,
    verifiedFrontendLexer_segment_items_node2_rest_kernel,
    verifiedFrontendLexer_reconstruct_item2_kernel,
    verifiedFrontendLexer_reconstruct_items_segment3_kernel,
    verifiedFrontendLexer_segment_proposed_items_drop2_kernel]

theorem verifiedFrontendLexer_segment_proposed_items_drop1_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 1 =
      verifiedFrontendLexerProposedItem1Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 2 := by
  rfl

theorem verifiedFrontendLexer_segment_items_node1_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6988 = some 1 := by
  cbv

theorem verifiedFrontendLexer_segment_items_node1_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6988 0 = some 16 := by
  cbv

theorem verifiedFrontendLexer_segment_items_node1_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6988 1 = some 6987 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_segment1_kernel :
    (reconstructItems 6990 verifiedFrontendLexerArtifact 6988).run 4 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 1, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_segment_items_node1_production_kernel,
    verifiedFrontendLexer_segment_items_node1_item_kernel,
    verifiedFrontendLexer_segment_items_node1_rest_kernel,
    verifiedFrontendLexer_reconstruct_item1_kernel,
    verifiedFrontendLexer_reconstruct_items_segment2_kernel,
    verifiedFrontendLexer_segment_proposed_items_drop1_kernel]

end Lanius.Extraction

