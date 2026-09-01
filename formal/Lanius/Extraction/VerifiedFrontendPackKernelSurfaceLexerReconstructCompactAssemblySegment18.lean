import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructCompactAssemblySegment21

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_segment_proposed_items_drop18_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 18 =
      verifiedFrontendLexerProposedItem18Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 19 := by
  rfl

theorem verifiedFrontendLexer_segment_items_node18_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6971 = some 1 := by
  cbv

theorem verifiedFrontendLexer_segment_items_node18_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6971 0 = some 4418 := by
  cbv

theorem verifiedFrontendLexer_segment_items_node18_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6971 1 = some 6970 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_segment18_kernel :
    (reconstructItems 6973 verifiedFrontendLexerArtifact 6971).run 692 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 18, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_segment_items_node18_production_kernel,
    verifiedFrontendLexer_segment_items_node18_item_kernel,
    verifiedFrontendLexer_segment_items_node18_rest_kernel,
    verifiedFrontendLexer_reconstruct_item18_kernel,
    verifiedFrontendLexer_reconstruct_items_segment19_kernel,
    verifiedFrontendLexer_segment_proposed_items_drop18_kernel]

theorem verifiedFrontendLexer_segment_proposed_items_drop17_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 17 =
      verifiedFrontendLexerProposedItem17Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 18 := by
  rfl

theorem verifiedFrontendLexer_segment_items_node17_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6972 = some 1 := by
  cbv

theorem verifiedFrontendLexer_segment_items_node17_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6972 0 = some 4362 := by
  cbv

theorem verifiedFrontendLexer_segment_items_node17_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6972 1 = some 6971 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_segment17_kernel :
    (reconstructItems 6974 verifiedFrontendLexerArtifact 6972).run 679 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 17, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_segment_items_node17_production_kernel,
    verifiedFrontendLexer_segment_items_node17_item_kernel,
    verifiedFrontendLexer_segment_items_node17_rest_kernel,
    verifiedFrontendLexer_reconstruct_item17_kernel,
    verifiedFrontendLexer_reconstruct_items_segment18_kernel,
    verifiedFrontendLexer_segment_proposed_items_drop17_kernel]

theorem verifiedFrontendLexer_segment_proposed_items_drop16_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 16 =
      verifiedFrontendLexerProposedItem16Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 17 := by
  rfl

theorem verifiedFrontendLexer_segment_items_node16_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6973 = some 1 := by
  cbv

theorem verifiedFrontendLexer_segment_items_node16_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6973 0 = some 4332 := by
  cbv

theorem verifiedFrontendLexer_segment_items_node16_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6973 1 = some 6972 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_segment16_kernel :
    (reconstructItems 6975 verifiedFrontendLexerArtifact 6973).run 623 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 16, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_segment_items_node16_production_kernel,
    verifiedFrontendLexer_segment_items_node16_item_kernel,
    verifiedFrontendLexer_segment_items_node16_rest_kernel,
    verifiedFrontendLexer_reconstruct_item16_kernel,
    verifiedFrontendLexer_reconstruct_items_segment17_kernel,
    verifiedFrontendLexer_segment_proposed_items_drop16_kernel]

end Lanius.Extraction

