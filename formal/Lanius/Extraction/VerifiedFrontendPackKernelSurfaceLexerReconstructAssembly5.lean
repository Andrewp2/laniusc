import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructAssembly

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_items_node26_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6963 = some 1 := by
  cbv

theorem verifiedFrontendLexer_items_node26_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6963 0 = some 6417 := by
  cbv

theorem verifiedFrontendLexer_items_node26_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6963 1 = some 6962 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items26_kernel :
    (reconstructItems 6965 verifiedFrontendLexerArtifact 6963).run 963 =
      some ([verifiedFrontendLexerProposedItem26Kernel, verifiedFrontendLexerProposedItem27Kernel], 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_items_node26_production_kernel,
    verifiedFrontendLexer_items_node26_item_kernel,
    verifiedFrontendLexer_items_node26_rest_kernel,
    verifiedFrontendLexer_reconstruct_item26_kernel,
    verifiedFrontendLexer_reconstruct_items27_kernel]

theorem verifiedFrontendLexer_items_node25_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6964 = some 1 := by
  cbv

theorem verifiedFrontendLexer_items_node25_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6964 0 = some 6118 := by
  cbv

theorem verifiedFrontendLexer_items_node25_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6964 1 = some 6963 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items25_kernel :
    (reconstructItems 6966 verifiedFrontendLexerArtifact 6964).run 931 =
      some ([verifiedFrontendLexerProposedItem25Kernel, verifiedFrontendLexerProposedItem26Kernel, verifiedFrontendLexerProposedItem27Kernel], 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_items_node25_production_kernel,
    verifiedFrontendLexer_items_node25_item_kernel,
    verifiedFrontendLexer_items_node25_rest_kernel,
    verifiedFrontendLexer_reconstruct_item25_kernel,
    verifiedFrontendLexer_reconstruct_items26_kernel]

end Lanius.Extraction

