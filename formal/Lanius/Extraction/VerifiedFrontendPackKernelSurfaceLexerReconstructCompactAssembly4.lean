import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructCompactAssembly5

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_proposed_items_drop24_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 24 =
      verifiedFrontendLexerProposedItem24Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 25 := by
  rfl

theorem verifiedFrontendLexer_compact_items_node24_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6965 = some 1 := by
  cbv

theorem verifiedFrontendLexer_compact_items_node24_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6965 0 = some 5916 := by
  cbv

theorem verifiedFrontendLexer_compact_items_node24_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6965 1 = some 6964 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_compact24_kernel :
    (reconstructItems 6967 verifiedFrontendLexerArtifact 6965).run 899 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 24, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_compact_items_node24_production_kernel,
    verifiedFrontendLexer_compact_items_node24_item_kernel,
    verifiedFrontendLexer_compact_items_node24_rest_kernel,
    verifiedFrontendLexer_reconstruct_item24_kernel,
    verifiedFrontendLexer_reconstruct_items_compact25_kernel,
    verifiedFrontendLexer_proposed_items_drop24_kernel]

theorem verifiedFrontendLexer_proposed_items_drop23_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 23 =
      verifiedFrontendLexerProposedItem23Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 24 := by
  rfl

theorem verifiedFrontendLexer_compact_items_node23_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6966 = some 1 := by
  cbv

theorem verifiedFrontendLexer_compact_items_node23_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6966 0 = some 5714 := by
  cbv

theorem verifiedFrontendLexer_compact_items_node23_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6966 1 = some 6965 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_compact23_kernel :
    (reconstructItems 6968 verifiedFrontendLexerArtifact 6966).run 771 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 23, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_compact_items_node23_production_kernel,
    verifiedFrontendLexer_compact_items_node23_item_kernel,
    verifiedFrontendLexer_compact_items_node23_rest_kernel,
    verifiedFrontendLexer_reconstruct_item23_kernel,
    verifiedFrontendLexer_reconstruct_items_compact24_kernel,
    verifiedFrontendLexer_proposed_items_drop23_kernel]

theorem verifiedFrontendLexer_proposed_items_drop22_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 22 =
      verifiedFrontendLexerProposedItem22Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 23 := by
  rfl

theorem verifiedFrontendLexer_compact_items_node22_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6967 = some 1 := by
  cbv

theorem verifiedFrontendLexer_compact_items_node22_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6967 0 = some 4826 := by
  cbv

theorem verifiedFrontendLexer_compact_items_node22_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6967 1 = some 6966 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_compact22_kernel :
    (reconstructItems 6969 verifiedFrontendLexerArtifact 6967).run 751 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 22, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_compact_items_node22_production_kernel,
    verifiedFrontendLexer_compact_items_node22_item_kernel,
    verifiedFrontendLexer_compact_items_node22_rest_kernel,
    verifiedFrontendLexer_reconstruct_item22_kernel,
    verifiedFrontendLexer_reconstruct_items_compact23_kernel,
    verifiedFrontendLexer_proposed_items_drop22_kernel]

end Lanius.Extraction
