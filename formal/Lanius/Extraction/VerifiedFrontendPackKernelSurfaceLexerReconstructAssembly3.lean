import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructAssembly4

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_items_node21_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6968 = some 1 := by
  cbv

theorem verifiedFrontendLexer_items_node21_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6968 0 = some 4678 := by
  cbv

theorem verifiedFrontendLexer_items_node21_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6968 1 = some 6967 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items21_kernel :
    (reconstructItems 6970 verifiedFrontendLexerArtifact 6968).run 731 =
      some ([verifiedFrontendLexerProposedItem21Kernel, verifiedFrontendLexerProposedItem22Kernel, verifiedFrontendLexerProposedItem23Kernel, verifiedFrontendLexerProposedItem24Kernel, verifiedFrontendLexerProposedItem25Kernel, verifiedFrontendLexerProposedItem26Kernel, verifiedFrontendLexerProposedItem27Kernel], 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_items_node21_production_kernel,
    verifiedFrontendLexer_items_node21_item_kernel,
    verifiedFrontendLexer_items_node21_rest_kernel,
    verifiedFrontendLexer_reconstruct_item21_kernel,
    verifiedFrontendLexer_reconstruct_items22_kernel]

theorem verifiedFrontendLexer_items_node20_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6969 = some 1 := by
  cbv

theorem verifiedFrontendLexer_items_node20_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6969 0 = some 4530 := by
  cbv

theorem verifiedFrontendLexer_items_node20_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6969 1 = some 6968 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items20_kernel :
    (reconstructItems 6971 verifiedFrontendLexerArtifact 6969).run 718 =
      some ([verifiedFrontendLexerProposedItem20Kernel, verifiedFrontendLexerProposedItem21Kernel, verifiedFrontendLexerProposedItem22Kernel, verifiedFrontendLexerProposedItem23Kernel, verifiedFrontendLexerProposedItem24Kernel, verifiedFrontendLexerProposedItem25Kernel, verifiedFrontendLexerProposedItem26Kernel, verifiedFrontendLexerProposedItem27Kernel], 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_items_node20_production_kernel,
    verifiedFrontendLexer_items_node20_item_kernel,
    verifiedFrontendLexer_items_node20_rest_kernel,
    verifiedFrontendLexer_reconstruct_item20_kernel,
    verifiedFrontendLexer_reconstruct_items21_kernel]

theorem verifiedFrontendLexer_items_node19_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6970 = some 1 := by
  cbv

theorem verifiedFrontendLexer_items_node19_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6970 0 = some 4474 := by
  cbv

theorem verifiedFrontendLexer_items_node19_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6970 1 = some 6969 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items19_kernel :
    (reconstructItems 6972 verifiedFrontendLexerArtifact 6970).run 705 =
      some ([verifiedFrontendLexerProposedItem19Kernel, verifiedFrontendLexerProposedItem20Kernel, verifiedFrontendLexerProposedItem21Kernel, verifiedFrontendLexerProposedItem22Kernel, verifiedFrontendLexerProposedItem23Kernel, verifiedFrontendLexerProposedItem24Kernel, verifiedFrontendLexerProposedItem25Kernel, verifiedFrontendLexerProposedItem26Kernel, verifiedFrontendLexerProposedItem27Kernel], 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_items_node19_production_kernel,
    verifiedFrontendLexer_items_node19_item_kernel,
    verifiedFrontendLexer_items_node19_rest_kernel,
    verifiedFrontendLexer_reconstruct_item19_kernel,
    verifiedFrontendLexer_reconstruct_items20_kernel]

theorem verifiedFrontendLexer_items_node18_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6971 = some 1 := by
  cbv

theorem verifiedFrontendLexer_items_node18_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6971 0 = some 4418 := by
  cbv

theorem verifiedFrontendLexer_items_node18_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6971 1 = some 6970 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items18_kernel :
    (reconstructItems 6973 verifiedFrontendLexerArtifact 6971).run 692 =
      some ([verifiedFrontendLexerProposedItem18Kernel, verifiedFrontendLexerProposedItem19Kernel, verifiedFrontendLexerProposedItem20Kernel, verifiedFrontendLexerProposedItem21Kernel, verifiedFrontendLexerProposedItem22Kernel, verifiedFrontendLexerProposedItem23Kernel, verifiedFrontendLexerProposedItem24Kernel, verifiedFrontendLexerProposedItem25Kernel, verifiedFrontendLexerProposedItem26Kernel, verifiedFrontendLexerProposedItem27Kernel], 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_items_node18_production_kernel,
    verifiedFrontendLexer_items_node18_item_kernel,
    verifiedFrontendLexer_items_node18_rest_kernel,
    verifiedFrontendLexer_reconstruct_item18_kernel,
    verifiedFrontendLexer_reconstruct_items19_kernel]

theorem verifiedFrontendLexer_items_node17_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6972 = some 1 := by
  cbv

theorem verifiedFrontendLexer_items_node17_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6972 0 = some 4362 := by
  cbv

theorem verifiedFrontendLexer_items_node17_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6972 1 = some 6971 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items17_kernel :
    (reconstructItems 6974 verifiedFrontendLexerArtifact 6972).run 679 =
      some ([verifiedFrontendLexerProposedItem17Kernel, verifiedFrontendLexerProposedItem18Kernel, verifiedFrontendLexerProposedItem19Kernel, verifiedFrontendLexerProposedItem20Kernel, verifiedFrontendLexerProposedItem21Kernel, verifiedFrontendLexerProposedItem22Kernel, verifiedFrontendLexerProposedItem23Kernel, verifiedFrontendLexerProposedItem24Kernel, verifiedFrontendLexerProposedItem25Kernel, verifiedFrontendLexerProposedItem26Kernel, verifiedFrontendLexerProposedItem27Kernel], 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_items_node17_production_kernel,
    verifiedFrontendLexer_items_node17_item_kernel,
    verifiedFrontendLexer_items_node17_rest_kernel,
    verifiedFrontendLexer_reconstruct_item17_kernel,
    verifiedFrontendLexer_reconstruct_items18_kernel]

theorem verifiedFrontendLexer_items_node16_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6973 = some 1 := by
  cbv

theorem verifiedFrontendLexer_items_node16_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6973 0 = some 4332 := by
  cbv

theorem verifiedFrontendLexer_items_node16_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6973 1 = some 6972 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items16_kernel :
    (reconstructItems 6975 verifiedFrontendLexerArtifact 6973).run 623 =
      some ([verifiedFrontendLexerProposedItem16Kernel, verifiedFrontendLexerProposedItem17Kernel, verifiedFrontendLexerProposedItem18Kernel, verifiedFrontendLexerProposedItem19Kernel, verifiedFrontendLexerProposedItem20Kernel, verifiedFrontendLexerProposedItem21Kernel, verifiedFrontendLexerProposedItem22Kernel, verifiedFrontendLexerProposedItem23Kernel, verifiedFrontendLexerProposedItem24Kernel, verifiedFrontendLexerProposedItem25Kernel, verifiedFrontendLexerProposedItem26Kernel, verifiedFrontendLexerProposedItem27Kernel], 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_items_node16_production_kernel,
    verifiedFrontendLexer_items_node16_item_kernel,
    verifiedFrontendLexer_items_node16_rest_kernel,
    verifiedFrontendLexer_reconstruct_item16_kernel,
    verifiedFrontendLexer_reconstruct_items17_kernel]

theorem verifiedFrontendLexer_items_node15_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6974 = some 1 := by
  cbv

theorem verifiedFrontendLexer_items_node15_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6974 0 = some 4012 := by
  cbv

theorem verifiedFrontendLexer_items_node15_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6974 1 = some 6973 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items15_kernel :
    (reconstructItems 6976 verifiedFrontendLexerArtifact 6974).run 567 =
      some ([verifiedFrontendLexerProposedItem15Kernel, verifiedFrontendLexerProposedItem16Kernel, verifiedFrontendLexerProposedItem17Kernel, verifiedFrontendLexerProposedItem18Kernel, verifiedFrontendLexerProposedItem19Kernel, verifiedFrontendLexerProposedItem20Kernel, verifiedFrontendLexerProposedItem21Kernel, verifiedFrontendLexerProposedItem22Kernel, verifiedFrontendLexerProposedItem23Kernel, verifiedFrontendLexerProposedItem24Kernel, verifiedFrontendLexerProposedItem25Kernel, verifiedFrontendLexerProposedItem26Kernel, verifiedFrontendLexerProposedItem27Kernel], 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_items_node15_production_kernel,
    verifiedFrontendLexer_items_node15_item_kernel,
    verifiedFrontendLexer_items_node15_rest_kernel,
    verifiedFrontendLexer_reconstruct_item15_kernel,
    verifiedFrontendLexer_reconstruct_items16_kernel]

end Lanius.Extraction

