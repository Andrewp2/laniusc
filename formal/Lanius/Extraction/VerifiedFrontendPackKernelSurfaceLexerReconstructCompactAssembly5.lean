import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructAssembly5

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_proposed_items_drop28_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 28 = [] := by
  rfl

theorem verifiedFrontendLexer_reconstruct_items_compact_end_kernel :
    (reconstructItems 6963 verifiedFrontendLexerArtifact 6961).run 1107 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 28, 1107) := by
  rw [verifiedFrontendLexer_proposed_items_drop28_kernel]
  exact verifiedFrontendLexer_reconstruct_items_end_kernel

theorem verifiedFrontendLexer_proposed_items_drop27_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 27 =
      verifiedFrontendLexerProposedItem27Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 28 := by
  rfl

theorem verifiedFrontendLexer_compact_items_node27_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6962 = some 1 := by
  cbv

theorem verifiedFrontendLexer_compact_items_node27_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6962 0 = some 6960 := by
  cbv

theorem verifiedFrontendLexer_compact_items_node27_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6962 1 = some 6961 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_compact27_kernel :
    (reconstructItems 6964 verifiedFrontendLexerArtifact 6962).run 1017 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 27, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_compact_items_node27_production_kernel,
    verifiedFrontendLexer_compact_items_node27_item_kernel,
    verifiedFrontendLexer_compact_items_node27_rest_kernel,
    verifiedFrontendLexer_reconstruct_item27_kernel,
    verifiedFrontendLexer_reconstruct_items_compact_end_kernel,
    verifiedFrontendLexer_proposed_items_drop27_kernel]

theorem verifiedFrontendLexer_proposed_items_drop26_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 26 =
      verifiedFrontendLexerProposedItem26Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 27 := by
  rfl

theorem verifiedFrontendLexer_compact_items_node26_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6963 = some 1 := by
  cbv

theorem verifiedFrontendLexer_compact_items_node26_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6963 0 = some 6417 := by
  cbv

theorem verifiedFrontendLexer_compact_items_node26_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6963 1 = some 6962 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_compact26_kernel :
    (reconstructItems 6965 verifiedFrontendLexerArtifact 6963).run 963 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 26, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_compact_items_node26_production_kernel,
    verifiedFrontendLexer_compact_items_node26_item_kernel,
    verifiedFrontendLexer_compact_items_node26_rest_kernel,
    verifiedFrontendLexer_reconstruct_item26_kernel,
    verifiedFrontendLexer_reconstruct_items_compact27_kernel,
    verifiedFrontendLexer_proposed_items_drop26_kernel]

theorem verifiedFrontendLexer_proposed_items_drop25_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 25 =
      verifiedFrontendLexerProposedItem25Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 26 := by
  rfl

theorem verifiedFrontendLexer_compact_items_node25_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6964 = some 1 := by
  cbv

theorem verifiedFrontendLexer_compact_items_node25_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6964 0 = some 6118 := by
  cbv

theorem verifiedFrontendLexer_compact_items_node25_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6964 1 = some 6963 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_compact25_kernel :
    (reconstructItems 6966 verifiedFrontendLexerArtifact 6964).run 931 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 25, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_compact_items_node25_production_kernel,
    verifiedFrontendLexer_compact_items_node25_item_kernel,
    verifiedFrontendLexer_compact_items_node25_rest_kernel,
    verifiedFrontendLexer_reconstruct_item25_kernel,
    verifiedFrontendLexer_reconstruct_items_compact26_kernel,
    verifiedFrontendLexer_proposed_items_drop25_kernel]

end Lanius.Extraction
