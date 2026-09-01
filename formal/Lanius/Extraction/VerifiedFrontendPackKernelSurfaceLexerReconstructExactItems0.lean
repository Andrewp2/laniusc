import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerProposedItems

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_reconstruct_item0_exact_kernel :
    (reconstructItem 6991 verifiedFrontendLexerArtifact 6).run 0 =
      some (verifiedFrontendLexerProposedItem0Kernel, 4) := by
  cbv

theorem verifiedFrontendLexer_reconstruct_item1_exact_kernel :
    (reconstructItem 6990 verifiedFrontendLexerArtifact 16).run 4 =
      some (verifiedFrontendLexerProposedItem1Kernel, 8) := by
  cbv

theorem verifiedFrontendLexer_reconstruct_item2_exact_kernel :
    (reconstructItem 6989 verifiedFrontendLexerArtifact 51).run 8 =
      some (verifiedFrontendLexerProposedItem2Kernel, 13) := by
  cbv

theorem verifiedFrontendLexer_reconstruct_item3_exact_kernel :
    (reconstructItem 6988 verifiedFrontendLexerArtifact 86).run 13 =
      some (verifiedFrontendLexerProposedItem3Kernel, 18) := by
  cbv

theorem verifiedFrontendLexer_reconstruct_item4_exact_kernel :
    (reconstructItem 6987 verifiedFrontendLexerArtifact 121).run 18 =
      some (verifiedFrontendLexerProposedItem4Kernel, 23) := by
  cbv

theorem verifiedFrontendLexer_reconstruct_item5_exact_kernel :
    (reconstructItem 6986 verifiedFrontendLexerArtifact 156).run 23 =
      some (verifiedFrontendLexerProposedItem5Kernel, 28) := by
  cbv

theorem verifiedFrontendLexer_reconstruct_item6_exact_kernel :
    (reconstructItem 6985 verifiedFrontendLexerArtifact 191).run 28 =
      some (verifiedFrontendLexerProposedItem6Kernel, 33) := by
  cbv

theorem verifiedFrontendLexer_reconstruct_item7_exact_kernel :
    (reconstructItem 6984 verifiedFrontendLexerArtifact 226).run 33 =
      some (verifiedFrontendLexerProposedItem7Kernel, 38) := by
  cbv

theorem verifiedFrontendLexer_reconstruct_item8_exact_kernel :
    (reconstructItem 6983 verifiedFrontendLexerArtifact 261).run 38 =
      some (verifiedFrontendLexerProposedItem8Kernel, 43) := by
  cbv

theorem verifiedFrontendLexer_reconstruct_item9_exact_kernel :
    (reconstructItem 6982 verifiedFrontendLexerArtifact 477).run 43 =
      some (verifiedFrontendLexerProposedItem9Kernel, 81) := by
  cbv

theorem verifiedFrontendLexer_reconstruct_item10_exact_kernel :
    (reconstructItem 6981 verifiedFrontendLexerArtifact 627).run 81 =
      some (verifiedFrontendLexerProposedItem10Kernel, 105) := by
  cbv

theorem verifiedFrontendLexer_reconstruct_item11_exact_kernel :
    (reconstructItem 6980 verifiedFrontendLexerArtifact 729).run 105 =
      some (verifiedFrontendLexerProposedItem11Kernel, 125) := by
  cbv

theorem verifiedFrontendLexer_reconstruct_item12_exact_kernel :
    (reconstructItem 6979 verifiedFrontendLexerArtifact 917).run 125 =
      some (verifiedFrontendLexerProposedItem12Kernel, 157) := by
  cbv

end Lanius.Extraction
