import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructCompactAssembly4

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_proposed_items_drop21_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 21 =
      verifiedFrontendLexerProposedItem21Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 22 := by
  rfl

theorem verifiedFrontendLexer_compact_items_node21_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6968 = some 1 := by
  cbv

theorem verifiedFrontendLexer_compact_items_node21_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6968 0 = some 4678 := by
  cbv

theorem verifiedFrontendLexer_compact_items_node21_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6968 1 = some 6967 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_compact21_kernel :
    (reconstructItems 6970 verifiedFrontendLexerArtifact 6968).run 731 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 21, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_compact_items_node21_production_kernel,
    verifiedFrontendLexer_compact_items_node21_item_kernel,
    verifiedFrontendLexer_compact_items_node21_rest_kernel,
    verifiedFrontendLexer_reconstruct_item21_kernel,
    verifiedFrontendLexer_reconstruct_items_compact22_kernel,
    verifiedFrontendLexer_proposed_items_drop21_kernel]

theorem verifiedFrontendLexer_proposed_items_drop20_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 20 =
      verifiedFrontendLexerProposedItem20Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 21 := by
  rfl

theorem verifiedFrontendLexer_compact_items_node20_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6969 = some 1 := by
  cbv

theorem verifiedFrontendLexer_compact_items_node20_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6969 0 = some 4530 := by
  cbv

theorem verifiedFrontendLexer_compact_items_node20_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6969 1 = some 6968 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_compact20_kernel :
    (reconstructItems 6971 verifiedFrontendLexerArtifact 6969).run 718 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 20, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_compact_items_node20_production_kernel,
    verifiedFrontendLexer_compact_items_node20_item_kernel,
    verifiedFrontendLexer_compact_items_node20_rest_kernel,
    verifiedFrontendLexer_reconstruct_item20_kernel,
    verifiedFrontendLexer_reconstruct_items_compact21_kernel,
    verifiedFrontendLexer_proposed_items_drop20_kernel]

theorem verifiedFrontendLexer_proposed_items_drop19_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 19 =
      verifiedFrontendLexerProposedItem19Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 20 := by
  rfl

theorem verifiedFrontendLexer_compact_items_node19_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6970 = some 1 := by
  cbv

theorem verifiedFrontendLexer_compact_items_node19_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6970 0 = some 4474 := by
  cbv

theorem verifiedFrontendLexer_compact_items_node19_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6970 1 = some 6969 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_compact19_kernel :
    (reconstructItems 6972 verifiedFrontendLexerArtifact 6970).run 705 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 19, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_compact_items_node19_production_kernel,
    verifiedFrontendLexer_compact_items_node19_item_kernel,
    verifiedFrontendLexer_compact_items_node19_rest_kernel,
    verifiedFrontendLexer_reconstruct_item19_kernel,
    verifiedFrontendLexer_reconstruct_items_compact20_kernel,
    verifiedFrontendLexer_proposed_items_drop19_kernel]

theorem verifiedFrontendLexer_proposed_items_drop18_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 18 =
      verifiedFrontendLexerProposedItem18Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 19 := by
  rfl

theorem verifiedFrontendLexer_compact_items_node18_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6971 = some 1 := by
  cbv

theorem verifiedFrontendLexer_compact_items_node18_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6971 0 = some 4418 := by
  cbv

theorem verifiedFrontendLexer_compact_items_node18_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6971 1 = some 6970 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_compact18_kernel :
    (reconstructItems 6973 verifiedFrontendLexerArtifact 6971).run 692 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 18, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_compact_items_node18_production_kernel,
    verifiedFrontendLexer_compact_items_node18_item_kernel,
    verifiedFrontendLexer_compact_items_node18_rest_kernel,
    verifiedFrontendLexer_reconstruct_item18_kernel,
    verifiedFrontendLexer_reconstruct_items_compact19_kernel,
    verifiedFrontendLexer_proposed_items_drop18_kernel]

theorem verifiedFrontendLexer_proposed_items_drop17_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 17 =
      verifiedFrontendLexerProposedItem17Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 18 := by
  rfl

theorem verifiedFrontendLexer_compact_items_node17_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6972 = some 1 := by
  cbv

theorem verifiedFrontendLexer_compact_items_node17_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6972 0 = some 4362 := by
  cbv

theorem verifiedFrontendLexer_compact_items_node17_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6972 1 = some 6971 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_compact17_kernel :
    (reconstructItems 6974 verifiedFrontendLexerArtifact 6972).run 679 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 17, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_compact_items_node17_production_kernel,
    verifiedFrontendLexer_compact_items_node17_item_kernel,
    verifiedFrontendLexer_compact_items_node17_rest_kernel,
    verifiedFrontendLexer_reconstruct_item17_kernel,
    verifiedFrontendLexer_reconstruct_items_compact18_kernel,
    verifiedFrontendLexer_proposed_items_drop17_kernel]

theorem verifiedFrontendLexer_proposed_items_drop16_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 16 =
      verifiedFrontendLexerProposedItem16Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 17 := by
  rfl

theorem verifiedFrontendLexer_compact_items_node16_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6973 = some 1 := by
  cbv

theorem verifiedFrontendLexer_compact_items_node16_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6973 0 = some 4332 := by
  cbv

theorem verifiedFrontendLexer_compact_items_node16_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6973 1 = some 6972 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_compact16_kernel :
    (reconstructItems 6975 verifiedFrontendLexerArtifact 6973).run 623 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 16, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_compact_items_node16_production_kernel,
    verifiedFrontendLexer_compact_items_node16_item_kernel,
    verifiedFrontendLexer_compact_items_node16_rest_kernel,
    verifiedFrontendLexer_reconstruct_item16_kernel,
    verifiedFrontendLexer_reconstruct_items_compact17_kernel,
    verifiedFrontendLexer_proposed_items_drop16_kernel]

theorem verifiedFrontendLexer_proposed_items_drop15_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 15 =
      verifiedFrontendLexerProposedItem15Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 16 := by
  rfl

theorem verifiedFrontendLexer_compact_items_node15_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6974 = some 1 := by
  cbv

theorem verifiedFrontendLexer_compact_items_node15_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6974 0 = some 4012 := by
  cbv

theorem verifiedFrontendLexer_compact_items_node15_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6974 1 = some 6973 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_compact15_kernel :
    (reconstructItems 6976 verifiedFrontendLexerArtifact 6974).run 567 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 15, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_compact_items_node15_production_kernel,
    verifiedFrontendLexer_compact_items_node15_item_kernel,
    verifiedFrontendLexer_compact_items_node15_rest_kernel,
    verifiedFrontendLexer_reconstruct_item15_kernel,
    verifiedFrontendLexer_reconstruct_items_compact16_kernel,
    verifiedFrontendLexer_proposed_items_drop15_kernel]

end Lanius.Extraction
