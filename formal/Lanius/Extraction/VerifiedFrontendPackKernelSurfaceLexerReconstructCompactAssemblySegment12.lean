import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructCompactAssemblySegment13

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_segment_proposed_items_drop12_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 12 =
      verifiedFrontendLexerProposedItem12Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 13 := by
  rfl

theorem verifiedFrontendLexer_segment_items_node12_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6977 = some 1 := by
  cbv

theorem verifiedFrontendLexer_segment_items_node12_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6977 0 = some 917 := by
  cbv

theorem verifiedFrontendLexer_segment_items_node12_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6977 1 = some 6976 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_segment12_kernel :
    (reconstructItems 6979 verifiedFrontendLexerArtifact 6977).run 125 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 12, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_segment_items_node12_production_kernel,
    verifiedFrontendLexer_segment_items_node12_item_kernel,
    verifiedFrontendLexer_segment_items_node12_rest_kernel,
    verifiedFrontendLexer_reconstruct_item12_kernel,
    verifiedFrontendLexer_reconstruct_items_segment13_kernel,
    verifiedFrontendLexer_segment_proposed_items_drop12_kernel]

theorem verifiedFrontendLexer_segment_proposed_items_drop11_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 11 =
      verifiedFrontendLexerProposedItem11Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 12 := by
  rfl

theorem verifiedFrontendLexer_segment_items_node11_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6978 = some 1 := by
  cbv

theorem verifiedFrontendLexer_segment_items_node11_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6978 0 = some 729 := by
  cbv

theorem verifiedFrontendLexer_segment_items_node11_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6978 1 = some 6977 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_segment11_kernel :
    (reconstructItems 6980 verifiedFrontendLexerArtifact 6978).run 105 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 11, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_segment_items_node11_production_kernel,
    verifiedFrontendLexer_segment_items_node11_item_kernel,
    verifiedFrontendLexer_segment_items_node11_rest_kernel,
    verifiedFrontendLexer_reconstruct_item11_kernel,
    verifiedFrontendLexer_reconstruct_items_segment12_kernel,
    verifiedFrontendLexer_segment_proposed_items_drop11_kernel]

theorem verifiedFrontendLexer_segment_proposed_items_drop10_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 10 =
      verifiedFrontendLexerProposedItem10Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 11 := by
  rfl

theorem verifiedFrontendLexer_segment_items_node10_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6979 = some 1 := by
  cbv

theorem verifiedFrontendLexer_segment_items_node10_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6979 0 = some 627 := by
  cbv

theorem verifiedFrontendLexer_segment_items_node10_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6979 1 = some 6978 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_segment10_kernel :
    (reconstructItems 6981 verifiedFrontendLexerArtifact 6979).run 81 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 10, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_segment_items_node10_production_kernel,
    verifiedFrontendLexer_segment_items_node10_item_kernel,
    verifiedFrontendLexer_segment_items_node10_rest_kernel,
    verifiedFrontendLexer_reconstruct_item10_kernel,
    verifiedFrontendLexer_reconstruct_items_segment11_kernel,
    verifiedFrontendLexer_segment_proposed_items_drop10_kernel]

end Lanius.Extraction

