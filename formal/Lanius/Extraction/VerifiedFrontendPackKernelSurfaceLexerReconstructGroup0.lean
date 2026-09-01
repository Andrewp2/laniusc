import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructBase

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_proposed_item0_present_kernel :
    (verifiedFrontendLexerProposedItemsKernel[0]?).isSome = true := by
  cbv

def verifiedFrontendLexerProposedItem0Kernel :=
  (verifiedFrontendLexerProposedItemsKernel[0]?).get
    verifiedFrontendLexer_proposed_item0_present_kernel

theorem verifiedFrontendLexer_reconstruct_item0_kernel :
    (reconstructItem 6990 verifiedFrontendLexerArtifact 6).run 0 =
      some (verifiedFrontendLexerProposedItem0Kernel, 4) := by
  cbv

theorem verifiedFrontendLexer_proposed_item1_present_kernel :
    (verifiedFrontendLexerProposedItemsKernel[1]?).isSome = true := by
  cbv

def verifiedFrontendLexerProposedItem1Kernel :=
  (verifiedFrontendLexerProposedItemsKernel[1]?).get
    verifiedFrontendLexer_proposed_item1_present_kernel

theorem verifiedFrontendLexer_reconstruct_item1_kernel :
    (reconstructItem 6989 verifiedFrontendLexerArtifact 16).run 4 =
      some (verifiedFrontendLexerProposedItem1Kernel, 8) := by
  cbv

theorem verifiedFrontendLexer_proposed_item2_present_kernel :
    (verifiedFrontendLexerProposedItemsKernel[2]?).isSome = true := by
  cbv

def verifiedFrontendLexerProposedItem2Kernel :=
  (verifiedFrontendLexerProposedItemsKernel[2]?).get
    verifiedFrontendLexer_proposed_item2_present_kernel

theorem verifiedFrontendLexer_reconstruct_item2_kernel :
    (reconstructItem 6988 verifiedFrontendLexerArtifact 51).run 8 =
      some (verifiedFrontendLexerProposedItem2Kernel, 13) := by
  cbv

theorem verifiedFrontendLexer_proposed_item3_present_kernel :
    (verifiedFrontendLexerProposedItemsKernel[3]?).isSome = true := by
  cbv

def verifiedFrontendLexerProposedItem3Kernel :=
  (verifiedFrontendLexerProposedItemsKernel[3]?).get
    verifiedFrontendLexer_proposed_item3_present_kernel

theorem verifiedFrontendLexer_reconstruct_item3_kernel :
    (reconstructItem 6987 verifiedFrontendLexerArtifact 86).run 13 =
      some (verifiedFrontendLexerProposedItem3Kernel, 18) := by
  cbv

theorem verifiedFrontendLexer_proposed_item4_present_kernel :
    (verifiedFrontendLexerProposedItemsKernel[4]?).isSome = true := by
  cbv

def verifiedFrontendLexerProposedItem4Kernel :=
  (verifiedFrontendLexerProposedItemsKernel[4]?).get
    verifiedFrontendLexer_proposed_item4_present_kernel

theorem verifiedFrontendLexer_reconstruct_item4_kernel :
    (reconstructItem 6986 verifiedFrontendLexerArtifact 121).run 18 =
      some (verifiedFrontendLexerProposedItem4Kernel, 23) := by
  cbv

theorem verifiedFrontendLexer_proposed_item5_present_kernel :
    (verifiedFrontendLexerProposedItemsKernel[5]?).isSome = true := by
  cbv

def verifiedFrontendLexerProposedItem5Kernel :=
  (verifiedFrontendLexerProposedItemsKernel[5]?).get
    verifiedFrontendLexer_proposed_item5_present_kernel

theorem verifiedFrontendLexer_reconstruct_item5_kernel :
    (reconstructItem 6985 verifiedFrontendLexerArtifact 156).run 23 =
      some (verifiedFrontendLexerProposedItem5Kernel, 28) := by
  cbv

theorem verifiedFrontendLexer_proposed_item6_present_kernel :
    (verifiedFrontendLexerProposedItemsKernel[6]?).isSome = true := by
  cbv

def verifiedFrontendLexerProposedItem6Kernel :=
  (verifiedFrontendLexerProposedItemsKernel[6]?).get
    verifiedFrontendLexer_proposed_item6_present_kernel

theorem verifiedFrontendLexer_reconstruct_item6_kernel :
    (reconstructItem 6984 verifiedFrontendLexerArtifact 191).run 28 =
      some (verifiedFrontendLexerProposedItem6Kernel, 33) := by
  cbv

theorem verifiedFrontendLexer_proposed_item7_present_kernel :
    (verifiedFrontendLexerProposedItemsKernel[7]?).isSome = true := by
  cbv

def verifiedFrontendLexerProposedItem7Kernel :=
  (verifiedFrontendLexerProposedItemsKernel[7]?).get
    verifiedFrontendLexer_proposed_item7_present_kernel

theorem verifiedFrontendLexer_reconstruct_item7_kernel :
    (reconstructItem 6983 verifiedFrontendLexerArtifact 226).run 33 =
      some (verifiedFrontendLexerProposedItem7Kernel, 38) := by
  cbv

theorem verifiedFrontendLexer_proposed_item8_present_kernel :
    (verifiedFrontendLexerProposedItemsKernel[8]?).isSome = true := by
  cbv

def verifiedFrontendLexerProposedItem8Kernel :=
  (verifiedFrontendLexerProposedItemsKernel[8]?).get
    verifiedFrontendLexer_proposed_item8_present_kernel

theorem verifiedFrontendLexer_reconstruct_item8_kernel :
    (reconstructItem 6982 verifiedFrontendLexerArtifact 261).run 38 =
      some (verifiedFrontendLexerProposedItem8Kernel, 43) := by
  cbv

theorem verifiedFrontendLexer_proposed_item9_present_kernel :
    (verifiedFrontendLexerProposedItemsKernel[9]?).isSome = true := by
  cbv

def verifiedFrontendLexerProposedItem9Kernel :=
  (verifiedFrontendLexerProposedItemsKernel[9]?).get
    verifiedFrontendLexer_proposed_item9_present_kernel

theorem verifiedFrontendLexer_reconstruct_item9_kernel :
    (reconstructItem 6981 verifiedFrontendLexerArtifact 477).run 43 =
      some (verifiedFrontendLexerProposedItem9Kernel, 81) := by
  cbv

theorem verifiedFrontendLexer_proposed_item10_present_kernel :
    (verifiedFrontendLexerProposedItemsKernel[10]?).isSome = true := by
  cbv

def verifiedFrontendLexerProposedItem10Kernel :=
  (verifiedFrontendLexerProposedItemsKernel[10]?).get
    verifiedFrontendLexer_proposed_item10_present_kernel

theorem verifiedFrontendLexer_reconstruct_item10_kernel :
    (reconstructItem 6980 verifiedFrontendLexerArtifact 627).run 81 =
      some (verifiedFrontendLexerProposedItem10Kernel, 105) := by
  cbv

theorem verifiedFrontendLexer_proposed_item11_present_kernel :
    (verifiedFrontendLexerProposedItemsKernel[11]?).isSome = true := by
  cbv

def verifiedFrontendLexerProposedItem11Kernel :=
  (verifiedFrontendLexerProposedItemsKernel[11]?).get
    verifiedFrontendLexer_proposed_item11_present_kernel

theorem verifiedFrontendLexer_reconstruct_item11_kernel :
    (reconstructItem 6979 verifiedFrontendLexerArtifact 729).run 105 =
      some (verifiedFrontendLexerProposedItem11Kernel, 125) := by
  cbv

theorem verifiedFrontendLexer_proposed_item12_present_kernel :
    (verifiedFrontendLexerProposedItemsKernel[12]?).isSome = true := by
  cbv

def verifiedFrontendLexerProposedItem12Kernel :=
  (verifiedFrontendLexerProposedItemsKernel[12]?).get
    verifiedFrontendLexer_proposed_item12_present_kernel

theorem verifiedFrontendLexer_reconstruct_item12_kernel :
    (reconstructItem 6978 verifiedFrontendLexerArtifact 917).run 125 =
      some (verifiedFrontendLexerProposedItem12Kernel, 157) := by
  cbv

end Lanius.Extraction

