import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructCompactAssemblySegment9

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_segment_proposed_items_drop6_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 6 =
      verifiedFrontendLexerProposedItem6Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 7 := by
  rfl

theorem verifiedFrontendLexer_segment_items_node6_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6983 = some 1 := by
  cbv

theorem verifiedFrontendLexer_segment_items_node6_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6983 0 = some 191 := by
  cbv

theorem verifiedFrontendLexer_segment_items_node6_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6983 1 = some 6982 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_segment6_kernel :
    (reconstructItems 6985 verifiedFrontendLexerArtifact 6983).run 28 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 6, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_segment_items_node6_production_kernel,
    verifiedFrontendLexer_segment_items_node6_item_kernel,
    verifiedFrontendLexer_segment_items_node6_rest_kernel,
    verifiedFrontendLexer_reconstruct_item6_kernel,
    verifiedFrontendLexer_reconstruct_items_segment7_kernel,
    verifiedFrontendLexer_segment_proposed_items_drop6_kernel]

theorem verifiedFrontendLexer_segment_proposed_items_drop5_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 5 =
      verifiedFrontendLexerProposedItem5Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 6 := by
  rfl

theorem verifiedFrontendLexer_segment_items_node5_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6984 = some 1 := by
  cbv

theorem verifiedFrontendLexer_segment_items_node5_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6984 0 = some 156 := by
  cbv

theorem verifiedFrontendLexer_segment_items_node5_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6984 1 = some 6983 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_segment5_kernel :
    (reconstructItems 6986 verifiedFrontendLexerArtifact 6984).run 23 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 5, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_segment_items_node5_production_kernel,
    verifiedFrontendLexer_segment_items_node5_item_kernel,
    verifiedFrontendLexer_segment_items_node5_rest_kernel,
    verifiedFrontendLexer_reconstruct_item5_kernel,
    verifiedFrontendLexer_reconstruct_items_segment6_kernel,
    verifiedFrontendLexer_segment_proposed_items_drop5_kernel]

theorem verifiedFrontendLexer_segment_proposed_items_drop4_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 4 =
      verifiedFrontendLexerProposedItem4Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 5 := by
  rfl

theorem verifiedFrontendLexer_segment_items_node4_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6985 = some 1 := by
  cbv

theorem verifiedFrontendLexer_segment_items_node4_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6985 0 = some 121 := by
  cbv

theorem verifiedFrontendLexer_segment_items_node4_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6985 1 = some 6984 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_segment4_kernel :
    (reconstructItems 6987 verifiedFrontendLexerArtifact 6985).run 18 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 4, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_segment_items_node4_production_kernel,
    verifiedFrontendLexer_segment_items_node4_item_kernel,
    verifiedFrontendLexer_segment_items_node4_rest_kernel,
    verifiedFrontendLexer_reconstruct_item4_kernel,
    verifiedFrontendLexer_reconstruct_items_segment5_kernel,
    verifiedFrontendLexer_segment_proposed_items_drop4_kernel]

end Lanius.Extraction

