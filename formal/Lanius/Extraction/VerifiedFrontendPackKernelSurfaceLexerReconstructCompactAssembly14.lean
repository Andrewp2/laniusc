import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructCompactAssembly3

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_proposed_items_drop14_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 14 =
      verifiedFrontendLexerProposedItem14Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 15 := by
  rfl

theorem verifiedFrontendLexer_compact_items_node14_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6975 = some 1 := by
  cbv

theorem verifiedFrontendLexer_compact_items_node14_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6975 0 = some 3692 := by
  cbv

theorem verifiedFrontendLexer_compact_items_node14_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6975 1 = some 6974 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_compact14_kernel :
    (reconstructItems 6977 verifiedFrontendLexerArtifact 6975).run 309 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 14, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_compact_items_node14_production_kernel,
    verifiedFrontendLexer_compact_items_node14_item_kernel,
    verifiedFrontendLexer_compact_items_node14_rest_kernel,
    verifiedFrontendLexer_reconstruct_item14_kernel,
    verifiedFrontendLexer_reconstruct_items_compact15_kernel,
    verifiedFrontendLexer_proposed_items_drop14_kernel]

end Lanius.Extraction
