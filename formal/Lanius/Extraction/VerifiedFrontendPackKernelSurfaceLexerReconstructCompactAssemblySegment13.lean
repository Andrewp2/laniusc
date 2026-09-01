import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructCompactAssemblySegment14

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_segment_proposed_items_drop13_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 13 =
      verifiedFrontendLexerProposedItem13Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 14 := by
  rfl

theorem verifiedFrontendLexer_segment_items_node13_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6976 = some 1 := by
  cbv

theorem verifiedFrontendLexer_segment_items_node13_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6976 0 = some 1905 := by
  cbv

theorem verifiedFrontendLexer_segment_items_node13_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6976 1 = some 6975 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_segment13_kernel :
    (reconstructItems 6978 verifiedFrontendLexerArtifact 6976).run 157 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 13, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_segment_items_node13_production_kernel,
    verifiedFrontendLexer_segment_items_node13_item_kernel,
    verifiedFrontendLexer_segment_items_node13_rest_kernel,
    verifiedFrontendLexer_reconstruct_item13_kernel,
    verifiedFrontendLexer_reconstruct_items_segment14_kernel,
    verifiedFrontendLexer_segment_proposed_items_drop13_kernel]

end Lanius.Extraction

