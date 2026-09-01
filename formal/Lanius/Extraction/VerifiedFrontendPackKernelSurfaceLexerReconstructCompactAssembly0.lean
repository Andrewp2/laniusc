import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructCompactAssembly1

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_proposed_items_drop12_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 12 =
      verifiedFrontendLexerProposedItem12Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 13 := by
  rfl

theorem verifiedFrontendLexer_compact_items_node12_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6977 = some 1 := by
  cbv

theorem verifiedFrontendLexer_compact_items_node12_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6977 0 = some 917 := by
  cbv

theorem verifiedFrontendLexer_compact_items_node12_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6977 1 = some 6976 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_compact12_kernel :
    (reconstructItems 6979 verifiedFrontendLexerArtifact 6977).run 125 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 12, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_compact_items_node12_production_kernel,
    verifiedFrontendLexer_compact_items_node12_item_kernel,
    verifiedFrontendLexer_compact_items_node12_rest_kernel,
    verifiedFrontendLexer_reconstruct_item12_kernel,
    verifiedFrontendLexer_reconstruct_items_compact13_kernel,
    verifiedFrontendLexer_proposed_items_drop12_kernel]

theorem verifiedFrontendLexer_proposed_items_drop11_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 11 =
      verifiedFrontendLexerProposedItem11Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 12 := by
  rfl

theorem verifiedFrontendLexer_compact_items_node11_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6978 = some 1 := by
  cbv

theorem verifiedFrontendLexer_compact_items_node11_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6978 0 = some 729 := by
  cbv

theorem verifiedFrontendLexer_compact_items_node11_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6978 1 = some 6977 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_compact11_kernel :
    (reconstructItems 6980 verifiedFrontendLexerArtifact 6978).run 105 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 11, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_compact_items_node11_production_kernel,
    verifiedFrontendLexer_compact_items_node11_item_kernel,
    verifiedFrontendLexer_compact_items_node11_rest_kernel,
    verifiedFrontendLexer_reconstruct_item11_kernel,
    verifiedFrontendLexer_reconstruct_items_compact12_kernel,
    verifiedFrontendLexer_proposed_items_drop11_kernel]

theorem verifiedFrontendLexer_proposed_items_drop10_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 10 =
      verifiedFrontendLexerProposedItem10Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 11 := by
  rfl

theorem verifiedFrontendLexer_compact_items_node10_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6979 = some 1 := by
  cbv

theorem verifiedFrontendLexer_compact_items_node10_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6979 0 = some 627 := by
  cbv

theorem verifiedFrontendLexer_compact_items_node10_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6979 1 = some 6978 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_compact10_kernel :
    (reconstructItems 6981 verifiedFrontendLexerArtifact 6979).run 81 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 10, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_compact_items_node10_production_kernel,
    verifiedFrontendLexer_compact_items_node10_item_kernel,
    verifiedFrontendLexer_compact_items_node10_rest_kernel,
    verifiedFrontendLexer_reconstruct_item10_kernel,
    verifiedFrontendLexer_reconstruct_items_compact11_kernel,
    verifiedFrontendLexer_proposed_items_drop10_kernel]

theorem verifiedFrontendLexer_proposed_items_drop9_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 9 =
      verifiedFrontendLexerProposedItem9Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 10 := by
  rfl

theorem verifiedFrontendLexer_compact_items_node9_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6980 = some 1 := by
  cbv

theorem verifiedFrontendLexer_compact_items_node9_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6980 0 = some 477 := by
  cbv

theorem verifiedFrontendLexer_compact_items_node9_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6980 1 = some 6979 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_compact9_kernel :
    (reconstructItems 6982 verifiedFrontendLexerArtifact 6980).run 43 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 9, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_compact_items_node9_production_kernel,
    verifiedFrontendLexer_compact_items_node9_item_kernel,
    verifiedFrontendLexer_compact_items_node9_rest_kernel,
    verifiedFrontendLexer_reconstruct_item9_kernel,
    verifiedFrontendLexer_reconstruct_items_compact10_kernel,
    verifiedFrontendLexer_proposed_items_drop9_kernel]

theorem verifiedFrontendLexer_proposed_items_drop8_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 8 =
      verifiedFrontendLexerProposedItem8Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 9 := by
  rfl

theorem verifiedFrontendLexer_compact_items_node8_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6981 = some 1 := by
  cbv

theorem verifiedFrontendLexer_compact_items_node8_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6981 0 = some 261 := by
  cbv

theorem verifiedFrontendLexer_compact_items_node8_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6981 1 = some 6980 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_compact8_kernel :
    (reconstructItems 6983 verifiedFrontendLexerArtifact 6981).run 38 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 8, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_compact_items_node8_production_kernel,
    verifiedFrontendLexer_compact_items_node8_item_kernel,
    verifiedFrontendLexer_compact_items_node8_rest_kernel,
    verifiedFrontendLexer_reconstruct_item8_kernel,
    verifiedFrontendLexer_reconstruct_items_compact9_kernel,
    verifiedFrontendLexer_proposed_items_drop8_kernel]

theorem verifiedFrontendLexer_proposed_items_drop7_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 7 =
      verifiedFrontendLexerProposedItem7Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 8 := by
  rfl

theorem verifiedFrontendLexer_compact_items_node7_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6982 = some 1 := by
  cbv

theorem verifiedFrontendLexer_compact_items_node7_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6982 0 = some 226 := by
  cbv

theorem verifiedFrontendLexer_compact_items_node7_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6982 1 = some 6981 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_compact7_kernel :
    (reconstructItems 6984 verifiedFrontendLexerArtifact 6982).run 33 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 7, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_compact_items_node7_production_kernel,
    verifiedFrontendLexer_compact_items_node7_item_kernel,
    verifiedFrontendLexer_compact_items_node7_rest_kernel,
    verifiedFrontendLexer_reconstruct_item7_kernel,
    verifiedFrontendLexer_reconstruct_items_compact8_kernel,
    verifiedFrontendLexer_proposed_items_drop7_kernel]

theorem verifiedFrontendLexer_proposed_items_drop6_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 6 =
      verifiedFrontendLexerProposedItem6Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 7 := by
  rfl

theorem verifiedFrontendLexer_compact_items_node6_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6983 = some 1 := by
  cbv

theorem verifiedFrontendLexer_compact_items_node6_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6983 0 = some 191 := by
  cbv

theorem verifiedFrontendLexer_compact_items_node6_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6983 1 = some 6982 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_compact6_kernel :
    (reconstructItems 6985 verifiedFrontendLexerArtifact 6983).run 28 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 6, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_compact_items_node6_production_kernel,
    verifiedFrontendLexer_compact_items_node6_item_kernel,
    verifiedFrontendLexer_compact_items_node6_rest_kernel,
    verifiedFrontendLexer_reconstruct_item6_kernel,
    verifiedFrontendLexer_reconstruct_items_compact7_kernel,
    verifiedFrontendLexer_proposed_items_drop6_kernel]

theorem verifiedFrontendLexer_proposed_items_drop5_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 5 =
      verifiedFrontendLexerProposedItem5Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 6 := by
  rfl

theorem verifiedFrontendLexer_compact_items_node5_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6984 = some 1 := by
  cbv

theorem verifiedFrontendLexer_compact_items_node5_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6984 0 = some 156 := by
  cbv

theorem verifiedFrontendLexer_compact_items_node5_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6984 1 = some 6983 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_compact5_kernel :
    (reconstructItems 6986 verifiedFrontendLexerArtifact 6984).run 23 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 5, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_compact_items_node5_production_kernel,
    verifiedFrontendLexer_compact_items_node5_item_kernel,
    verifiedFrontendLexer_compact_items_node5_rest_kernel,
    verifiedFrontendLexer_reconstruct_item5_kernel,
    verifiedFrontendLexer_reconstruct_items_compact6_kernel,
    verifiedFrontendLexer_proposed_items_drop5_kernel]

theorem verifiedFrontendLexer_proposed_items_drop4_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 4 =
      verifiedFrontendLexerProposedItem4Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 5 := by
  rfl

theorem verifiedFrontendLexer_compact_items_node4_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6985 = some 1 := by
  cbv

theorem verifiedFrontendLexer_compact_items_node4_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6985 0 = some 121 := by
  cbv

theorem verifiedFrontendLexer_compact_items_node4_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6985 1 = some 6984 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_compact4_kernel :
    (reconstructItems 6987 verifiedFrontendLexerArtifact 6985).run 18 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 4, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_compact_items_node4_production_kernel,
    verifiedFrontendLexer_compact_items_node4_item_kernel,
    verifiedFrontendLexer_compact_items_node4_rest_kernel,
    verifiedFrontendLexer_reconstruct_item4_kernel,
    verifiedFrontendLexer_reconstruct_items_compact5_kernel,
    verifiedFrontendLexer_proposed_items_drop4_kernel]

theorem verifiedFrontendLexer_proposed_items_drop3_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 3 =
      verifiedFrontendLexerProposedItem3Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 4 := by
  rfl

theorem verifiedFrontendLexer_compact_items_node3_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6986 = some 1 := by
  cbv

theorem verifiedFrontendLexer_compact_items_node3_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6986 0 = some 86 := by
  cbv

theorem verifiedFrontendLexer_compact_items_node3_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6986 1 = some 6985 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_compact3_kernel :
    (reconstructItems 6988 verifiedFrontendLexerArtifact 6986).run 13 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 3, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_compact_items_node3_production_kernel,
    verifiedFrontendLexer_compact_items_node3_item_kernel,
    verifiedFrontendLexer_compact_items_node3_rest_kernel,
    verifiedFrontendLexer_reconstruct_item3_kernel,
    verifiedFrontendLexer_reconstruct_items_compact4_kernel,
    verifiedFrontendLexer_proposed_items_drop3_kernel]

theorem verifiedFrontendLexer_proposed_items_drop2_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 2 =
      verifiedFrontendLexerProposedItem2Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 3 := by
  rfl

theorem verifiedFrontendLexer_compact_items_node2_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6987 = some 1 := by
  cbv

theorem verifiedFrontendLexer_compact_items_node2_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6987 0 = some 51 := by
  cbv

theorem verifiedFrontendLexer_compact_items_node2_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6987 1 = some 6986 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_compact2_kernel :
    (reconstructItems 6989 verifiedFrontendLexerArtifact 6987).run 8 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 2, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_compact_items_node2_production_kernel,
    verifiedFrontendLexer_compact_items_node2_item_kernel,
    verifiedFrontendLexer_compact_items_node2_rest_kernel,
    verifiedFrontendLexer_reconstruct_item2_kernel,
    verifiedFrontendLexer_reconstruct_items_compact3_kernel,
    verifiedFrontendLexer_proposed_items_drop2_kernel]

theorem verifiedFrontendLexer_proposed_items_drop1_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 1 =
      verifiedFrontendLexerProposedItem1Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 2 := by
  rfl

theorem verifiedFrontendLexer_compact_items_node1_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6988 = some 1 := by
  cbv

theorem verifiedFrontendLexer_compact_items_node1_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6988 0 = some 16 := by
  cbv

theorem verifiedFrontendLexer_compact_items_node1_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6988 1 = some 6987 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_compact1_kernel :
    (reconstructItems 6990 verifiedFrontendLexerArtifact 6988).run 4 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 1, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_compact_items_node1_production_kernel,
    verifiedFrontendLexer_compact_items_node1_item_kernel,
    verifiedFrontendLexer_compact_items_node1_rest_kernel,
    verifiedFrontendLexer_reconstruct_item1_kernel,
    verifiedFrontendLexer_reconstruct_items_compact2_kernel,
    verifiedFrontendLexer_proposed_items_drop1_kernel]

theorem verifiedFrontendLexer_proposed_items_drop0_kernel :
    verifiedFrontendLexerProposedItemsKernel.drop 0 =
      verifiedFrontendLexerProposedItem0Kernel ::
        verifiedFrontendLexerProposedItemsKernel.drop 1 := by
  rfl

theorem verifiedFrontendLexer_compact_items_node0_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6989 = some 1 := by
  cbv

theorem verifiedFrontendLexer_compact_items_node0_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6989 0 = some 6 := by
  cbv

theorem verifiedFrontendLexer_compact_items_node0_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6989 1 = some 6988 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items_compact0_kernel :
    (reconstructItems 6991 verifiedFrontendLexerArtifact 6989).run 0 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 0, 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_compact_items_node0_production_kernel,
    verifiedFrontendLexer_compact_items_node0_item_kernel,
    verifiedFrontendLexer_compact_items_node0_rest_kernel,
    verifiedFrontendLexer_reconstruct_item0_kernel,
    verifiedFrontendLexer_reconstruct_items_compact1_kernel,
    verifiedFrontendLexer_proposed_items_drop0_kernel]

end Lanius.Extraction
